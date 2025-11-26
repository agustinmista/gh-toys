#!/usr/bin/env bash

set -euo pipefail

# Defaults
PR_NUMBER="${PR_NUMBER:-}"
IGNORE_WIP="${IGNORE_WIP:-false}"
IGNORE_CHECKS="${IGNORE_CHECKS:-false}"
IGNORE_APPROVALS="${IGNORE_APPROVALS:-false}"

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -p, --pr <pr-number>    Specify PR number (default: detect from current branch)
  -w, --ignore-wip        Ignore WIP status in PR title (DANGEROUS)
  -c, --ignore-checks     Ignore CI checks status (DANGEROUS)
  -c, --ignore-approvals  Ignore PR approvals (DANGEROUS)
  -h, --help              Show this help and exit
EOF
  exit 1
}

# Parse arguments
OPTIONS=$(getopt \
  -o p:wcah \
  --long pr:,ignore-wip,ignore-checks,ignore-approvals,help \
  -- "$@" \
)
eval set -- "$OPTIONS"

while true; do
  case "$1" in
    -p|--pr) PR_NUMBER="$2"; shift 2 ;;
    -w|--ignore-wip) IGNORE_WIP="true"; shift ;;
    -c|--ignore-checks) IGNORE_CHECKS="true"; shift ;;
    -a|--ignore-approvals) IGNORE_APPROVALS="true"; shift ;;
    -h|--help) usage ;;
    --) shift; break ;;
    *) usage ;;
  esac
done

# Check for authentication against GitHub
if ! gh auth status &>/dev/null; then
  echo "❌ You must be authenticated with GitHub CLI"
  echo "   Run: gh auth login"
  exit 1
fi

# Detect PR number from current branch if not provided
if [[ -z "$PR_NUMBER" ]]; then
  echo "ℹ️ No PR number provided, trying to detect from current branch ..."
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  PR_NUMBER=$(gh pr view "$CURRENT_BRANCH" --json number --jq .number 2>/dev/null || true)
  if [[ -z "$PR_NUMBER" ]]; then
    echo "❌ Could not find an open PR number for this branch"
    echo "   Please specify with -p <pr-number>"
    exit 1
  fi
fi

# Fetch PR info
echo "ℹ️ Fetching info from PR #$PR_NUMBER ..."
PR_JSON=$( \
  gh pr view \
    "$PR_NUMBER" \
    --json title,url,state,reviews,statusCheckRollup,isDraft,baseRefName,headRefName \
  )

PR_TITLE=$(jq -r .title <<< "$PR_JSON")
PR_HEAD_REF=$(jq -r .headRefName <<< "$PR_JSON")
PR_BASE_REF=$(jq -r .baseRefName <<< "$PR_JSON")

echo "✅ Found PR:"
echo ""
echo "   $PR_TITLE"
echo ""
echo "   trying to merge: $PR_HEAD_REF"
echo "   into:            $PR_BASE_REF"
echo ""

# Warn if PR is not a draft
PR_IS_DRAFT=$(jq -r .isDraft <<< "$PR_JSON")
if [[ "$PR_IS_DRAFT" != "true" ]]; then
  echo "⚠️ This PR is not a draft"
fi

# The PR must be open
PR_STATE=$(jq -r .state <<< "$PR_JSON")
if [[ "$PR_STATE" != "OPEN" ]]; then
  echo "❌ PR is not open"
  exit 1
fi
echo "✅ PR is open"

# The PR title must not contain "WIP"
if echo "$PR_TITLE" | grep -q -v -i "WIP"; then
  echo "✅ PR title does not contain 'WIP'"
elif [[ "$IGNORE_WIP" == "true" ]]; then
  echo "⚠️ PR title contains 'WIP', but ignoring due to -w/--ignore-wip"
else
  echo "❌ PR title contains 'WIP' (work in progress)"
  exit 1
fi

# The PR must have at least one approval
PR_APPROVALS=$(jq '[.reviews[] | select(.state=="APPROVED")] | length' <<< "$PR_JSON")
if [[ "$PR_APPROVALS" -ge 1 ]]; then
  echo "✅ PR has $PR_APPROVALS approval(s)"
elif [[ "$IGNORE_APPROVALS" == "true" ]]; then
  echo "⚠️ PR has no approvals, but ignoring due to -a/--ignore-approvals"
