# Last Mile: Module Publishing Pipeline — Order of Operations

## Context

After `/tf-module-implement` completes (code written, tests pass, validation score meets threshold), the module lives on a feature branch with no way to reach consumers. This document covers the **last mile** — the one-time setup and repeatable publish flow that gets a validated module into HCP Terraform's Private Module Registry (PMR).

This pipeline is designed to execute automatically via GitHub Actions once a PR is approved and merged by a human reviewer.

**Validated**: 2026-03-27 — Full e2e run completed successfully. Module `hashi-demos-apj/bedrock-agentcore/aws` published as `v0.2.0` to PMR via automated pipeline.

---

## One-Time Setup (Per Module)

These steps must be completed **once** before the first PR merge can publish. They require GitHub repository admin access and an HCP Terraform API token.

### Step 1: Create GitHub Semver Labels

The validation workflow enforces that every PR carries exactly one semver label. These must exist in the repository.

```bash
gh label create "semver:patch" --color "0e8a16" --description "Patch version bump"
gh label create "semver:minor" --color "1d76db" --description "Minor version bump"
gh label create "semver:major" --color "d93f0b" --description "Major version bump"
```

**Finding**: Labels are repository-scoped. If the repo already has these labels from a prior module, this step is a no-op. The `gh label create` command will error on duplicates — use `--force` to update existing labels.

### Step 2: Set GitHub Repository Variables

The release workflow reads module coordinates from repository variables (not secrets) so they appear in logs for debuggability.

```bash
# gh variable set requires gh >= 2.35.0; older versions need the API:
REPO="owner/repo"
gh api "repos/$REPO/actions/variables" -X POST -f name=TFE_ORG -f value=hashi-demos-apj
gh api "repos/$REPO/actions/variables" -X POST -f name=TFE_MODULE -f value=bedrock-agentcore
gh api "repos/$REPO/actions/variables" -X POST -f name=TFE_PROVIDER -f value=aws
```

**Finding**: `TFE_TOKEN` must already exist as a **repository secret** (not a variable). This token needs `Manage Modules` permission on the HCP Terraform organization.

**Lesson (from e2e)**: The `gh variable set` subcommand does not exist in older `gh` CLI versions (< 2.35.0). The devcontainer ships an older version. Use the `gh api` form shown above as a reliable fallback.

**Finding**: If this repo hosts multiple modules in the future, these variables would need to become workflow-level inputs or matrix values. The current design assumes one module per repo.

### Step 3: Create the Module Entity in PMR

Before any version can be published, the module shell must exist in PMR. This is an API-only operation (no VCS connection).

```bash
curl -s \
  -H "Authorization: Bearer $TFE_TOKEN" \
  -H "Content-Type: application/vnd.api+json" \
  -X POST \
  "https://app.terraform.io/api/v2/organizations/hashi-demos-apj/registry-modules" \
  -d '{
    "data": {
      "type": "registry-modules",
      "attributes": {
        "name": "bedrock-agentcore",
        "provider": "aws",
        "registry-name": "private",
        "no-code": false
      }
    }
  }'
```

**Finding**: The API returns `422 Unprocessable Entity` if the module already exists. This is safe to retry. The response includes the module ID needed for subsequent version publishes.

**Finding**: The `registry-name` must be `"private"` for PMR. The `no-code` attribute controls whether the module appears in the no-code provisioning UI — set to `false` for infrastructure modules.

**Lesson (from e2e)**: After creation, the module status is `pending` until the first version is successfully published with a tarball upload. This is normal — the status transitions to `setup_complete` after the first version's tarball is accepted.

### Step 4: Verify `TFE_TOKEN` Permissions

The token used in the release workflow needs:
- **Manage Modules** — to create versions and upload tarballs via API
- The token must be a **Team** or **Organization** token, not a User token, for CI reliability

```bash
# Quick verification — list modules visible to the token
curl -s \
  -H "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/organizations/hashi-demos-apj/registry-modules" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Modules visible: {len(d.get(\"data\",[]))}')"
```

