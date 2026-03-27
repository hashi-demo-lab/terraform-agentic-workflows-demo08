---
name: tf-module-publish
description: >
  Publish a Terraform module to HCP Terraform's Private Module Registry (PMR) via GitHub Actions.
  Covers one-time PMR setup (labels, variables, module entity, token verification) and the
  repeatable PR-merge-publish cycle. Use this skill when the user wants to publish a module to
  the private registry, set up CI/CD for module releases, configure the PMR publishing pipeline,
  create semver labels, or verify that the release workflow is working. Also trigger when the user
  says things like "publish to PMR", "set up the release pipeline", "module is stuck in pending",
  "configure module publishing", "last mile", or references the module_release/module_validate
  GitHub Actions workflows.
user-invocable: true
argument-hint: "[module-name] - Set up and publish module to HCP Terraform PMR"
---

# Terraform Module Publish to PMR

After `/tf-module-implement` produces a validated module on a feature branch, this skill handles the **last mile** — setting up and operating the CI/CD pipeline that publishes module versions to HCP Terraform's Private Module Registry (PMR).

The pipeline has two GitHub Actions workflows:
- `module_validate.yml` — runs on PRs (fmt, validate, tflint, trivy, unit tests, terraform-docs)
- `module_release.yml` — runs on merge to main (version calculation, PMR publish, git tag, GitHub Release)

## Workflow

### Step 1: Determine what's needed

Check the current state of the repository to decide which setup steps are required:

```bash
# Check if workflows exist
ls .github/workflows/module_validate.yml .github/workflows/module_release.yml 2>/dev/null

# Check if Python publish scripts exist
ls .github/workflows/get_module_version.py .github/workflows/publish_module_version.py 2>/dev/null

# Check if semver labels exist (requires gh auth)
gh label list --search "semver"

# Check if repo variables are set
gh api "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/actions/variables" --jq '.variables[].name'
```

If all artifacts exist, skip to Step 5 (verify). Otherwise, proceed through the missing steps.

### Step 2: One-time GitHub setup

#### Semver labels

The validation workflow enforces exactly one semver label per PR. Create all three:

```bash
gh label create "semver:patch" --color "0e8a16" --description "Patch version bump"
gh label create "semver:minor" --color "1d76db" --description "Minor version bump"
gh label create "semver:major" --color "d93f0b" --description "Major version bump"
```

Labels are repo-scoped — if they already exist, `gh label create` will error (safe to ignore). Use `--force` to update existing labels.

#### Repository variables

The release workflow reads module coordinates from repository variables (not secrets) so they appear in logs. The `gh variable set` subcommand requires gh >= 2.35.0 — older versions need the API fallback:

```bash
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
gh api "repos/$REPO/actions/variables" -X POST -f name=TFE_ORG -f value="<org-name>"
gh api "repos/$REPO/actions/variables" -X POST -f name=TFE_MODULE -f value="<module-name>"
gh api "repos/$REPO/actions/variables" -X POST -f name=TFE_PROVIDER -f value="<provider-name>"
```

#### TFE_TOKEN secret

The `TFE_TOKEN` GitHub secret must have **Manage Modules** permission on the HCP Terraform organization. A token with only `Traverse` or `Create Workspaces` will cause the version calculator (read-only) to succeed but the publish step (write) to fail with HTTP 404 — a confusing partial failure. Always verify the token can both read AND write module versions.

### Step 3: Create the module entity in PMR

Before any version can be published, the module shell must exist in PMR. This is a one-time API call. The module starts in `pending` status until the first version is published with a tarball upload.

```bash
curl -s \
  -H "Authorization: Bearer $TFE_TOKEN" \
  -H "Content-Type: application/vnd.api+json" \
  -X POST \
  "https://app.terraform.io/api/v2/organizations/<org>/registry-modules" \
  -d '{
    "data": {
      "type": "registry-modules",
      "attributes": {
        "name": "<module-name>",
        "provider": "<provider>",
        "registry-name": "private",
        "no-code": false
      }
    }
  }'
```

The API returns `422` if the module already exists (safe to retry). Verify the module entity exists via the `mcp__terraform__search_private_modules` tool.

### Step 4: Create workflow files (if missing)

The pipeline requires five files in `.github/workflows/`:

| File | Purpose |
|------|---------|
| `module_validate.yml` | PR validation (fmt, init, validate, tflint, trivy, unit tests, terraform-docs, example matrix) |
| `module_release.yml` | On merge: version calculation, PMR publish with tarball upload, git tag, GitHub Release |
| `get_module_version.py` | Queries PMR API for current version, returns incremented version based on semver label |
| `publish_module_version.py` | Three-step publish: create version record, package tarball, upload to pre-signed URL |
| `requirements.txt` | `requests==2.31.0`, `packaging==24.0` |

Key design decisions in these workflows:

- **Unit tests are blocking** (not `continue-on-error`) — PRs cannot merge with failing tests
- **Example validation** runs as a separate matrix job (parallel, not sequential)
- **Trivy** must use `v` prefix and version `>= v0.35.0` — older versions have broken transitive dependencies
- **terraform-docs** with `git-push: true` auto-commits README updates to the PR branch
- **terraform init** uses `-backend=false` to avoid cloud backend configuration in CI
- **Tarball upload is mandatory** — for API-driven (non-VCS) modules, creating a version record only returns an upload URL; the module tarball must be PUT to that URL or the version stays in `pending` status forever

### Step 5: Verify end-to-end

Run through this checklist to confirm the pipeline works:

1. **Labels**: `gh label list --search "semver"` shows all three labels
2. **Variables**: `gh api "repos/$REPO/actions/variables" --jq '.variables[].name'` shows `TFE_ORG`, `TFE_MODULE`, `TFE_PROVIDER`
3. **TFE_TOKEN**: Verify the secret can manage modules:
   ```bash
   curl -s -H "Authorization: Bearer $TFE_TOKEN" \
     "https://app.terraform.io/api/v2/organizations/<org>/registry-modules" \
     | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Modules visible: {len(d.get(\"data\",[]))}')"
   ```
4. **Module entity**: Use `mcp__terraform__search_private_modules` to confirm the module exists in PMR
5. **Validate workflow**: Push a change to a PR branch that touches `.tf` files, confirm `module_validate.yml` triggers
6. **Release workflow**: Merge a PR with a semver label, confirm `module_release.yml` publishes to PMR
7. **PMR version**: Use `mcp__terraform__get_private_module_details` to confirm the version is accessible

### Step 6: README verification

Before publishing, verify the root README describes the **module** (features, usage examples, prerequisites, security controls), not the framework or template repo that generated it. `terraform-docs` only manages content between `<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->` markers — everything above those markers is static prose that PMR ingests verbatim from the uploaded tarball. A framework-focused README will confuse module consumers.

## Troubleshooting

### Module stuck in `pending` status

The module entity was created but no version has been successfully published with a tarball. Either:
- No version has been created yet (check `version-statuses` in the API response)
- A version was created but the tarball was not uploaded (the `publish_module_version.py` script must perform the three-step flow: create version, package tarball, upload to pre-signed URL)

To fix manually:
```bash
# Create a version and get the upload URL
RESPONSE=$(curl -s -H "Authorization: Bearer $TFE_TOKEN" \
  -H "Content-Type: application/vnd.api+json" -X POST \
  "https://app.terraform.io/api/v2/organizations/<org>/registry-modules/private/<org>/<module>/<provider>/versions" \
  -d '{"data":{"type":"registry-module-versions","attributes":{"version":"0.1.0","commit-sha":"'$(git rev-parse HEAD)'"}}}')

UPLOAD_URL=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['links']['upload'])")

# Package and upload
tar -czf /tmp/module.tar.gz --exclude='.git' --exclude='.github' --exclude='specs' --exclude='.claude' --exclude='__pycache__' --exclude='.terraform' .
curl -s -H "Content-Type: application/octet-stream" -X PUT --data-binary @/tmp/module.tar.gz "$UPLOAD_URL"
```

### Release workflow fails at "Publish Module Version"

Check the `TFE_TOKEN` GitHub secret permissions. HTTP 404 on the create-version API call means the token lacks `Manage Modules` permission. Update the secret with a properly-scoped token and re-run the workflow.

### Release workflow fails at "Determine Release Type"

The merged PR had no semver label. This cannot be auto-recovered — the PR is closed. Either:
- Create a no-op PR with the correct label to trigger a new release
- Run the version calculator and publish scripts manually with environment variables set

### terraform-docs causes push conflicts

The validation workflow's `terraform-docs` step pushes a commit to the PR branch. If you push locally after that, git will reject with "remote contains work that you do not have locally." Always `git pull --rebase` before pushing to a branch with an active validation workflow.

### Trivy action fails at "Set up job"

The `aquasecurity/trivy-action` tag must use the `v` prefix (e.g., `v0.35.0` not `0.35.0`). Versions below `v0.29.0` have a broken transitive dependency on `aquasecurity/setup-trivy`. Use `v0.35.0` or later.

### `gh pr edit --add-label` fails

Repos with GitHub Projects (Classic) get a GraphQL deprecation error. Use the REST API:
```bash
gh api "repos/OWNER/REPO/issues/PR_NUMBER/labels" -X POST --input - <<< '{"labels":["semver:minor"]}'
```

## Semver label guidelines

| Change Type | Label | First Version |
|-------------|-------|---------------|
| New module | `semver:minor` | `0.1.0` |
| Add optional variable/output | `semver:minor` | — |
| Add new resource | `semver:minor` | — |
| Bug fix | `semver:patch` | — |
| Update provider constraint | `semver:patch` | — |
| Remove/rename variable | `semver:major` | — |
| Change default (breaking) | `semver:major` | — |
| Remove output | `semver:major` | — |

## Reference

Full operational guide with all e2e findings: `specs/bedrock-agentcore/last-mile-operations.md`