else
  echo "❌ PR needs at least 1 approval"
  exit 1
fi

# All the required CI checks must have passed
# See https://medium.com/@humu71918/automatically-approving-and-merging-dependabot-pull-requests-with-github-actions-518193ddb1c9
ALL_CHECKS_PASSED="true"
FAILED_NON_REQUIRED_CHECKS=()
PR_CI_CHECKS=$( \
  jq -r \
    '[ .statusCheckRollup[]
     | { name: .name
       , type: .["__typename"]
       , status: .status
       , state: .state
       , conclusion: .conclusion
       , url: .detailsUrl
       }
     ]' <<< "$PR_JSON" \
   )
while IFS= read -r ci_check; do
  status=$(jq -r 'if .type == "CheckRun" then .conclusion else .state end' <<< "$ci_check")
  if [[ "$status" != "SUCCESS" ]] && [[ "$status" != "SKIPPED" ]]; then

    # ============================================================================
    # Hack: if the check runs on IOGs Hydra, and its name does not contain the
    # `required` attribute anywhere, then we can skip it safely when not passed.
    # This is a workaround for sticky checks that later succeed but are not
    # properly cleared in the GitHub UI.
    name=$(jq -r .name <<< "$ci_check")
    url=$(jq -r .url <<< "$ci_check")
    if [[ "$url" == https://ci.iog.io/build/* ]] && [[ ! "$name" == *.required.* ]]; then
      FAILED_NON_REQUIRED_CHECKS+=("$name")
      continue
    fi
    # ============================================================================

    ALL_CHECKS_PASSED="false"
  fi
done <<< "$(jq -c '.[]' <<< "$PR_CI_CHECKS")"

if [[ ${#FAILED_NON_REQUIRED_CHECKS[@]} -gt 0 ]]; then
  echo "⚠️ Ignoring the following non-required checks that have not passed:"
  for name in "${FAILED_NON_REQUIRED_CHECKS[@]}"; do
    echo "   * $name"
  done
fi

if [[ "$ALL_CHECKS_PASSED" == "true" ]]; then
  echo "✅ All required CI checks have passed"
elif [[ "$IGNORE_CHECKS" == "true" ]]; then
  echo "⚠️ Some CI required checks have not passed, but ignoring due to -c/--ignore-checks"
else
  echo "❌ Some CI required checks have not passed"
  echo ""
  gh pr checks
  exit 1
fi

# The PR must be up-to-date with the target branch
NEEDS_REBASE="false"
git fetch origin # Make sure we have the latest refs
if git merge-base --is-ancestor "origin/$PR_BASE_REF" "origin/$PR_HEAD_REF"; then
  echo "✅ PR branch is up-to-date with $PR_BASE_REF"
else
  echo "❌ PR branch is not up-to-date with $PR_BASE_REF"
  NEEDS_REBASE="true"
fi

# Perform actions
if [[ "$NEEDS_REBASE" == "true" ]]; then
  echo ""
  read -rp "❓ Would you like me to rebase $PR_HEAD_REF onto $PR_BASE_REF? [y/N] " REBASE_CONFIRM
  if [[ "$REBASE_CONFIRM" != [yY] ]]; then
    echo "Aborted"
  else
    echo "⚡ Rebasing PR $PR_HEAD_REF branch onto $PR_BASE_REF remotely ..."
    gh pr update-branch "$PR_NUMBER" --rebase
    echo "✅ Rebase requested"
    echo "⚠️ Run 'gh co $PR_NUMBER' to check out the updated branch locally"
    echo "⚠️ Rerun this script after CI checks pass"
  fi
else
  echo ""
  read -rp "❓ Ready to merge PR #$PR_NUMBER into $PR_BASE_REF? [y/N] " MERGE_CONFIRM
  if [[ "$MERGE_CONFIRM" != [yY] ]]; then
    echo "Aborted"
  else
    echo "⚡ Merging $PR_NUMBER into $PR_BASE_REF ..."
    # Make sure both branches are up-to-date locally before merging
    gh pr checkout "$PR_NUMBER"
    git checkout "$PR_BASE_REF"
    git pull origin "$PR_BASE_REF"
    # Perform a fast-forward merge
    git merge --ff-only "$PR_HEAD_REF"
    # Push the updated base branch
    git push origin "$PR_BASE_REF"
    echo "✅ Merge complete"
  fi
fi

exit 0

