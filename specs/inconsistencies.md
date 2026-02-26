# Audit Report: Conflicts & Duplication Across Agents & Skills

Generated: 2026-02-26. Validated by subagent review.

## CRITICAL

| # | Status | Finding | Files |
|---|--------|---------|-------|
| **C1** | CONFIRMED | **AGENTS.md missing agents from workflow table.** `tf-provider-test-writer` missing from provider row; `tf-module-validator` missing from module row. Both agents exist as files and are dispatched by implement skills. | `AGENTS.md` lines 9-10 |
| **C2** | CONFIRMED | **Test file ownership collision (module + provider).** Provider: item A says "test stubs" — collides with test-writer at step 4. Module: item E claims tests — collides with test-writer at step 5. Consumer: no collision (no test-writer). | Provider: `provider-design-template.md` item A vs `tf-provider-implement` step 4. Module: `module-design-template.md` item E vs `tf-module-implement` step 5 |
| **C3** | CONFIRMED | **Module constitution defines 4 test scenario groups; design template + test-writer define 5.** Constitution §5.1: secure defaults, full features, conditional creation disabled, input validation. Template/test-writer: split validation into "Validation Errors" + "Validation Boundaries", replaced "conditional creation" with "Feature Interactions." | `module-constitution.md` §5.1 vs `module-design-template.md` §5 |
| **C4** | CONFIRMED | **AGENTS.md says consumer validator "handles security review" — validator says it does NOT.** Validator line 22, implement skill line 40 both explicitly deny it. Constitution §6.3 gate says "Security review passes" but nothing fulfills it. | `AGENTS.md` line 26, `tf-consumer-validator.md` line 22, `tf-consumer-implement` line 40, `consumer-constitution.md` §6.3 |
| **C5** | CONFIRMED | **Terraform version mismatch in module workflow.** Constitution line 181: `>= 1.14`. Test-writer line 24: fallback `>= 1.7`. | `module-constitution.md` line 181 vs `tf-module-test-writer.md` line 24 |

## IMPORTANT

| # | Status | Finding | Files |
|---|--------|---------|-------|
| **I1** | FALSE | ~~Config function ownership ambiguity (provider).~~ Item F says "complete" (finish implementation), not "create." Test-writer creates skeleton; developer completes with real values. Boundary is clear. | — |
| **I2** | CONFIRMED | **Test patterns duplicated between `provider-resources` and `provider-test-patterns` skills.** 7+ overlapping topics: TestCase/TestStep fields, check functions, config functions, scenario patterns, sweepers. Developer loads both — drift risk and wasted tokens. | `provider-resources` Testing section (lines 374-489) vs `provider-test-patterns` |
| **I3** | CONFIRMED | **`tf-module-design` has `terraform-test` skill but never writes test code.** Skill in frontmatter line 9. Agent designs test scenarios but never writes `.tftest.hcl` files. ~300 lines of HCL patterns injected for no purpose. | `tf-module-design.md` frontmatter |
| **I4** | CONFIRMED | **`tf-module-validator` references `tf-report-template` in instructions but doesn't list it in `skills:` frontmatter.** Frontmatter only has `tf-judge-criteria`. Body line 101 references "the `tf-report-template` skill's module template format." | `tf-module-validator.md` step 5 vs frontmatter |
| **I5** | CONFIRMED | **`tf-provider-research` has no skills assigned.** No `skills:` in frontmatter. `tf-module-research` and `tf-consumer-research` both have `tf-research`. | `tf-provider-research.md` frontmatter |
| **I6** | CONFIRMED | **Consumer developer missing `get_module_details` / `get_private_module_details` MCP tools.** Has `search_modules` + `search_private_modules` but no `get_*_details` counterparts. Cannot inspect module interfaces. | `tf-consumer-developer.md` frontmatter |
| **I7** | CONFIRMED | **Consumer validator has Write/Edit tools but documented as non-destructive.** Tools grant mutation. Constraint line 133: "Do NOT auto-fix code." Policy depends on agent self-discipline, not technical guardrails. | `tf-consumer-validator.md` frontmatter vs line 133 |
| **I8** | FALSE | ~~Module developer examples use `count` vs constitution `for_each` preference.~~ Constitution §2.5 explicitly permits both `count` and `for_each`. Examples use a permitted pattern — style gap, not a conflict. | — |
