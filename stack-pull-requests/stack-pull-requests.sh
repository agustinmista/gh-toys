#!/usr/bin/env bash

set -euo pipefail

# Defaults
BASE_BRANCH="${BASE_BRANCH:-main}"
BRANCH_NAME="${BRANCH_NAME:-}"
DRY_RUN="${DRY_RUN:-false}"

usage() {
  cat <<EOF
Usage: $0 [options] pr-number [pr-number ...]

Options:
  -b, --base        Base branch to stack PRs on top of (default: main)
  -n, --name        Name of the new branch to create (default: stacked/pr1-pr2-...)
  -d, --dry-run     Don't perform the cherry-pick, just print the command
  -h, --help        Show this help and exit
EOF
  exit 1
}

# Parse arguments
OPTIONS=$(getopt \
  -o b:n:dh \
  --long base:,name:,dry-run,help \
  -- "$@" \
)
eval set -- "$OPTIONS"

while true; do
  case "$1" in
    -b|--base) BASE_BRANCH="$2"; shift 2 ;;
    -n|--name) BRANCH_NAME="$2"; shift 2 ;;
    -d|--dry-run) DRY_RUN="true"; shift ;;
    -h|--help) usage ;;
    --) shift; break ;;
  esac
done

# Remaining arguments are PR numbers
if [[ $# -lt 1 ]]; then
  echo "❌ No PR number(s) provided"
  usage
else
  PR_NUMBERS=("$@")
fi

# Save the current reference to return to later
HERE=$(git rev-parse --abbrev-ref HEAD)

# Setup trap to restore the original ref on error
trap 'git checkout "$HERE" &>/dev/null' ERR

# Check for authentication against GitHub
if ! gh auth status &>/dev/null; then
  echo "❌ You must be authenticated with GitHub CLI"
  echo "   Run: gh auth login"
  exit 1
fi

# Iterate over each PR number and stack their commits on top of each other
COMMITS_TO_CHERRY_PICK=()
PR_NUMBERS_LEFT=("${PR_NUMBERS[@]}")
while [[ ${#PR_NUMBERS_LEFT[@]} -gt 0 ]]; do
  PR_NUMBER="${PR_NUMBERS_LEFT[0]}"
  PR_NUMBERS_LEFT=("${PR_NUMBERS_LEFT[@]:1}")

  # Fetch PR details
  PR_JSON=$( \
    gh pr view "$PR_NUMBER" \
      --json title,commits \
  )

  # Extract PR title
  PR_TITLE=$( \
    jq -r .title <<< "$PR_JSON" \
  )

  # Extract commits
  PR_COMMITS_JSON=$( \
    jq '.commits[] | {sha: .oid, message: .messageHeadline}' <<< "$PR_JSON"
  )

  echo ""
  echo "🥞 Stacking #$PR_NUMBER: $PR_TITLE"

  while IFS= read -r commit; do
    COMMIT_SHA=$(jq -r '.sha' <<< "$commit")
    COMMIT_MESSAGE=$(jq -r .message <<< "$commit")

    # Check if the commit is already in the base branch and if so, skip it
    if git merge-base --is-ancestor "$COMMIT_SHA" "$BASE_BRANCH"; then
      echo "🍋 Skipping ${COMMIT_SHA:0:7}: $COMMIT_MESSAGE [already in ${BASE_BRANCH}]"
      continue
    fi

    # Add commit to the list to cherry-pick
    echo "🍒 Selecting ${COMMIT_SHA:0:7}: $COMMIT_MESSAGE"
    COMMITS_TO_CHERRY_PICK=("${COMMITS_TO_CHERRY_PICK[@]}" "$COMMIT_SHA")

  done <<< "$(jq -c '.' <<< "$PR_COMMITS_JSON")"
done

# Build a new branch name based on the PR numbers
if [[ -n "$BRANCH_NAME" ]]; then
  echo ""
  echo "🌿 Using provided branch name: $BRANCH_NAME"
else
  echo ""
  echo "🌿 Generating branch name based on PR numbers..."
  BRANCH_NAME="stacked"
  SEP="/"
  for PR_NUMBER in "${PR_NUMBERS[@]}"; do
    BRANCH_NAME+="$SEP$PR_NUMBER"
    SEP="-"
  done
fi

# Perform the cherry-pick or print the command if dry-run
echo ""
if [[ "$DRY_RUN" == "true" ]]; then
  echo "⚙️ Dry run enabled. I would have executed the following commands:"
  cat <<EOF
((git switch $BRANCH_NAME || git switch -c $BRANCH_NAME) && \
git reset --hard $BASE_BRANCH && \
git cherry-pick ${COMMITS_TO_CHERRY_PICK[*]})
EOF
else
  echo "🌿 Switching to branch '$BRANCH_NAME' pointing to '$BASE_BRANCH'"
  git switch "$BRANCH_NAME" || git switch -c "$BRANCH_NAME"
  git reset --hard "$BASE_BRANCH"
  echo "🍒 Starting cherry-pick of ${#COMMITS_TO_CHERRY_PICK[@]} commit(s)..."
  git cherry-pick "${COMMITS_TO_CHERRY_PICK[@]}"
fi