**Lesson (CRITICAL, from e2e)**: The `TFE_TOKEN` stored as a GitHub secret **must** have `Manage Modules` permission. During our e2e run, the release workflow failed with `HTTP 404` on the create-version API call because the original secret was a low-privilege token with only `Traverse` + `Create Workspaces`. The version calculator step succeeded (it only reads), but the publish step failed (it writes). Always verify the secret token can both read AND write module versions before relying on the pipeline.

**Lesson (from e2e)**: The MCP-configured Terraform token (used by the `terraform` MCP server) may have different permissions than the `TFE_TOKEN` GitHub secret. These are separate tokens — verify each independently.

---

## Repeatable Flow (Every Module Release)

This is the automated pipeline that executes on every PR targeting `main`.

### Phase A: PR Validation (`module_validate.yml`)

**Trigger**: Any PR that touches `*.tf`, `*.tfvars`, `*.tftest.hcl` files, or `workflow_dispatch`

```
┌─────────────────────────────────────────────────────────┐
│  PR opened/updated on feature branch                     │
│                                                          │
│  1. Checkout (PR head ref)                               │
│  2. Semver label check (exactly 1 of patch/minor/major)  │
│  3. terraform fmt -check -recursive           [blocking] │
│  4. terraform init -backend=false             [blocking] │
│  5. terraform validate                        [blocking] │
│  6. tflint --init && tflint --format compact  [warning]  │
│  7. trivy scan (CRITICAL,HIGH)                [warning]  │
│  8. terraform test (4 unit test files)        [blocking] │
│  9. terraform-docs (auto-push to PR branch)              │
│ 10. Summary table → GitHub Step Summary                  │
│                                                          │
│  Parallel: validate-examples matrix (basic, complete)    │
└─────────────────────────────────────────────────────────┘
```

**Finding**: The semver label check runs **before** any Terraform steps. If no label is applied, the workflow fails fast without consuming runner minutes on validation.

**Finding**: Unit tests are **blocking** (unlike the reference template which uses `continue-on-error`). This means a PR cannot merge with failing tests. This is intentional — the module has 35 passing tests and we want to maintain that bar.

**Lesson (from e2e)**: `terraform-docs` with `git-push: true` pushes a commit to the PR branch if `README.md` needs updating. This caused a push conflict when we tried to push locally after the workflow had already pushed a docs commit. Always `git pull --rebase` before pushing to a branch with an active validation workflow. The workflow may also trigger a second run — the second run is expected and lightweight.

**Lesson (IMPORTANT, from e2e)**: `terraform-docs` only manages content between `<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->` markers — it injects inputs, outputs, and resources there but **never touches content outside those markers**. If the README prose above the markers describes the framework/template repo rather than the module itself, that stale content will be published to PMR as the module's documentation. Consumers then see framework docs instead of module usage instructions. **The `/tf-module-implement` pipeline does not rewrite the README prose sections** — this must be done manually or added as a pipeline step. Ensure the root README is module-focused (title, features, usage examples, prerequisites, security defaults) before the first publish to PMR, since PMR ingests the full README from the uploaded tarball.

**Finding**: The `terraform init -backend=false` flag is critical. Without it, init would try to configure the cloud backend and fail without credentials.

**Lesson (from e2e)**: `aquasecurity/trivy-action` tags use the `v` prefix (e.g., `v0.35.0` not `0.35.0`). Using `@0.28.0` (without `v`) fails at "Set up job" with `unable to find version`. Even with the correct prefix, versions below `v0.29.0` have a broken transitive dependency on `aquasecurity/setup-trivy@v0.2.1` which also fails at "Set up job". **Use `v0.35.0` or later.** This cost two failed CI runs to diagnose.

**Lesson (from e2e)**: Changes to `.py` and `.md` files do **not** trigger the validate workflow — the path filter only matches `*.tf`, `*.tfvars`, `*.tftest.hcl`. This is correct behavior but means Python script fixes require a manual `workflow_dispatch` run or must be bundled with a `.tf` change to get validated.

### Phase B: Human Review

```
┌─────────────────────────────────────────────────────┐
│  All checks green                                    │
│                                                      │
│  Human reviewer:                                     │
│  1. Reviews code changes                             │
│  2. Verifies semver label matches change scope       │
│     - patch: bug fixes, doc updates                  │
│     - minor: new features, new variables/outputs     │
│     - major: breaking changes (removed variables,    │
│              renamed resources, changed defaults)     │
│  3. Approves PR                                      │
│  4. Merges to main                                   │
└─────────────────────────────────────────────────────┘
```

