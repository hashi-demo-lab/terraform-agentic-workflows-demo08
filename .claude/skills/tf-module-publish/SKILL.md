---
name: tf-module-publish
description: >
  Publish a Terraform module to HCP Terraform's Private Module Registry (PMR) via GitHub Actions.
  Covers per-module PMR setup (repo naming, VCS-connected module creation, labels, variables,
  token verification), README preparation, and the repeatable PR-merge-publish cycle. Use this
  skill when the user wants to publish a module to the private registry, set up the release
  pipeline for a new module, configure module publishing, create semver labels, or verify that the
  release workflow is working. Also trigger when the user says things like "publish to PMR", "set
  up the release pipeline", "module is stuck in pending", "configure module publishing", "last
  mile", or references the module_release/module_validate GitHub Actions workflows.
user-invocable: true
argument-hint: "[module-name] - Set up and publish module to HCP Terraform PMR"
---

# Terraform Module Publish to PMR

After `/tf-module-implement` produces a validated module on a feature branch, this skill handles the **last mile** — configuring HCP Terraform and GitHub so that merging the PR automatically publishes the module to the Private Module Registry (PMR).

The template repo ships with two GitHub Actions workflows that handle CI/CD:
- `module_validate.yml` — runs on PRs (fmt, validate, tflint, trivy, unit tests, terraform-docs)
- `module_release.yml` — runs on merge to main (version calculation, PMR version creation, git tag, GitHub Release)

The module is registered in PMR as a **VCS-connected, branch-based** module. PMR is linked to the GitHub repo via GitHub App and fetches source code directly from the configured branch — no tarball upload is needed.

This skill covers the **per-module setup** that those workflows depend on.

## Workflow

### Step 1: Resolve module coordinates

Determine the values the release pipeline needs:

- **TFE_ORG** — the HCP Terraform organization name (e.g., `hashi-demos-apj`)
- **TFE_MODULE** — the module name, matching the Terraform naming convention (e.g., `bedrock-agentcore`)
- **TFE_PROVIDER** — the provider the module targets (e.g., `aws`)

Derive these from the repo context — check `versions.tf` for the required provider, and ask the user for the org name if not already known.

### Step 2: Ensure the repo follows the naming convention

The repo **must** be named `terraform-{provider}-{module-name}` (e.g., `terraform-aws-bedrock-agentcore`). This is required for VCS-connected PMR modules — HCP Terraform derives the module name and provider from the repo name.

If the repo needs renaming:
```bash
gh api "repos/OWNER/CURRENT-NAME" -X PATCH -f name="terraform-<provider>-<module-name>"
# Update local remote
git remote set-url origin https://github.com/OWNER/terraform-<provider>-<module-name>.git
```

GitHub automatically redirects the old URL, but local git remotes need updating.

### Step 3: Create semver labels

The validation workflow enforces exactly one semver label per PR. Create all three if they don't already exist:

```bash
gh label create "semver:patch" --color "0e8a16" --description "Patch version bump"
gh label create "semver:minor" --color "1d76db" --description "Minor version bump"
gh label create "semver:major" --color "d93f0b" --description "Major version bump"
```

Labels are repo-scoped — `gh label create` errors on duplicates (safe to ignore).

### Step 4: Set repository variables

The release workflow reads module coordinates from repository variables (not secrets) so they appear in logs. Use the API form since `gh variable set` requires gh >= 2.35.0:

```bash
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
gh api "repos/$REPO/actions/variables" -X POST -f name=TFE_ORG -f value="<org-name>"
gh api "repos/$REPO/actions/variables" -X POST -f name=TFE_MODULE -f value="<module-name>"
gh api "repos/$REPO/actions/variables" -X POST -f name=TFE_PROVIDER -f value="<provider-name>"
```

To update existing variables, use `-X PATCH` on `repos/$REPO/actions/variables/TFE_MODULE` instead of `-X POST`.

### Step 5: Verify TFE_TOKEN permissions

The `TFE_TOKEN` GitHub secret must have **Manage Modules** permission on the HCP Terraform organization. A token with only `Traverse` or `Create Workspaces` will cause the version calculator (read-only) to succeed but the publish step (write) to fail with HTTP 404 — a confusing partial failure where the workflow reports the correct version number but then can't create it.

If the user can provide the token value, verify it directly:
```bash
curl -s -H "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/organizations/<org>/registry-modules" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Modules visible: {len(d.get(\"data\",[]))}')"
```

If not, confirm with the user that the secret has the right scope. This is the most common cause of release workflow failures.

### Step 6: Create the VCS-connected module in PMR

