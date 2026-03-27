# Last Mile: Module Publishing Pipeline — Order of Operations

## Context

After `/tf-module-implement` completes (code written, tests pass, validation score meets threshold), the module lives on a feature branch with no way to reach consumers. This document covers the **last mile** — the one-time setup and repeatable publish flow that gets a validated module into HCP Terraform's Private Module Registry (PMR).

This pipeline is designed to execute automatically via GitHub Actions once a PR is approved and merged by a human reviewer.

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
gh variable set TFE_ORG --body "hashi-demos-apj"
gh variable set TFE_MODULE --body "bedrock-agentcore"
gh variable set TFE_PROVIDER --body "aws"
```

**Finding**: `TFE_TOKEN` must already exist as a **repository secret** (not a variable). This token needs `Manage Modules` permission on the HCP Terraform organization.

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

### Step 4: Verify `TFE_TOKEN` Permissions

The token used in the release workflow needs:
- **Manage Modules** — to create versions via API
- The token must be a **Team** or **Organization** token, not a User token, for CI reliability

```bash
# Quick verification — list modules visible to the token
curl -s \
  -H "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/organizations/hashi-demos-apj/registry-modules" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Modules visible: {len(d.get(\"data\",[]))}')"
```

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

**Finding**: `terraform-docs` with `git-push: true` will push a commit to the PR branch if `README.md` needs updating. This means the validation workflow may trigger **twice** on a fresh PR — once for the original push, and once for the docs commit. The second run is expected and lightweight.

**Finding**: The `terraform init -backend=false` flag is critical. Without it, init would try to configure the cloud backend and fail without credentials.

**Finding**: `aquasecurity/trivy-action` tags use the `v` prefix (e.g., `v0.35.0` not `0.35.0`). Older versions (< v0.29.0) have a broken transitive dependency on `aquasecurity/setup-trivy` that fails at "Set up job". Use `v0.35.0` or later.

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
│     - POST new version to PMR API with commit SHA            │
│  6. Create + push git tag (v{VERSION})                       │
│  7. Create GitHub Release with auto-generated notes          │
│  8. Summary with direct PMR link → GitHub Step Summary       │
└─────────────────────────────────────────────────────────────┘
```

**Finding**: The release workflow runs on the `pull_request: closed` event, NOT on push to main. This is important because it gives access to `github.event.pull_request.labels` which is needed to determine the semver bump. A push-triggered workflow would not have label context.

**Finding**: `fetch-depth: 0` is required for the git tag step. Without full history, the tag push may fail or the GitHub Release auto-generated notes will be incomplete.

**Finding**: The Python version calculator queries the **PMR API** (not git tags) for the current version. This means PMR is the source of truth. If someone manually creates a git tag without publishing to PMR, the version calculator won't see it. Conversely, if PMR has a version but the git tag was deleted, the calculator will still increment correctly.

**Finding**: The `commit-sha` attribute in the PMR API links the published version to the merge commit. This is informational only — PMR does not fetch code from GitHub. The module source code is resolved by consumers via `source = "app.terraform.io/hashi-demos-apj/bedrock-agentcore/aws"` which reads from the registry, not the git SHA.

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

### Release Fails After Merge

| Failure | Recovery |
|---------|----------|
| No semver label on merged PR | **Cannot auto-recover.** The merged PR is closed. Manually run the version calculator and publish scripts with env vars set, or create a no-op PR with the correct label. |
| PMR API rejects version | Check TFE_TOKEN permissions. If version already exists (409), it's a no-op. |
| Git tag already exists | Delete the tag (`git push --delete origin v1.2.3`) and re-run the workflow. Or bump version manually. |
| GitHub Release creation fails | Non-critical. The module is already in PMR. Create the release manually via `gh release create`. |
| Python dependency install fails | Pin to known-good versions in `requirements.txt`. Current pins: `requests==2.31.0`, `packaging==24.0`. |

**Finding**: The most dangerous failure is a **merged PR without a semver label**. The `module_validate.yml` workflow enforces labels on PRs, but if branch protection is misconfigured (e.g., admins can merge without checks), a labelless PR can slip through. The release workflow will then fail at the "Determine Release Type" step.

**Finding**: If the release workflow fails partway (e.g., PMR publish succeeds but git tag fails), re-running the workflow will attempt to publish the same version again. The PMR API returns `422` for duplicate versions. The workflow should be re-run after fixing the specific failing step, or the remaining steps (tag, release) should be done manually.

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

## Verification Checklist

After one-time setup, verify the pipeline end-to-end:

- [ ] Semver labels exist in repository (`semver:patch`, `semver:minor`, `semver:major`)
- [ ] Repository variables set (`TFE_ORG`, `TFE_MODULE`, `TFE_PROVIDER`)
- [ ] `TFE_TOKEN` secret exists with Manage Modules permission
- [ ] Module entity created in PMR (API call from Step 3)
- [ ] PR opened with `.tf` file changes triggers `module_validate.yml`
- [ ] Validation workflow passes all blocking steps
- [ ] `terraform-docs` auto-commits if README needs update
- [ ] PR merged triggers `module_release.yml`
- [ ] Version calculated correctly (first release → `0.1.0`)
- [ ] Module version published to PMR
- [ ] Git tag `v0.1.0` created and pushed
- [ ] GitHub Release `v0.1.0` created with release notes
- [ ] Module visible at: `app.terraform.io/app/hashi-demos-apj/registry/modules/private/hashi-demos-apj/bedrock-agentcore/aws`
- [ ] Consumer can reference: `source = "app.terraform.io/hashi-demos-apj/bedrock-agentcore/aws"` with `version = "0.1.0"`
