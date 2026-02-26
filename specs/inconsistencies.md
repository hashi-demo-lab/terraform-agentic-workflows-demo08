# Audit Report: Conflicts & Duplication Across Agents & Skills

Generated: 2026-02-26

## CRITICAL

| # | Finding | Files |
|---|---------|-------|
| **C1** | **AGENTS.md missing agents from workflow table.** `tf-provider-test-writer` missing from provider row; `tf-module-validator` missing from module row. Orchestrators consulting AGENTS.md won't know these agents exist. | `AGENTS.md` lines 9-10 |
| **C2** | **Test file ownership collision (all 3 workflows).** The implement skill launches a test-writer agent *before* checklist execution, but the design template's checklist item A also says "create test stubs." Both the test-writer agent and the developer agent (on item A) claim ownership of the test file, causing a potential double-write. | Module: `module-design-template.md` item A vs `tf-module-implement` step 5. Provider: `provider-design-template.md` item A vs `tf-provider-implement` step 4 |
| **C3** | **Module constitution defines 4 test scenario groups; design template + test-writer define 5.** Constitution §5.1 lists: secure defaults, full features, conditional creation disabled, input validation. Template/test-writer split validation into "Validation Errors" + "Validation Boundaries" and replace "conditional creation" with "Feature Interactions." The validator scores against the constitution — mismatch. | `module-constitution.md` §5.1 vs `module-design-template.md` §5 |
| **C4** | **AGENTS.md says consumer validator "handles security review" — validator says it does NOT.** The validator agent, the implement skill, and the constitution all agree no security review happens. AGENTS.md rule 7 is the outlier. Constitution §6.3 quality gate also says "Security review passes" referencing a gate no agent fulfills. | `AGENTS.md` line 26, `tf-consumer-validator.md` line 22, `consumer-constitution.md` §6.3 |
| **C5** | **Terraform version mismatch in module workflow.** Constitution says `>= 1.14`, but `tf-module-test-writer` hardcodes fallback `>= 1.7`. If the design doc omits a version, the test-writer generates the wrong constraint. | `module-constitution.md` line 181 vs `tf-module-test-writer.md` line 24 |

## IMPORTANT

| # | Finding | Files |
|---|---------|-------|
| **I1** | **Config function ownership ambiguity (provider).** Test-writer creates config functions with real HCL. Developer checklist item F says "complete all test configs." If test-writer produces full configs, item F is redundant. If stubs, the boundary is unclear. | `tf-provider-test-writer.md` step 4c vs `provider-design-template.md` item F |
| **I2** | **Test patterns duplicated between `provider-resources` and `provider-test-patterns` skills.** Developer agent loads both — ~100 lines of overlapping test content (TestCase fields, scenario patterns, config helpers). Creates drift risk and wastes tokens. | `provider-resources` Testing section vs `provider-test-patterns` |
| **I3** | **`tf-module-design` has `terraform-test` skill but never writes test code.** Injects ~300 lines of `.tftest.hcl` syntax patterns into the design agent's context for no purpose. The design agent only needs test *scenario structure* (already in its instructions), not HCL patterns. | `tf-module-design.md` frontmatter |
| **I4** | **`tf-module-validator` references `tf-report-template` in its instructions but doesn't list it in `skills:` frontmatter.** Template rules won't be auto-loaded into context. Agent must manually read the file. | `tf-module-validator.md` step 5 vs frontmatter |
| **I5** | **`tf-provider-research` has no skills assigned.** Unlike `tf-module-research` and `tf-consumer-research` (both have `tf-research`), the provider research agent has zero skills. Inconsistent across workflows. | `tf-provider-research.md` frontmatter |
| **I6** | **Consumer developer agent missing `get_module_details` / `get_private_module_details` MCP tools.** Can search for private registry modules but cannot inspect their interfaces (inputs/outputs/types). Essential for correct wiring. | `tf-consumer-developer.md` frontmatter |
| **I7** | **Consumer validator has Write/Edit tools but is documented as non-destructive.** Constraints say "Do NOT auto-fix code" but tools grant mutation capability. LLM agents tend to use available tools. | `tf-consumer-validator.md` frontmatter vs line 133 |
| **I8** | **Module developer agent examples all use `count`, contradicting constitution's `for_each` preference.** Constitution §2.2 says "Prefer `for_each` over `count` for stable resource addresses." Developer agent only shows `count = var.create ? 1 : 0` patterns. Systemic bias. | `tf-module-developer.md` lines 49-84 vs `module-constitution.md` §2.2 |
