#!/usr/bin/env bash
# Fetch run task stages and results from TFC/TFE API.
#
# Usage:
#   get-run-task-results.sh <run-id-or-url>
#
# Environment:
#   TFE_TOKEN    - Required. API token with read access to the workspace.
#   TFE_ADDRESS  - Optional. Defaults to https://app.terraform.io
#
# Output: JSON object with run task stages and their nested task results.
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
  local response
  local http_code

  response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${TFE_TOKEN}" \
    -H "Content-Type: application/vnd.api+json" \
    "${API_BASE}${endpoint}")

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 400 ]]; then
    echo "Error: API returned HTTP ${http_code} for ${endpoint}" >&2
    echo "$body" >&2
    return 1
  fi

  echo "$body"
}

# --- Step 1: Fetch task stages for the run ---

stages_response=$(api_get "/runs/${RUN_ID}/task-stages")

stage_count=$(echo "$stages_response" | jq '.data | length')

if [[ "$stage_count" -eq 0 ]]; then
  # Return empty result
  jq -n \
    --arg run_id "$RUN_ID" \
    --arg base "$TFE_BASE" \
    '{
      run_id: $run_id,
      tfe_base: $base,
      task_stages: [],
      summary: { total_tasks: 0, passed: 0, failed: 0, errored: 0, pending: 0 }
    }'
  exit 0
fi

# --- Step 2: Extract task result IDs from each stage ---

# Build a list of all task result IDs grouped by stage
task_result_ids=$(echo "$stages_response" | jq -r '
  .data[] |
  .relationships["task-results"].data[]?.id // empty
')

# --- Step 3: Fetch each task result ---

results_json="[]"

for result_id in $task_result_ids; do
  result=$(api_get "/task-results/${result_id}")
  results_json=$(echo "$results_json" | jq --argjson r "$result" '. + [$r]')
done

# --- Step 4: Assemble structured output ---

# Merge stages with their full task results
output=$(jq -n \
  --arg run_id "$RUN_ID" \
  --arg base "$TFE_BASE" \
  --argjson stages "$stages_response" \
  --argjson results "$results_json" \
  '
  # Index results by ID for lookup
  ($results | map(.data) | INDEX(.id)) as $results_by_id |

  # Stage ordering
  ["pre_plan", "post_plan", "pre_apply", "post_apply"] as $stage_order |

  {
    run_id: $run_id,
    tfe_base: $base,
    task_stages: [
      $stages.data[]
      | . as $stage
      | {
          id: .id,
          stage: .attributes.stage,
          status: .attributes.status,
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
                enforcement_level: .attributes["workspace-task-enforcement-level"],
                stage: .attributes.stage,
                is_speculative: .attributes["is-speculative"],
                task_id: .attributes["task-id"],
                workspace_task_id: .attributes["workspace-task-id"],
                status_timestamps: .attributes["status-timestamps"],
                created_at: .attributes["created-at"],
                updated_at: .attributes["updated-at"]
              }
          ]
        }
    ]
    | sort_by(
        .stage as $s | $stage_order | to_entries[] | select(.value == $s) | .key
      ),
    summary: {
      total_tasks: ([
        $stages.data[].relationships["task-results"].data[]?
      ] | length),
      passed: ([$results[].data | select(.attributes.status == "passed")] | length),
      failed: ([$results[].data | select(.attributes.status == "failed")] | length),
      errored: ([$results[].data | select(.attributes.status == "errored")] | length),
      pending: ([$results[].data | select(.attributes.status == "pending")] | length),
      unreachable: ([$results[].data | select(.attributes.status == "unreachable")] | length)
    }
  }
')

echo "$output"