**Finding**: The semver label is a **human judgment call**. The automation enforces that one exists but cannot determine the correct bump level. Reviewers must verify the label matches the actual change scope. A mislabeled patch for a breaking change will silently publish a wrong version.

**Lesson (from e2e)**: Adding labels via `gh pr edit --add-label` can fail on repos with legacy GitHub Projects (Classic) due to a GraphQL deprecation error. Use the REST API instead: `gh api "repos/OWNER/REPO/issues/PR_NUMBER/labels" -X POST --input - <<< '{"labels":["semver:minor"]}'`.

### Phase C: Release to PMR (`module_release.yml`)

**Trigger**: `pull_request: types: [closed]` on `main` branch, gated by `github.event.pull_request.merged == true`

```
┌─────────────────────────────────────────────────────────────┐
│  PR merged to main                                           │
│                                                              │
│  1. Checkout with full history (fetch-depth: 0)              │
│  2. Read PR labels → determine RELEASE_TYPE                  │
│  3. Setup Python 3.11 + install requirements                 │
│  4. get_module_version.py:                                   │
│     - Query PMR API for current latest version               │
│     - If no versions exist → 0.1.0                           │
│     - Otherwise increment based on RELEASE_TYPE              │
│  5. publish_module_version.py:                               │
│     - POST new version to PMR API → get upload URL           │
│     - Package module source as tarball (excluding .git etc)  │
│     - PUT tarball to pre-signed upload URL                   │
│  6. Create + push git tag (v{VERSION})                       │
│  7. Create GitHub Release with auto-generated notes          │
│  8. Summary with direct PMR link → GitHub Step Summary       │
└─────────────────────────────────────────────────────────────┘
```

**Finding**: The release workflow runs on the `pull_request: closed` event, NOT on push to main. This is important because it gives access to `github.event.pull_request.labels` which is needed to determine the semver bump. A push-triggered workflow would not have label context.

**Finding**: `fetch-depth: 0` is required for the git tag step. Without full history, the tag push may fail or the GitHub Release auto-generated notes will be incomplete.

**Finding**: The Python version calculator queries the **PMR API** (not git tags) for the current version. This means PMR is the source of truth. If someone manually creates a git tag without publishing to PMR, the version calculator won't see it. Conversely, if PMR has a version but the git tag was deleted, the calculator will still increment correctly.

**Lesson (CRITICAL, from e2e)**: For API-driven (non-VCS) modules, creating a version via the API returns an **upload URL**. You must then create a tarball of the module source and `PUT` it to that URL. Without the upload, the module version stays in `pending` status and the module itself stays in `pending` forever. The reference template's `publish_module_version.py` from `hashi-demo-lab/tf-module-template` **only created the version record — it did not upload the tarball**. Our fixed version performs all three steps: create version → package tarball → upload to pre-signed URL. This was the single most important fix discovered during e2e testing.

**Finding**: The tarball should contain only Terraform module files (`.tf`, `modules/`, `examples/`, `tests/`, `README.md`, etc.) and exclude repo scaffolding (`.git`, `.github`, `specs`, `.claude`, `__pycache__`, `.terraform`). The upload URL is a pre-signed archivist URL that accepts `application/octet-stream`.

**Finding**: The `commit-sha` attribute in the PMR API links the published version to the merge commit. This is informational only — PMR does not fetch code from GitHub. The module source is uploaded directly via the tarball.

**Lesson (from e2e)**: The release workflow is re-runnable. On the first attempt it failed due to a bad `TFE_TOKEN`. After updating the secret, we re-ran the same workflow via `gh api "repos/OWNER/REPO/actions/runs/RUN_ID/rerun" -X POST` and it succeeded on the second attempt. GitHub Actions re-runs pick up updated secrets immediately.

---

## Failure Modes & Recovery

### Validation Fails on PR

