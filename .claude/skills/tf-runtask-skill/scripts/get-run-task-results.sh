#!/usr/bin/env bash
# Fetch run task stages, results, and outcomes from TFC/TFE API.
#
# Usage:
#   get-run-task-results.sh <run-id-or-url>
#
# Environment:
#   TFE_TOKEN    - Required. API token with read access to the workspace.
#   TFE_ADDRESS  - Optional. Defaults to https://app.terraform.io
#
# Output: JSON object with run task stages, results, outcomes, and outcome bodies.
#
# Example:
#   get-run-task-results.sh run-iURWDL3wVxzefsjo
#   get-run-task-results.sh https://app.terraform.io/app/org/workspaces/ws/runs/run-abc123

set -euo pipefail

# --- Validate prerequisites ---

if [[ -z "${TFE_TOKEN:-}" ]]; then
  echo "Error: TFE_TOKEN environment variable is not set." >&2
  exit 1
fi

if ! command -v curl &>/dev/null; then
  echo "Error: curl is required but not found." >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not found." >&2
  exit 1
fi

# --- Parse input ---

INPUT="${1:-}"
if [[ -z "$INPUT" ]]; then
  echo "Usage: get-run-task-results.sh <run-id-or-url>" >&2
  exit 1
fi

# Extract run ID from URL or use directly
if [[ "$INPUT" =~ ^https?:// ]]; then
  RUN_ID=$(echo "$INPUT" | grep -oE 'run-[a-zA-Z0-9]+')
  if [[ -z "$RUN_ID" ]]; then
    echo "Error: Could not extract run ID from URL: $INPUT" >&2
    exit 1
  fi
  # Extract base URL (scheme + hostname) from the provided URL
  PARSED_BASE=$(echo "$INPUT" | grep -oE '^https?://[^/]+')
  TFE_BASE="${TFE_ADDRESS:-$PARSED_BASE}"
else
  RUN_ID="$INPUT"
  TFE_BASE="${TFE_ADDRESS:-https://app.terraform.io}"
fi

# Strip trailing slash
TFE_BASE="${TFE_BASE%/}"

API_BASE="${TFE_BASE}/api/v2"

# --- Helper: authenticated GET returning JSON ---

api_get() {
  local endpoint="$1"
  local response http_code body

  response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${TFE_TOKEN}" \
    -H "Content-Type: application/vnd.api+json" \
    "${API_BASE}${endpoint}")

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 400 ]]; then
    echo "Error: API returned HTTP ${http_code} for ${endpoint} (run: ${RUN_ID})" >&2
    echo "$body" >&2
    return 1
  fi

  echo "$body"
}

# Helper: fetch HTML body from outcome (follows redirects)
api_get_body() {
  local endpoint="$1"
  local body

  body=$(curl -s -L \
    -H "Authorization: Bearer ${TFE_TOKEN}" \
    -H "Content-Type: application/vnd.api+json" \
    "${API_BASE}${endpoint}")

  echo "$body"
}

# --- Step 1: Fetch task stages with sideloaded task results ---

stages_response=$(api_get "/runs/${RUN_ID}/task-stages?include=task_results")

stage_count=$(echo "$stages_response" | jq '.data | length')

if [[ "$stage_count" -eq 0 ]]; then
  jq -n \
    --arg run_id "$RUN_ID" \
    --arg base "$TFE_BASE" \
    '{
      run_id: $run_id,
      tfe_base: $base,
      task_stages: [],
      summary: { total_tasks: 0, passed: 0, failed: 0, errored: 0, pending: 0, unreachable: 0 }
    }'
  exit 0
fi

# --- Step 2: Extract task result IDs and fetch outcomes for each ---

