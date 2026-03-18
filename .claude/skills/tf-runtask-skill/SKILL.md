---
name: tf-runtask-skill
description: Retrieve and display Terraform Cloud/Enterprise run task results for a given run. Use this skill whenever the user asks about run task results, run task checks, task stage statuses, or wants to inspect what run tasks reported for a Terraform Cloud/Enterprise run. Triggers on phrases like "check the run tasks", "what did the run tasks say", "show run task results", "get task results for run-xxx", or any reference to run task outcomes on a specific run.
---

# Terraform Cloud/Enterprise Run Task Reader

Retrieve structured run task results from a Terraform Cloud or Enterprise run. The MCP terraform tools can fetch run details but lack endpoints for task stages and task results — this skill bridges that gap with a script that calls the TFC/TFE REST API directly.

## Workflow

### Step 1: Identify the run

The user may provide either:
- A **run ID** like `run-iURWDL3wVxzefsjo`
- A **URL** like `https://app.terraform.io/app/org/workspaces/ws-name/runs/run-abc123`

Pass either form directly to the script — it handles both.

### Step 2: Fetch run task data

Run the script to get all task stages and results as structured JSON:

```bash
scripts/get-run-task-results.sh <run-id-or-url>
```

The script requires:
- `$TFE_TOKEN` — API token with read access to the workspace
- `$TFE_ADDRESS` — (optional) defaults to `https://app.terraform.io`; auto-detected from URL input
- `curl` and `jq` on PATH

The script handles all API calls (fetching task stages, then each task result) and returns a single JSON object.

### Step 3: Present structured results

Parse the script's JSON output and present a markdown summary grouped by stage:

```
## Run Task Results for `run-abc123`

**Run status**: applied
**Total tasks**: 3 | Passed: 3 | Failed: 0

### Post-Plan Tasks (stage status: passed)

| Task Name | Status | Enforcement | Message | Details |
|-----------|--------|-------------|---------|---------|
| security-scan | passed | mandatory | No issues found | [View](https://...) |
| cost-check | passed | advisory | Estimated cost: $12.50/mo | [View](https://...) |

### Pre-Apply Tasks (stage status: passed)

| Task Name | Status | Enforcement | Message | Details |
|-----------|--------|-------------|---------|---------|
| approval-gate | passed | mandatory | Approved by team lead | [View](https://...) |
```

**Field mapping from JSON output:**

Each `task_stages[].task_results[]` object contains:
- `task_name` — Name of the run task
- `status` — `pending`, `running`, `passed`, `failed`, `errored`, `unreachable`
- `enforcement_level` — `advisory` or `mandatory`
- `message` — Status message from the external service (may be multi-line; show first line if long)
- `url` — Link to external service results page (use as "View" link if present)
- `stage` — `pre_plan`, `post_plan`, `pre_apply`, `post_apply`

The `summary` object provides aggregate counts: `total_tasks`, `passed`, `failed`, `errored`, `pending`, `unreachable`.

**Stage ordering** (show in execution order): `pre_plan` → `post_plan` → `pre_apply` → `post_apply`. Only show stages present in the output. The script already sorts stages in this order.

### Optionally: Get run context via MCP

If the user needs broader run context (trigger message, overall status, plan/apply details), also call `mcp__terraform__get_run_details` with the run ID to supplement the task results with run metadata.

## Script output schema

```json
{
  "run_id": "run-abc123",
  "tfe_base": "https://app.terraform.io",
  "task_stages": [
    {
      "id": "ts-...",
      "stage": "post_plan",
      "status": "passed",
      "status_timestamps": { "passed-at": "...", "running-at": "..." },
      "created_at": "...",
      "updated_at": "...",
      "task_results": [
        {
          "id": "taskrs-...",
          "task_name": "example-task",
          "status": "passed",
          "message": "No issues found.",
          "url": "https://external.service/results",
          "enforcement_level": "mandatory",
          "stage": "post_plan",
          "is_speculative": false,
          "task_id": "task-...",
          "workspace_task_id": "wstask-...",
          "status_timestamps": { ... },
          "created_at": "...",
          "updated_at": "..."
        }
      ]
    }
  ],
  "summary": {
    "total_tasks": 1,
    "passed": 1,
    "failed": 0,
    "errored": 0,
    "pending": 0,
    "unreachable": 0
  }
}
```

## Error handling

- If `$TFE_TOKEN` is not set, the script exits with an error message
- HTTP 401/403 — token lacks permissions for the workspace
- HTTP 404 — invalid run ID or task result ID
- If a task result has `status: errored` or `unreachable`, highlight this prominently — the external service failed to respond
