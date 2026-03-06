# Consumer Module Uplift — Implementation Plan

**Branch**: feat/consumer-module-uplift
**Date**: 2026-03-06
**Issue**: hashi-demo-lab/terraform-agentic-workflows#3 (Use Case 1)
**Status**: Draft

---

## 1. Problem Statement

When a module author publishes a new version to the HCP Terraform private registry, **consumers** of that module must update their workspace code. The change scope ranges from trivial (bump a version constraint) to complex (new required variables, removed outputs, restructured interfaces). Existing tools like Dependabot can detect new versions but provide **zero semantic understanding** of what changed — especially for private registry modules which lack changelogs.

The automation gap: no tool today reads the module interface diff, maps breaking changes to consumer code, rewrites HCL, and validates the result. This is precisely the gap an agentic workflow can fill.

---

## 2. Scope

**In scope (Use Case 1 only)**:
- Consumer-side module version upgrades (workspace code that calls private registry modules)
- Detection via Dependabot + fallback scanner
- AI-powered analysis of module interface changes
- Automated code adaptation where possible
- Risk-based decision framework (auto-merge / needs-review / breaking-change)
- CI pipeline via GitHub Actions with HCP Terraform integration

**Out of scope (Use Case 2 — separate issue)**:
- Producer-side module uplift (upgrading the module itself)
- Provider version upgrades within modules
- Breaking change detection for module authors
- Migration guide generation

---

## 3. Architecture Overview

### Two Execution Modes

The consumer uplift workflow operates in **two complementary modes**:

| Mode | Trigger | Runtime | Agent Model |
|------|---------|---------|-------------|
| **Interactive** (`/tf-consumer-uplift`) | User invokes CLI skill | Claude Code (Opus) | Full SDD 4-phase with human gates |
| **CI Pipeline** (GitHub Actions) | Dependabot PR / cron scan | claude-code-action (Sonnet) | Automated 4-job pipeline with decision matrix |

Both modes share the same analysis logic and decision matrix, but differ in execution context:

- **Interactive mode** follows SDD conventions: research agents, design document, human approval gate, implementation agents
- **CI mode** runs as a GitHub Actions workflow: classify, validate, analyze, decide — optimized for automated PRs

### Alignment with SDD Framework

The interactive workflow maps to the existing SDD 4-phase structure:

```
Phase 1: DETECT & ANALYZE (Clarify)
  ├── Identify module version bump (source: Dependabot PR, manual input, or scan)
  ├── tf-consumer-uplift-analyzer agents (parallel, foreground)
  │   ├── Module interface diff (MCP: get_private_module_details old vs new)
  │   ├── Consumer code impact scan (grep module references, trace outputs)
  │   └── Security review (IAM, encryption, exposure changes)
  └── Collect findings → structured impact report

Phase 2: PLAN ADAPTATION (Design)
  ├── tf-consumer-uplift-planner agent
  │   ├── Reads impact report + current consumer code
  │   ├── Produces consumer-uplift-design.md (new template)
  │   └── Includes: interface diff, required changes, risk assessment
  └── Human approval gate (approve / request changes)

Phase 3: EXECUTE ADAPTATION (Implement)
  ├── tf-consumer-developer agent (reused, with UPLIFT arguments)
  │   ├── Update module version constraint
  │   ├── Add/modify variables for new required inputs
  │   ├── Update references to changed/removed outputs
  │   └── terraform init -upgrade, validate
  └── Checkpoint commit

Phase 4: VALIDATE & DECIDE (Validate)
  ├── tf-consumer-validator agent (reused, with uplift instructions)
  │   ├── terraform plan review (expected vs unexpected changes)
  │   ├── Security review of new resources/permissions
  │   ├── Risk classification (low/medium/high/critical)
  │   └── Quality scoring
  ├── Sandbox deployment (optional, orchestrator-controlled)
  └── PR creation with analysis summary
```

---

## 4. Decision Matrix

Risk classification drives the automated decision for CI mode, and informs the human reviewer in interactive mode.

```
                      PATCH           MINOR           MAJOR
                      -----           -----           -----
No breaking +         AUTO-MERGE      AUTO-MERGE      NEEDS-REVIEW
plan changes <= 5     risk:low        risk:low        risk:medium

No breaking +         NEEDS-REVIEW    NEEDS-REVIEW    NEEDS-REVIEW
plan changes > 5      risk:medium     risk:medium     risk:high

Breaking (adapted)    NEEDS-REVIEW    NEEDS-REVIEW    BREAKING-CHANGE
                      risk:medium     risk:medium     risk:high

Breaking (cannot      BREAKING-       BREAKING-       BREAKING-
  adapt)              CHANGE          CHANGE          CHANGE
                      risk:high       risk:high       risk:critical

Any DESTROY           NEEDS-REVIEW    NEEDS-REVIEW    BREAKING-CHANGE
in plan               risk:high       risk:high       risk:critical

Security finding      NEEDS-REVIEW    NEEDS-REVIEW    BREAKING-CHANGE
>= HIGH severity      risk:high       risk:high       risk:critical
```