task_result_ids=$(echo "$stages_response" | jq -r '
  .included[]? | select(.type == "task-results") | .id // empty
')

outcomes_json="[]"

for result_id in $task_result_ids; do
  # Fetch outcomes list for this task result
  outcomes_response=$(api_get "/task-results/${result_id}/outcomes" 2>/dev/null || echo '{"data":[]}')

  # For each outcome, fetch the HTML body
  outcome_ids=$(echo "$outcomes_response" | jq -r '.data[]?.id // empty')

  for outcome_id in $outcome_ids; do
    body_html=$(api_get_body "/task-result-outcomes/${outcome_id}/body" 2>/dev/null || echo "")

    # Merge HTML body into the outcome object
    outcomes_response=$(echo "$outcomes_response" | jq \
      --arg oid "$outcome_id" \
      --arg html "$body_html" \
      '(.data[] | select(.id == $oid)) += {"body_html": $html}')
  done

  # Add outcomes keyed by task result ID
  outcomes_json=$(echo "$outcomes_json" | jq \
    --arg rid "$result_id" \
    --argjson outcomes "$outcomes_response" \
    '. + [{ task_result_id: $rid, outcomes: $outcomes.data }]')
done

# --- Step 3: Assemble structured output ---

output=$(jq -n \
  --arg run_id "$RUN_ID" \
  --arg base "$TFE_BASE" \
  --argjson stages "$stages_response" \
  --argjson outcomes "$outcomes_json" \
  '
  # Index sideloaded task results by ID
  ([$stages.included[]? | select(.type == "task-results")] | INDEX(.id)) as $results_by_id |

  # Index outcomes by task result ID
  ($outcomes | INDEX(.task_result_id)) as $outcomes_by_result |

  # Stage ordering
  ["pre_plan", "post_plan", "pre_apply", "post_apply"] as $stage_order |

  {
    run_id: $run_id,
    tfe_base: $base,
    task_stages: [
      $stages.data[]
      | {
          id: .id,
          stage: .attributes.stage,
          status: .attributes.status,
          is_overridable: (.attributes.actions["is-overridable"] // false),
          permissions: {
            can_override_policy: (.attributes.permissions["can-override-policy"] // false),
            can_override_tasks: (.attributes.permissions["can-override-tasks"] // false),
            can_override: (.attributes.permissions["can-override"] // false)
          },
          status_timestamps: .attributes["status-timestamps"],
          created_at: .attributes["created-at"],
          updated_at: .attributes["updated-at"],
          task_results: [
            .relationships["task-results"].data[]?
            | .id as $rid
            | $results_by_id[$rid]
            | select(. != null)
            | {
                id: .id,
                task_name: .attributes["task-name"],
                status: .attributes.status,
                message: .attributes.message,
                url: .attributes.url,
                task_url: .attributes["task-url"],
                enforcement_level: .attributes["workspace-task-enforcement-level"],
                stage: .attributes.stage,
                is_speculative: .attributes["is-speculative"],
                task_id: .attributes["task-id"],
                workspace_task_id: .attributes["workspace-task-id"],
                outcomes_count: (.attributes["task-result-outcomes-count"] // 0),
                status_timestamps: .attributes["status-timestamps"],
                created_at: .attributes["created-at"],
                updated_at: .attributes["updated-at"],
                outcomes: (
                  ($outcomes_by_result[$rid].outcomes // [])
                  | map({
                      id: .id,
                      outcome_id: .attributes["outcome-id"],
                      description: .attributes.description,
                      tags: .attributes.tags,
                      url: .attributes.url,
                      body_html: (.body_html // null),
                      created_at: .attributes["created-at"]
                    })
                )
              }
          ]
        }
    ]
    | sort_by(
        .stage as $s | $stage_order | to_entries[] | select(.value == $s) | .key
      ),
    summary: {
      total_tasks: ([$stages.included[]? | select(.type == "task-results")] | length),
      passed: ([$stages.included[]? | select(.type == "task-results") | select(.attributes.status == "passed")] | length),
      failed: ([$stages.included[]? | select(.type == "task-results") | select(.attributes.status == "failed")] | length),
      errored: ([$stages.included[]? | select(.type == "task-results") | select(.attributes.status == "errored")] | length),
      pending: ([$stages.included[]? | select(.type == "task-results") | select(.attributes.status == "pending")] | length),
      unreachable: ([$stages.included[]? | select(.type == "task-results") | select(.attributes.status == "unreachable")] | length)
    }
  }
')

echo "$output"
