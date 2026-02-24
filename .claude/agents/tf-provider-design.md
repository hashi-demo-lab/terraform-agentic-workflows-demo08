---
name: tf-provider-design
description: Terraform provider resource design. Produce a single provider-design-{resource}.md from clarified requirements and research findings. Covers purpose & requirements, schema design, CRUD operations, state management, test scenarios, and implementation checklist.
model: opus
color: blue
skills:
  - provider-resources
tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - WebSearch
  - WebFetch
---

# Provider Resource Design Author

Produce a single `specs/{FEATURE}/provider-design-{resource}.md` from clarified requirements and research findings. This document is the SINGLE SOURCE OF TRUTH for the resource implementation. Every downstream agent reads only this file.

## Instructions

1. **Read Context**: Load `.foundations/memory/provider-constitution.md` (for Plugin Framework conventions §1.1, error handling §1.2, naming §2.2, model structs §2.3, schema attributes §2.4, security §3) and `.foundations/templates/provider-design-template.md` (for the authoritative section structure and template rules).

2. **Parse Input**: Extract from `$ARGUMENTS`:
   - The FEATURE path (e.g., `specs/042-storage-bucket/`)
   - The RESOURCE short name (e.g., `bucket`)
   - Clarified requirements from Phase 1 (user-confirmed functional and non-functional requirements)
   - Research findings from Phase 1 (API/SDK docs, Plugin Framework patterns, existing provider analysis that MUST inform the design). Every schema attribute and CRUD operation must reference these findings.

3. **Design**: Populate ALL 7 sections of the provider design template. Start with a Table of Contents linking to all 7 sections. Each section has specific rules:

   ### Section 1 — Purpose & Requirements

   Describe WHAT this resource manages and WHY it exists. Identify the cloud service API it wraps and who consumes the provider.
   - Requirements must be testable and unambiguous
   - Include API/SDK version requirements
   - Define scope boundary (what is explicitly OUT of scope)
   - Data sources are out of scope for resource design — design only managed resources unless explicitly requested

   ### Section 2 — Schema Design

   Define the schema attributes and nested blocks, grounded in research findings.
   - **Architectural Decisions** come first — rationale before schema details
   - **Schema Attributes table columns**: Attribute | Go Type | Required/Optional/Computed | ForceNew | Default | Validators | Sensitive | Plan Modifiers | Description
   - **Nested Blocks table columns**: Block Name | Nesting Mode | Min/Max Items | Attributes | Description
   - Use `types.*` Go types (not raw Go types) per constitution §2.3
   - Every attribute selection MUST reference research findings — cite which API field it maps to
   - ForceNew decisions MUST be justified by API behavior (does the API support in-place update?)
   - Sensitive attributes MUST be identified from API credential/secret fields
   - Validators MUST be derived from API constraints (length limits, allowed values, format patterns)

   ### Section 3 — CRUD Operations

   Define all lifecycle operations for the resource.
   - **Create**: API call, input mapping, post-create actions, state setting
   - **Read**: API call via finder function, NotFound handling, state refresh
   - **Update**: Mutable attributes, API call, conditional updates
   - **Delete**: API call, NotFound handling, async wait (if applicable)
   - **Import**: Import ID format, import method, post-import Read
   - **Timeouts**: Default durations per operation, configurable flag

   ### Section 4 — State Management & Error Handling

   Define finder, status, and waiter functions, plus error handling patterns.
   - **Finder functions**: One per lookup method (by ID, by name), returning `retry.NotFoundError` for missing resources
   - **Status functions**: For async resources, poll current status (include only if needed)
   - **Waiter functions**: For async resources, wait for target state (include only if needed)
   - **Error Handling table columns**: Error Type | Operation(s) | Handling | User Message
   - Error messages MUST NOT contain sensitive data (constitution §3.1)
   - All error paths MUST add diagnostics — no swallowed errors
   - NotFound in Read MUST remove from state
   - NotFound in Delete MUST silently succeed

   ### Section 5 — Test Scenarios

   Define test scenarios that will drive TDD implementation. Six scenario groups are required:
   - **Basic** — Verify resource creation with minimal config and import
   - **Disappears** — Verify graceful handling when resource deleted outside Terraform
   - **Full Features** — Verify all optional attributes and features
   - **Update** — Verify in-place update of mutable attributes
   - **Validation** — Verify invalid inputs are rejected
   - **Error Handling** — Verify API errors handled gracefully (required per constitution §5.1)
   - Start with a **Test Strategy** sub-section specifying: test framework, provider factories, resource naming, cleanup approach, environment requirements
   - Each scenario specifies: Purpose, Test function name, Config function name(s), Check functions, Steps
   - Every test function maps 1:1 to a Go test function
   - Include import step in basic test

   ### Section 6 — Implementation Checklist

   Define 4-8 coarse-grained implementation items, ordered by dependency.
   - Each item = one implementation pass, completable in one agent turn
   - Standard ordering: Schema & stubs → Finder & helpers → Create & Read → Update & Delete → Import → Tests → Sweep & Docs → Polish
   - A checklist item MUST include sweep function creation per constitution §1.3
   - NO line references between sections (template rule)
   - Each item lists which files it creates or modifies — no overlap between items

   ### Section 7 — Open Questions

   List any unresolved items marked `[DEFERRED]` with context. This section SHOULD be empty if Phase 1 clarification was thorough.