**Key principles:**
1. Patch and minor bumps with no breaking changes and small plan diff are safe to auto-merge
2. Any DESTROY action in the plan escalates to at minimum NEEDS-REVIEW
3. Breaking changes that cannot be automatically adapted always block merge
4. Security findings of HIGH or above always escalate regardless of semver type
5. Major version bumps are never auto-merged, even with zero breaking changes

---

## 5. Artifacts to Create

### 5.1 New Skill (Interactive Mode)

| File | Purpose |
|------|---------|
| `.claude/skills/tf-consumer-uplift/SKILL.md` | Orchestrator skill — 4-phase consumer uplift workflow |

The skill follows the same patterns as `/tf-consumer-plan` but adapted for uplift:
- Phase 1 uses uplift-specific research agents (module diff, not module discovery)
- Phase 2 produces `consumer-uplift-design.md` (not `consumer-design.md`)
- Phase 3 reuses `tf-consumer-developer` with uplift-mode arguments
- Phase 4 reuses `tf-consumer-validator` with uplift-specific instructions

### 5.2 New Agents

| File | Purpose | Model |
|------|---------|-------|
| `.claude/agents/tf-consumer-uplift-analyzer.md` | Analyze module version diff, classify changes, assess risk | Opus |

**tf-consumer-uplift-analyzer** — one instance per analysis dimension:
- **Interface diff**: Uses MCP `get_private_module_details` for old and new versions, compares inputs/outputs
- **Consumer impact**: Scans consumer `.tf` files for references to changed/removed outputs
- **Security review**: Assesses IAM, encryption, and exposure changes in the new version

The planner role is handled by `tf-consumer-design` agent (reused) with uplift-specific arguments — no need for a separate planner agent.

### 5.3 New Design Template

| File | Purpose |
|------|---------|
| `.foundations/templates/consumer-uplift-design-template.md` | Design document template for uplift scenarios |

Template sections:
1. **Uplift Summary** — current version, target version, semver type, trigger source
2. **Interface Diff** — added/removed/changed variables and outputs (tables)
3. **Consumer Impact** — which files need changes, what references break
4. **Risk Assessment** — decision matrix result, security findings, plan summary
5. **Adaptation Checklist** — ordered steps to adapt consumer code
6. **Open Questions** — deferred decisions

### 5.4 GitHub Actions Workflows (CI Mode)

| File | Purpose |
|------|---------|
| `.github/workflows/terraform-consumer-uplift.yml` | Main 4-job pipeline: classify, validate, analyze, decide |
| `.github/workflows/terraform-consumer-uplift-apply.yml` | Post-merge apply to HCP Terraform |

Adapted from the external repo's workflows with these changes:
- **Organization-agnostic**: Use env vars for TFC org/workspace, not hardcoded values
- **Configurable model**: Default to Sonnet for CI cost efficiency, but allow override
- **MCP via npx**: Use `npx @anthropic-ai/terraform-mcp-server` (not Docker) for CI
- **Concurrency groups**: Per-branch to prevent race conditions
- **Squash merge only**: Single commit per upgrade for clean reverts

### 5.5 CI Agent Definition

| File | Purpose |
|------|---------|
| `.github/agents/module-upgrade-analyst.md` | Claude Code Action agent prompt for CI analysis |

Adapted from the external repo's agent with SDD alignment:
- 5 sub-analyses: interface diff, config adaptation, security review, plan analysis, recommendation
- Uses Terraform MCP tools for registry queries
- Outputs structured JSON recommendation
- Conservative bias: `needs-review` over `auto-merge` when uncertain

### 5.6 Supporting Scripts

| File | Purpose |
|------|---------|
| `.foundations/scripts/bash/classify-version-bump.sh` | Parse git diff to classify semver bump type |
| `.foundations/scripts/bash/scan-module-versions.sh` | TFC API scanner for module version detection (Dependabot fallback) |

### 5.7 Configuration Files

| File | Purpose |
|------|---------|
| `.github/dependabot.yml` | Private registry module scanning config |
| `.mcp-ci.json` | MCP server config for CI (npx, no Docker) — already partially exists |

### 5.8 Diagram

| File | Purpose |
|------|---------|
| `.foundations/design/consumer-uplift-workflow.html` | Interactive visual diagram of the consumer uplift workflow |

---

## 6. Integration Points

### With Existing SDD Framework

| Component | Integration |
|-----------|-------------|
| **AGENTS.md** | Add `/tf-consumer-uplift` workflow entry to the workflows table |
| **CLAUDE.md** | Add `/tf-consumer-uplift` to workflow entry points table |
| **Consumer constitution** | No changes — uplift follows existing consumer code standards |
| **tf-consumer-developer** | Reused with `UPLIFT MODE` in `$ARGUMENTS` — update version constraints, add/remove variables, fix output references |
| **tf-consumer-validator** | Reused with uplift-specific instructions — regression focus, plan diff analysis |
| **validate-env.sh** | No changes — same prerequisites (TFE_TOKEN, gh CLI) |
| **checkpoint-commit.sh** | Reused for phase checkpoints |
| **post-issue-progress.sh** | Reused for issue progress updates |

