---
name: tf-runtask-skill
description: Retrieve and display Terraform Cloud/Enterprise run task results for a given run. Use this skill whenever the user asks about run task results, run task checks, task stage statuses, or wants to inspect what run tasks reported for a Terraform Cloud/Enterprise run. Triggers on phrases like "check the run tasks", "what did the run tasks say", "show run task results", "get task results for run-xxx", or any reference to run task outcomes on a specific run.
---

# Terraform Cloud/Enterprise Run Task Reader

Retrieve structured run task results from a Terraform Cloud or Enterprise run. The MCP terraform tools can fetch run details but lack endpoints for task stages, task results, and task result outcomes — this skill bridges that gap with a script that calls the TFC/TFE REST API directly.

## Workflow

### Step 1: Identify the run

The user may provide either:
- A **run ID** like `run-iURWDL3wVxzefsjo`
- A **URL** like `https://app.terraform.io/app/org/workspaces/ws-name/runs/run-abc123`

Pass either form directly to the script — it handles both.

### Step 2: Fetch run task data

Run the script to get all task stages, results, and outcomes as structured JSON:

```bash
scripts/get-run-task-results.sh <run-id-or-url>
```

The script requires:
- `$TFE_TOKEN` — API token with read access to the workspace
- `$TFE_HOSTNAME` — (optional) TFE/TFC hostname, defaults to `app.terraform.io`; auto-detected from URL input
- `$TFE_SKIP_VERIFY` — (optional) set to `true` to skip TLS certificate verification (for self-signed certs on TFE)
- `curl` and `jq` on PATH

The script uses `include=task_results` for efficient sideloading (single API call for stages + results), then fetches outcomes and their HTML bodies for each task result. It returns a single JSON object.

### Step 3: Present structured results

Parse the script's JSON output and present a markdown summary grouped by stage. The output now includes three layers of detail: **stages → task results → outcomes**.

```
## Run Task Results for `run-abc123`

**Total tasks**: 1 | Passed: 0 | Failed: 1

### Post-Plan Tasks (stage status: passed)

| Task Name | Status | Enforcement | Message |
|-----------|--------|-------------|---------|
| Apptio-Cloudability | failed | advisory | Total Cost before: 31.54, after: 31.64, diff: +0.10 |

#### Apptio-Cloudability — Outcomes

| Outcome | Description | Status | Severity |
|---------|-------------|--------|----------|
| Estimation | Cost Estimation Result | Passed | — |
| Policy | Policy Evaluation Result | Failed | Gated |
| Recommendation | Recommendation Result | Passed | — |

<details>
<summary>Policy Evaluation Detail</summary>

[HTML body content from the outcome — shows failing resources, tag violations, etc.]

</details>
```

**If `task_stages` is empty** (the run has no run tasks configured), inform the user clearly: "This run has no run tasks configured."

### Field mapping from JSON output

**Task stage fields** (`task_stages[]`):
- `stage` — `pre_plan`, `post_plan`, `pre_apply`, `post_apply`
- `status` — stage-level status (can pass even if advisory tasks fail)
- `is_overridable` — whether the stage can be overridden
- `permissions` — `can_override_policy`, `can_override_tasks`, `can_override`

**Task result fields** (`task_stages[].task_results[]`):
- `task_name` — Name of the run task
- `status` — `pending`, `running`, `passed`, `failed`, `errored`, `unreachable`
- `enforcement_level` — `advisory` (warning only) or `mandatory` (blocks run)
- `message` — Status message from the external service
- `url` — Link to external service results page (if present)
- `task_url` — Callback URL of the external service
- `outcomes_count` — Number of outcome categories

**Outcome fields** (`task_stages[].task_results[].outcomes[]`):
- `outcome_id` — Category name (e.g., "Estimation", "Policy", "Recommendation")
- `description` — Human-readable description
- `tags` — Array of `{label, value: [{label, level}]}` for status/severity
- `body_html` — Full HTML detail (failing resources, policy violations, etc.)

The `summary` object provides aggregate counts: `total_tasks`, `passed`, `failed`, `errored`, `pending`, `unreachable`.

**Stage ordering** (show in execution order): `pre_plan` → `post_plan` → `pre_apply` → `post_apply`. Only show stages present in the output. The script already sorts stages in this order.

### Presenting outcomes

Outcomes provide the richest detail — they break each task result into categories (e.g., cost estimation, policy evaluation, recommendations). Present each outcome as a row in a sub-table under the task result.

The `tags` array on each outcome contains status and severity information:
- `tags[].label == "Status"` → `tags[].value[0].label` gives "Passed" or "Failed"
- `tags[].label == "Severity"` → `tags[].value[0].label` gives severity (e.g., "Gated")

If `body_html` is present and non-empty, render it in a collapsible `<details>` block. The HTML typically contains lists of failing resources, tag violations, or recommendations.

### Optionally: Get run context via MCP

If the user needs broader run context (trigger message, overall status, plan/apply details), also call `mcp__terraform__get_run_details` with the run ID to supplement the task results with run metadata.

## Error handling

- If `$TFE_TOKEN` is not set, the script exits with an error message
- HTTP 401/403 — token lacks permissions for the workspace
- HTTP 404 — invalid run ID; the error message includes the run ID for debugging
- If a task result has `status: errored` or `unreachable`, highlight this prominently — the external service failed to respond
- If `task_stages` is empty, no run tasks are configured for this workspace
