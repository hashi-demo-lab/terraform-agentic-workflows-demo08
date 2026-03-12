# AGENTS.md

Operational rules for the orchestrator during workflow execution. Everything else — agent instructions, skill steps, constitution rules — lives in its own file and is loaded automatically.

## Workflows

| Command | Agents | Design Artifact | Constitution |
|---------|--------|----------------|--------------|
| `/tf-module-plan` + `/tf-module-implement` | tf-module-research, tf-module-design, tf-module-test-writer, tf-module-developer | `specs/{FEATURE}/design.md` | `.foundations/memory/module-constitution.md` |
| `/tf-provider-plan` + `/tf-provider-implement` | tf-provider-research, tf-provider-design, tf-provider-developer, tf-provider-validator | `specs/{FEATURE}/provider-design-{resource}.md` | `.foundations/memory/provider-constitution.md` |
| `/tf-consumer-plan` + `/tf-consumer-implement` | tf-consumer-research, tf-consumer-design, tf-consumer-developer, tf-consumer-validator | `specs/{FEATURE}/consumer-design.md` | `.foundations/memory/consumer-constitution.md` |

### Consumer Module Uplift (CI Pipeline)

Automated pipeline for private registry module version upgrades. Runs entirely in GitHub Actions — no CLI skill.

| Component | File | Purpose |
|-----------|------|---------|
| Main pipeline | `.github/workflows/terraform-consumer-uplift.yml` | Classify, validate, AI analysis, decision + @claude interactive |
| Post-merge apply | `.github/workflows/terraform-apply.yml` | Apply to HCP Terraform + rollback on failure |
| CI agent prompt | `.github/agents/module-upgrade-analyst.md` | 5-step analysis: interface diff, config adaptation, security review, plan analysis, recommendation |
| Version classifier | `.foundations/scripts/bash/classify-version-bump.sh` | Parse git diff for semver classification |
| Fallback scanner | `.foundations/scripts/bash/scan-module-versions.sh` | TFC API scanner for modules Dependabot misses |
| CI MCP config | `.mcp-ci.json` | Terraform MCP server config for CI (npx, no Docker) |
| Dependabot | `.github/dependabot.yml` | Private registry module version detection |
| Visual diagram | `.foundations/design/consumer-uplift-workflow.html` | Interactive architecture diagram |

**Decision matrix**: Risk classification (low/medium/high/critical) drives auto-merge, needs-review, or breaking-change decisions. See `specs/feat-consumer-uplift/implementation-plan.md` Section 4.

**Two-pass validation**: If the AI adapts code (step 5B), the pipeline re-runs to validate the adapted code before making a final decision.

**Rollback on apply failure**: Creates an incident issue + draft revert PR. Does NOT auto-revert merges.

## Context Management

These rules apply to ALL three workflows. Replace `{workflow}` with `module`, `provider`, or `consumer` as appropriate.

1. **NEVER call TaskOutput** to read subagent results — EXCEPT for research agents (`tf-{workflow}-research`), whose findings are collected and forwarded to the design agent. All other agents write artifacts to disk.
2. **Verify file existence with Glob** after each agent completes — do NOT read file contents into the orchestrator.
3. **Downstream agents read their own inputs from disk.** The orchestrator passes the FEATURE path plus scope via `$ARGUMENTS`. For the design agent, `$ARGUMENTS` also includes research findings collected from research agents.
4. **Research agents: parallel foreground Task calls** (NOT `run_in_background`). Launch ALL research agents in a single message with multiple Task tool calls, then collect their in-memory findings to pass to the design agent.
5. **Minimal $ARGUMENTS**: Only pass the FEATURE path + a specific question or scope. The one exception is research findings passed to the design agent.

### Consumer-Specific Rules

6. **No test-writer agent**: Consumer workflow does NOT have a test-writer agent. Validation is via `terraform validate` and sandbox deployment, not `.tftest.hcl` files.
7. **Validator handles deploy**: The `tf-consumer-validator` agent handles security review, quality scoring, AND sandbox deployment in a single pass. The orchestrator controls whether sandbox deploy is included via `$ARGUMENTS`.
8. **Sandbox destroy is orchestrator-controlled**: The orchestrator (not the validator) prompts the user about destroying sandbox resources after PR creation.

## Operational Notes

### GitHub Enterprise Authentication

Most `gh` commands (issue, pr, repo, etc.) do NOT accept `--hostname`. Use the `GH_HOST` environment variable instead:

```bash
export GH_HOST=github.enterprise.com
gh issue create --title "Bug report"
# Or inline:
GH_HOST=github.enterprise.com gh pr create --title "Feature"
```

Authentication requires `gh auth login --hostname <hostname>` — standard `gh auth login` only authenticates against github.com.

### Agent Output Persistence

Most agents persist output artifacts to disk. The orchestrator verifies expected files exist after each dispatch. **Exception**: Research agents (`tf-{workflow}-research`) return findings in-memory — the orchestrator collects these and passes them to the design agent via `$ARGUMENTS`.