| Failure | Recovery |
|---------|----------|
| Missing semver label | Add label, re-run workflow |
| `terraform fmt` fails | Run `terraform fmt -recursive` locally, push |
| `terraform validate` fails | Fix HCL errors, push |
| Unit tests fail | Fix tests or module code, push |
| terraform-docs push fails | Check branch protection; the action needs `contents: write` |
| Trivy action version not found | Use `v` prefix and version `>= v0.35.0` |

### Release Fails After Merge

| Failure | Recovery |
|---------|----------|
| No semver label on merged PR | **Cannot auto-recover.** The merged PR is closed. Manually run the version calculator and publish scripts with env vars set, or create a no-op PR with the correct label. |
| PMR API returns 404 on create-version | **Token permissions.** The `TFE_TOKEN` secret lacks `Manage Modules`. Update the secret, then re-run the workflow. |
| PMR API rejects version (422) | Version already exists. If the tarball was uploaded, this is a no-op. If not, delete the version via API and re-run. |
| Tarball upload fails | Check tarball size (should be < 5MB for typical modules). Re-run the workflow — the create-version step will fail with 422, so you may need to delete the pending version first. |
| Git tag already exists | Delete the tag (`git push --delete origin v1.2.3`) and re-run the workflow. Or create the remaining artifacts (release) manually. |
| GitHub Release creation fails | Non-critical. The module is already in PMR. Create the release manually via `gh release create`. |
| Python dependency install fails | Pin to known-good versions in `requirements.txt`. Current pins: `requests==2.31.0`, `packaging==24.0`. |

**Finding**: The most dangerous failure is a **merged PR without a semver label**. The `module_validate.yml` workflow enforces labels on PRs, but if branch protection is misconfigured (e.g., admins can merge without checks), a labelless PR can slip through. The release workflow will then fail at the "Determine Release Type" step.

**Lesson (from e2e)**: If the release workflow fails partway (e.g., PMR publish succeeds but git tag fails), re-running the workflow will attempt to publish the same version again. The PMR API returns `422` for duplicate versions, which causes the re-run to fail at the publish step. In this case, either delete the version via API before re-running, or complete the remaining steps (tag, release) manually.

---

## Integration with `/tf-module-implement`

The full lifecycle from spec to published module:

```
/tf-module-plan          → design.md (human approval gate)
        │
/tf-module-implement     → code + tests + validation report
        │
  git push feature branch
        │
  Open PR to main        → module_validate.yml runs automatically
        │                    (add semver:minor label for new modules)
  Human review + approve
        │
  Merge to main          → module_release.yml runs automatically
        │                    (version calculated, published to PMR)
        │
  Module available in PMR → consumers can reference in terraform blocks
```

### Semver Label Guidelines for `/tf-module-implement` Output

| Change Type | Label | Example |
|-------------|-------|---------|
| New module (first release) | `semver:minor` | Initial `0.1.0` release |
| Add optional variable/output | `semver:minor` | New `enable_logging` variable |
| Add new resource to module | `semver:minor` | Add CloudWatch alarm resource |
| Fix bug in existing logic | `semver:patch` | Fix incorrect IAM policy |
| Update provider version constraint | `semver:patch` | `>= 5.0` → `>= 5.83` |
| Remove or rename variable | `semver:major` | Rename `name` → `module_name` |
| Change variable default (breaking) | `semver:major` | Default `true` → `false` |
| Remove output | `semver:major` | Remove deprecated output |

---

## Considerations for Multi-Module Repos

The current pipeline assumes **one module per repository**. If this repo evolves to host multiple modules:

1. **Repository variables** (`TFE_MODULE`, `TFE_PROVIDER`) would need to become per-workflow inputs or use a path-based matrix strategy
2. **Path filters** in `module_validate.yml` would need scoping (e.g., `modules/bedrock-agentcore/**/*.tf`)
3. **Semver labels** would need module prefixes (e.g., `bedrock-agentcore:semver:minor`)
4. **Version calculation** already supports different module names via env vars, so the Python scripts work as-is
5. Consider monorepo tools like `paths-filter` action to trigger only relevant module pipelines

---

## Lessons Learned (E2E Run 2026-03-27)

Summary of all issues encountered during the first end-to-end validation, ordered by severity:

### Critical