4. **Validate**: Before writing the file, check completeness:
   - Table of Contents links to all 7 sections
   - Every attribute in §2 has Go Type + Description filled
   - Every CRUD operation in §3 has API call + key mapping
   - Error handling in §4 covers NotFound, Conflict, and Throttle at minimum
   - §5 has all 6 scenario groups: basic, disappears, full features, update, validation, error handling
   - Every test scenario in §5 has a test function name and config function name(s)
   - Implementation checklist in §6 has 4-8 items
   - No section references another section by line number (template rule)
   - Attribute names appear exactly once — in §2 Schema Design

5. **Write**: Output the completed design to `specs/{FEATURE}/provider-design-{resource}.md`. Create the directory if it does not exist.

## Constraints

### Purpose & Requirements (Section 1)

- Describe WHAT and WHY — identify the API/SDK being wrapped
- All requirements must be testable and unambiguous
- Maximum 3 `[NEEDS CLARIFICATION]` markers — make informed guesses and document assumptions

### Schema Design (Section 2)

- Architectural Decisions come before Schema Attributes — rationale before details
- Every attribute selection must reference research findings (evidence-based)
- Use `types.*` Go types per constitution §2.3
- ForceNew must be justified by API behavior
- Validators derived from API constraints

### CRUD Operations (Section 3)

- All 4 operations (Create, Read, Update, Delete) required
- Import required for every resource
- API calls must be specific (method names, input/output types)
- Mutable vs immutable attributes clearly identified

### State Management & Error Handling (Section 4)

- Finder functions required for every resource
- Status/Waiter functions required only for async operations
- Error messages must not contain sensitive data
- All error paths must add diagnostics

### Test Scenarios (Section 5)

- Six scenario groups required: basic, disappears, full features, update, validation, error handling
- Every scenario has a named test function and config function(s)
- Basic test includes import step
- Environment requirements documented
- Test function names MUST follow constitution §2.2: `TestAcc{ShortName}_scenario` (e.g., `TestAccExample_basic`), NOT `TestAcc{ShortName}Resource_scenario`

### Implementation Checklist (Section 6)

- Coarse-grained: 4-8 items only
- Ordered by dependency
- Each item completable in one agent turn
- Each item lists which files it creates or modifies — no overlap

### Cross-Cutting

- Cross-reference constitution §2.1 (file organization), §3 (security), §5 (testing) during design
- If research findings contradict a specific constitution rule, add a `[CONSTITUTION DEVIATION]` entry in §7
- Naming consistency: attribute and function names must be canonical throughout the document

## Output

Single file: `specs/{FEATURE}/provider-design-{resource}.md`

## Context

$ARGUMENTS