### With HCP Terraform

| Integration | Details |
|-------------|---------|
| **Private registry** | MCP `get_private_module_details` for interface diff |
| **Workspace** | Plan + apply in target workspace |
| **Variable sets** | Shared credentials for sandbox deployment |
| **Run API** | `POST /api/v2/runs` for post-merge apply |

### With GitHub

| Integration | Details |
|-------------|---------|
| **Dependabot** | `terraform-registry` ecosystem for private module detection |
| **Actions** | 4-job workflow for automated uplift |
| **PR labels** | Risk classification labels: `risk:low/medium/high/critical` |
| **PR comments** | Structured analysis summaries |

---

## 7. Implementation Order

### Phase A: Foundation (skill + agents + template)

1. Create `consumer-uplift-design-template.md`
2. Create `tf-consumer-uplift-analyzer.md` agent
3. Create `tf-consumer-uplift/SKILL.md` orchestrator skill
4. Update `AGENTS.md` and `CLAUDE.md` with new workflow

### Phase B: CI Pipeline (GitHub Actions)

5. Create `classify-version-bump.sh` script
6. Create `scan-module-versions.sh` script
7. Create `module-upgrade-analyst.md` CI agent
8. Create `terraform-consumer-uplift.yml` workflow
9. Create `terraform-consumer-uplift-apply.yml` workflow
10. Create/update `dependabot.yml` and `.mcp-ci.json`

### Phase C: Documentation & Diagram

11. Create `consumer-uplift-workflow.html` visual diagram
12. Update playground with reference to new workflow (optional)

---

## 8. Key Design Decisions

### D1: Reuse existing agents vs. create new ones

**Decision**: Create ONE new agent (`tf-consumer-uplift-analyzer`), reuse `tf-consumer-developer` and `tf-consumer-validator` with mode-specific arguments.

*Rationale*: The uplift analysis (interface diff, risk assessment) is genuinely new capability. But code adaptation and validation are the same operations as regular consumer development — just with different inputs. Adding mode arguments keeps the agent count low and avoids duplication.

### D2: Separate skill vs. extending tf-consumer-plan

**Decision**: Create a separate `/tf-consumer-uplift` skill, not extend `/tf-consumer-plan`.

*Rationale*: The uplift workflow has fundamentally different inputs (existing code + version bump) versus consumer-plan (greenfield requirements). Combining them would add complexity to both. Separate skills follow the SDD principle of clear entry points.

### D3: Interactive + CI modes vs. CI only

**Decision**: Support both modes. Interactive for ad-hoc upgrades, CI for automated Dependabot PRs.

*Rationale*: The external repo only has CI mode, but the SDD framework's strength is interactive human-gated workflows. Teams need both: automated pipeline for routine patches, and interactive mode for complex major upgrades that need human judgment.

### D4: Sonnet for CI, Opus for interactive

**Decision**: CI pipeline uses Sonnet (cost/speed), interactive mode uses Opus (capability).

*Rationale*: CI runs on every Dependabot PR — cost matters. Structured analysis tasks (interface diff, plan parsing) don't require Opus capability. Interactive mode benefits from Opus's deeper reasoning for complex adaptation decisions.

### D5: No separate constitution for uplift

**Decision**: Reuse the existing consumer constitution. No `uplift-constitution.md`.

*Rationale*: Uplift produces consumer code — the same rules apply. The consumer constitution already covers version management (Section 4.3: "Major version upgrades require design document update and review"). Adding a separate constitution would create maintenance burden and potential conflicts.

---

## 9. What We're NOT Adopting From the External Repo

| External Repo Pattern | Our Approach | Reason |
|----------------------|--------------|--------|
| Sonnet for all analysis | Opus for interactive, Sonnet for CI | User requirement: Opus for subagents |
| Hardcoded TFC org/workspace | Environment variables | Portability across organizations |
| Docker MCP in CI | npx MCP in CI | External repo already chose npx — we agree (faster cold start) |
| Single monolithic workflow | Separated concerns (skill + agents + workflow) | SDD framework conventions |
| No human gate | Human gate in interactive mode | SDD requires Phase 2 approval |
| Module tracker dashboard issue | Deferred to Phase 4 (cross-repo integration) | Incremental delivery |

---

## 10. Success Criteria

1. `/tf-consumer-uplift` skill successfully analyzes a module version bump and produces a design document
2. GitHub Actions workflow classifies, validates, analyzes, and labels a Dependabot PR
3. Low-risk patches are auto-merged; high-risk changes are blocked with analysis
4. Decision matrix correctly maps semver type + breaking changes + plan diff to risk level
5. Reused agents (`tf-consumer-developer`, `tf-consumer-validator`) work correctly in uplift mode
6. Visual diagram accurately represents the workflow using the established design theme