1. **Reference template publish script is incomplete.** The `hashi-demo-lab/tf-module-template` `publish_module_version.py` only creates a version record via the API — it does not upload the module tarball. For non-VCS (API-driven) modules, this leaves the module permanently in `pending` status. **Fix**: Our version adds tarball packaging and upload to the pre-signed archivist URL.

2. **TFE_TOKEN permission mismatch.** The GitHub secret `TFE_TOKEN` had `Traverse` + `Create Workspaces` but not `Manage Modules`. The version calculator (read-only) succeeded, but the publish step (write) returned HTTP 404. **Fix**: Updated the secret with a token that has `Manage Modules` permission.

### High

3. **Trivy action versioning.** `aquasecurity/trivy-action` requires the `v` prefix on tags AND versions `>= v0.29.0` (older versions have a broken `setup-trivy` dependency). Cost two failed CI runs. **Fix**: Pinned to `v0.35.0`.

4. **terraform-docs auto-push causes rebase conflicts.** The validation workflow pushes a docs commit to the PR branch, which means local pushes will be rejected until you pull. **Mitigation**: Always `git pull --rebase` before pushing to a branch with an active validation workflow.

### Medium

5. **`gh variable set` unavailable in older CLI.** The devcontainer's `gh` version doesn't have the `variable` subcommand. **Fix**: Use `gh api repos/OWNER/REPO/actions/variables -X POST` as a fallback.

6. **`gh pr edit --add-label` fails with legacy Projects.** Repos with GitHub Projects (Classic) get a GraphQL deprecation error. **Fix**: Use the REST labels API directly.

7. **Path filters don't cover Python scripts.** Changes to `.py` files in `.github/workflows/` don't trigger the validate workflow. Python fixes need a manual `workflow_dispatch` or must be bundled with `.tf` changes. **Consideration**: Add `'.github/workflows/*.py'` to the paths filter if Python script validation is desired.

### Low

8. **Release workflow is re-runnable (with caveats).** Updated secrets take effect immediately on re-run. However, if the PMR version was already created (but tarball not uploaded), re-running will fail with 422 on the create-version step. Manual cleanup needed in that case.

9. **README published to PMR contained framework docs, not module docs.** `terraform-docs` only manages the `BEGIN_TF_DOCS`/`END_TF_DOCS` block — it does not rewrite the prose above it. The `/tf-module-implement` pipeline also does not update the prose README. Since PMR ingests the full README from the tarball, the first two published versions showed SDD framework content to consumers instead of module usage docs. **Fix**: Rewrote README to be module-focused before subsequent publishes. **Prevention**: Add a README rewrite step to the module implementation checklist or validate that the README title matches the module name before publishing.

10. **`__pycache__`/`.pyc` files not gitignored.** Python bytecode cache files were created locally during syntax validation (`py_compile`) and left in the working tree. They were not committed only because explicit `git add` with named files was used instead of `git add .`. **Fix**: Added `__pycache__/` and `*.pyc` to `.gitignore`.

---

## Verification Checklist (Completed 2026-03-27)

- [x] Semver labels exist in repository (`semver:patch`, `semver:minor`, `semver:major`)
- [x] Repository variables set (`TFE_ORG`, `TFE_MODULE`, `TFE_PROVIDER`)
- [x] `TFE_TOKEN` secret exists with Manage Modules permission
- [x] Module entity created in PMR (`mod-juCA9PNWnEnE3sKo`)
- [x] PR opened with `.tf` file changes triggers `module_validate.yml`
- [x] Validation workflow passes all blocking steps (run `23630829470`)
- [x] `terraform-docs` auto-commits if README needs update (commit `d19533e`)
- [x] PR merged triggers `module_release.yml` (run `23631781611`)
- [x] Version calculated correctly (`0.2.0` — second release after manual `0.1.0`)
- [x] Module version published to PMR with tarball upload
- [x] Git tag `v0.2.0` created and pushed
- [x] GitHub Release `v0.2.0` created with auto-generated release notes
- [x] Module visible at: `app.terraform.io/app/hashi-demos-apj/registry/modules/private/hashi-demos-apj/bedrock-agentcore/aws`
- [x] Consumer can reference: `source = "app.terraform.io/hashi-demos-apj/bedrock-agentcore/aws"` with `version = "0.2.0"`
