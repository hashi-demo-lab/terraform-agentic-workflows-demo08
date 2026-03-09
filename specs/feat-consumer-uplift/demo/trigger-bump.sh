#!/usr/bin/env bash
# trigger-bump.sh — Create a Dependabot-style PR that triggers the uplift pipeline
#
# Scenarios:
#   patch    — Bump version constraint, add a tag (plan shows changes)
#   minor    — Bump version + add versioning config change (plan shows changes)
#   breaking — Change to non-existent output reference (plan errors)
#   no-op    — Same version, different constraint format (plan shows no changes)
#
# Usage:
#   bash specs/feat-consumer-uplift/demo/trigger-bump.sh [--scenario patch|minor|breaking|no-op]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Color helpers ───────────────────────────────────────────────────────────
C_CYAN="\033[38;2;80;220;235m"
C_GREEN="\033[38;2;80;250;160m"
C_RED="\033[38;2;255;85;85m"
C_YELLOW="\033[38;2;255;200;80m"
C_WHITE="\033[1;37m"
C_DIM="\033[38;5;243m"
C_PINK="\033[38;2;255;92;138m"
C_RESET="\033[0m"

info()    { printf "  ${C_CYAN}▸${C_RESET} %s\n" "$1"; }
success() { printf "  ${C_GREEN}✔${C_RESET} %s\n" "$1"; }
error()   { printf "  ${C_RED}✖${C_RESET} %s\n" "$1"; }
warn()    { printf "  ${C_YELLOW}▲${C_RESET} %s\n" "$1"; }
header()  { printf "\n  ${C_CYAN}▎${C_RESET} ${C_WHITE}%s${C_RESET}\n\n" "$1"; }

# ─── Load config ─────────────────────────────────────────────────────────────
ENV_FILE="${SCRIPT_DIR}/demo.env"
if [[ ! -f "$ENV_FILE" ]]; then
  error "demo.env not found. Run setup.sh first."
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

# ─── Parse args ──────────────────────────────────────────────────────────────
SCENARIO="${DEMO_SCENARIO:-minor}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario) SCENARIO="$2"; shift 2 ;;
    *) error "Unknown arg: $1"; exit 1 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BASE_BRANCH="${BASE_BRANCH:-$(cd "$REPO_ROOT" && git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}' || echo "main")}"
MODULE_NAME="${MODULE_NAME:-s3-bucket}"
MODULE_SOURCE="${MODULE_SOURCE:?MODULE_SOURCE is required}"
MODULE_CURRENT_VERSION="${MODULE_CURRENT_VERSION:?MODULE_CURRENT_VERSION is required}"
MODULE_TARGET_VERSION="${MODULE_TARGET_VERSION:-${MODULE_CURRENT_VERSION}}"

# ─── Validate version bump ─────────────────────────────────────────────────
if [[ "$MODULE_TARGET_VERSION" == "$MODULE_CURRENT_VERSION" ]]; then
  error "MODULE_TARGET_VERSION (${MODULE_TARGET_VERSION}) is the same as MODULE_CURRENT_VERSION (${MODULE_CURRENT_VERSION})"
  echo ""
  info "Run publish-module-version.sh first to create a new version in the PMR:"
  printf "    ${C_DIM}bash specs/feat-consumer-uplift/demo/publish-module-version.sh${C_RESET}\n"
  echo ""
  info "Or set MODULE_TARGET_VERSION in demo.env to the version you want to bump to."
  exit 1
fi

# ─── Ensure on base branch ─────────────────────────────────────────────────
header "Preparing Demo Trigger"

cd "$REPO_ROOT"
info "Working directory: ${REPO_ROOT}"
info "Base branch: ${BASE_BRANCH}"

CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "$BASE_BRANCH" ]]; then
  warn "Not on ${BASE_BRANCH} (currently on ${CURRENT_BRANCH})"
  info "Switching to ${BASE_BRANCH}..."
  git checkout "$BASE_BRANCH"
  git pull origin "$BASE_BRANCH"
fi

# Verify consumer code exists (created by setup.sh)
if [[ ! -f "main.tf" ]]; then
  error "main.tf not found in ${REPO_ROOT}"
  error "Run setup.sh first to template and commit consumer code"
  exit 1
fi

# ─── Branch name ─────────────────────────────────────────────────────────────
TIMESTAMP=$(date +%s | tail -c 5)
BRANCH_NAME="dependabot/terraform/${MODULE_NAME}-${MODULE_TARGET_VERSION}-${TIMESTAMP}"

printf "    ${C_DIM}%-18s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Scenario" "$SCENARIO"
printf "    ${C_DIM}%-18s${C_RESET} ${C_WHITE}%s${C_RESET}\n" "Branch" "$BRANCH_NAME"
printf "    ${C_DIM}%-18s${C_RESET} ${C_WHITE}%s → %s${C_RESET}\n" "Version" "$MODULE_CURRENT_VERSION" "$MODULE_TARGET_VERSION"
echo ""

# ─── Create branch ───────────────────────────────────────────────────────────
header "Creating Branch"

git checkout -b "$BRANCH_NAME"
success "Branch created: ${BRANCH_NAME}"

# ─── Apply scenario changes ─────────────────────────────────────────────────
header "Applying Scenario: ${SCENARIO}"

  # Replace version constraint in main.tf — matches any existing constraint format
  # e.g., "5.8.2", "~> 5.8.2", ">= 5.8.2"
  replace_version() {
    local target="$1"
    local replaced
    replaced=$(sed "s|version[[:space:]]*=[[:space:]]*\"[^\"]*\"|version = \"${target}\"|" main.tf)
    echo "$replaced" > main.tf

    # Verify the replacement actually happened
    if ! grep -q "version = \"${target}\"" main.tf; then
      error "Failed to replace version constraint in main.tf"
      exit 1
    fi
    success "Version constraint updated to: ${target}"
  }