The module must be registered in PMR with a VCS connection to the GitHub repo. This uses the **VCS endpoint** (not the plain registry-modules endpoint which creates API-driven modules without source metadata).

First, find the GitHub App installation ID for the org:
```bash
curl -s -H "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/organizations/<org>/github-app-installations" \
  | python3 -c "import sys,json; d=json.load(sys.stdin)['data'][0]; print(f'ID: {d[\"id\"]}, Name: {d[\"attributes\"][\"name\"]}')"
```

Then create the module with VCS connection, branch-based publishing, tracking `main`:
```bash
curl -s \
  -H "Authorization: Bearer $TFE_TOKEN" \
  -H "Content-Type: application/vnd.api+json" \
  -X POST \
  "https://app.terraform.io/api/v2/organizations/<org>/registry-modules/vcs" \
  -d '{
    "data": {
      "type": "registry-modules",
      "attributes": {
        "vcs-repo": {
          "identifier": "<github-org>/terraform-<provider>-<module-name>",
          "display-identifier": "<github-org>/terraform-<provider>-<module-name>",
          "github-app-installation-id": "<ghain-xxx>",
          "branch": "main",
          "tags": false
        },
        "no-code": false
      }
    }
  }'
```

Key points:
- Use the `/registry-modules/vcs` endpoint, NOT `/registry-modules` (which creates non-VCS modules)
- `display-identifier` is required — set it to the same value as `identifier`
- `branch: "main"` and `tags: false` configures branch-based publishing
- The module name and provider are derived from the repo name (`terraform-{provider}-{name}`)
- The module starts in `pending` status — it resolves when the first version is published

Verify via `mcp__terraform__search_private_modules`. The PMR UI should now show Source, Branch, and Commit metadata.

### Step 7: Prepare the README

PMR ingests the root README directly from the VCS-connected repo. `terraform-docs` only manages content between `<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->` markers — everything above those markers is static prose that must be written manually.

Before publishing, verify the README describes the **module**, not the template repo. It should include:
- Module title and one-line description
- Features list
- Usage examples (basic + advanced) with the PMR source path
- Prerequisites (provider version, required AWS permissions/resources)
- Security defaults table

The `/tf-module-implement` pipeline does not rewrite the prose README — this step must be done explicitly.

### Step 8: Add semver label and verify the pipeline

1. Add `semver:minor` label to the PR (first release). Use the REST API to avoid GitHub Projects (Classic) errors:
   ```bash
   gh api "repos/OWNER/REPO/issues/PR_NUMBER/labels" -X POST --input - <<< '{"labels":["semver:minor"]}'
   ```
2. Confirm `module_validate.yml` triggers and passes
3. If `terraform-docs` pushes a commit, run `git pull --rebase` before any local pushes
4. After human review, merge the PR
5. Confirm `module_release.yml` triggers, creates version in PMR, creates git tag and GitHub Release
6. Verify via `mcp__terraform__get_private_module_details` — confirm Source/Branch/Commit metadata is populated

## Troubleshooting

### Module stuck in `pending` status

For VCS-connected modules, `pending` means no version has been published yet. Create the first version by merging a PR with a semver label. If the release workflow already ran, check the logs for errors.

For non-VCS (API-driven) modules, `pending` means a version was created but the tarball was never uploaded. This indicates the module was created via the wrong API endpoint — delete it and recreate using the `/registry-modules/vcs` endpoint (Step 6).

### PMR shows no Source/Branch/Commit metadata

The module was created via the plain `/registry-modules` endpoint (API-driven, `non_vcs`) instead of the `/registry-modules/vcs` endpoint. The `publishing-mechanism` cannot be changed after creation. Delete the module and recreate it with a VCS connection (Step 6).

### Release workflow fails at "Publish Module Version" (HTTP 404)

The `TFE_TOKEN` secret lacks `Manage Modules` permission. Update the secret and re-run the workflow — re-runs pick up updated secrets immediately.

### Release workflow fails at "Determine Release Type"

The merged PR had no semver label. Cannot auto-recover (PR is closed). Either create a no-op PR with the correct label, or run the publish scripts manually with environment variables set.

### terraform-docs causes push conflicts

The validation workflow pushes a docs commit to the PR branch. Local pushes after that are rejected. Always `git pull --rebase` before pushing to a branch with an active validation workflow.

### Re-running a partially failed release

If the release failed after the PMR version was created (e.g., git tag step failed), re-running will fail with 422 (duplicate version). Either delete the pending version via API first, or complete the remaining steps (tag, release) manually.

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
