# User Notes

## Uncertainty
- The run has a task stage (post_plan) with status "passed" but zero task results inside it. This is an edge case -- it is unclear whether this means a run task was configured but the external service never called back, or if the task results were cleaned up.

## Needs Human Review
- None

## Workarounds
- None

## Suggestions
- The skill's instructions say "If task_stages is empty, no run tasks are configured." However, this case is different: task_stages is NOT empty (there is one stage), but the task_results within it are empty. The skill could add guidance for this edge case.