case "$SCENARIO" in
  patch)
    # Simple version constraint change + add a tag
    info "Changing version constraint and adding demo tag"
    replace_version "~> ${MODULE_TARGET_VERSION}"
    if ! grep -q 'DemoRun' main.tf; then
      sed -i 's|Purpose     = "consumer-uplift-demo"|Purpose     = "consumer-uplift-demo"\n    DemoRun     = "patch-bump"|' main.tf
    else
      sed -i "s|DemoRun.*|DemoRun     = \"patch-bump-$(date +%s | tail -c 5)\"|" main.tf
    fi
    success "Applied patch scenario"
    ;;

  minor)
    # Version bump + add logging configuration
    info "Bumping version and adding logging configuration"
    replace_version "~> ${MODULE_TARGET_VERSION}"

    # Add logging config to the module block (before the tags block) if not already present
    if ! grep -q 'logging' main.tf; then
      sed -i '/tags = {/i\
  logging = {\
    target_bucket = "access-logs-bucket"\
    target_prefix = "demo-bucket-logs/"\
  }\
' main.tf
    fi

    # Add a new output
    if ! grep -q 'bucket_domain_name' outputs.tf 2>/dev/null; then
      cat >> outputs.tf <<'NEWOUTPUT'

output "bucket_domain_name" {
  description = "The bucket domain name"
  value       = module.demo_bucket.s3_bucket_bucket_domain_name
}
NEWOUTPUT
    fi
    success "Applied minor scenario (added logging + output)"
    ;;

  breaking)
    # Reference a non-existent output to trigger plan failure
    info "Introducing breaking output reference"
    replace_version "~> ${MODULE_TARGET_VERSION}"

    if ! grep -q 'bucket_acceleration' outputs.tf 2>/dev/null; then
      cat >> outputs.tf <<'BREAKOUTPUT'

output "bucket_acceleration" {
  description = "This output references a removed attribute"
  value       = module.demo_bucket.s3_bucket_acceleration_status
}
BREAKOUTPUT
    fi
    success "Applied breaking scenario (invalid output reference)"
    ;;

  no-op)
    # Change constraint format but resolves to same version
    info "Changing constraint format (same resolved version)"
    replace_version "~> ${MODULE_TARGET_VERSION}"
    success "Applied no-op scenario (constraint format change only)"
    ;;

  *)
    error "Unknown scenario: ${SCENARIO}"
    echo "  Valid scenarios: patch, minor, breaking, no-op"
    exit 1
    ;;
esac

# ─── Commit ──────────────────────────────────────────────────────────────────
header "Committing Changes"

git add -A
git commit -m "build(deps): bump ${MODULE_NAME} from ${MODULE_CURRENT_VERSION} to ${MODULE_TARGET_VERSION}

Bumps ${MODULE_SOURCE} from ${MODULE_CURRENT_VERSION} to ${MODULE_TARGET_VERSION}.

Scenario: ${SCENARIO}
Detected by scan-module-versions.sh (demo trigger)"

success "Changes committed"

# ─── Push and create PR ──────────────────────────────────────────────────────
header "Pushing Branch & Creating PR"

git push -u origin "$BRANCH_NAME"
success "Branch pushed"

PR_TITLE="build(deps): bump ${MODULE_NAME} from ${MODULE_CURRENT_VERSION} to ${MODULE_TARGET_VERSION}"
PR_BODY=$(cat <<PRBODY
Bumps [\`${MODULE_NAME}\`](https://${TFE_HOSTNAME}/app/${TFE_ORG}/registry/modules/private/${TFE_ORG}/${MODULE_NAME}/aws) from \`${MODULE_CURRENT_VERSION}\` to \`${MODULE_TARGET_VERSION}\`.

**Demo scenario**: \`${SCENARIO}\`

---
*This PR was created by \`trigger-bump.sh\` to demonstrate the consumer module uplift pipeline.*
PRBODY
)

PR_URL=$(gh pr create \
  --title "$PR_TITLE" \
  --body "$PR_BODY" \
  --label "dependencies,terraform" \
  --head "$BRANCH_NAME" \
  --base "$BASE_BRANCH" 2>&1)

success "PR created"

# ─── Switch back to base branch ───────────────────────────────────────────
git checkout "$BASE_BRANCH"

# ─── Summary ─────────────────────────────────────────────────────────────────
header "Demo Triggered"

echo ""
printf "  ${C_PINK}▸${C_RESET} ${C_WHITE}PR URL:${C_RESET} ${C_CYAN}%s${C_RESET}\n" "$PR_URL"
echo ""
printf "  ${C_DIM}The consumer uplift pipeline should trigger automatically.${C_RESET}\n"
printf "  ${C_DIM}Watch the Actions tab for the workflow run.${C_RESET}\n"
echo ""

case "$SCENARIO" in
  patch)
    printf "  ${C_DIM}Expected: Classify → Validate (exit 2) → AI Analysis → Decision (auto-merge or needs-review)${C_RESET}\n"
    ;;
  minor)
    printf "  ${C_DIM}Expected: Classify → Validate (exit 2) → AI Analysis → Decision (needs-review)${C_RESET}\n"
    ;;
  breaking)
    printf "  ${C_DIM}Expected: Classify → Validate (exit 1) → Labels: breaking-change, risk:critical${C_RESET}\n"
    ;;
  no-op)
    printf "  ${C_DIM}Expected: Classify → Validate (exit 0) → PR auto-closed with explanation${C_RESET}\n"
    ;;
esac

echo ""
printf "  ${C_DIM}To test @claude interactive: comment '@claude explain the changes' on the PR${C_RESET}\n"
echo ""
