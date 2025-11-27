#!/usr/bin/env bash

set -euo pipefail

# Defaults
PR_NUMBER="${PR_NUMBER:-}"
KEEP_GOING="${CONTINUE:-false}"
NO_DIFF="${NO_DIFF:-false}"
VERBOSE="${VERBOSE:-false}"
COMMAND="${COMMAND:-}"

usage() {
  cat <<EOF
Usage: $0 [options] command

Options:
  -p, --pr <pr-number>    Specify PR number (default: detect from current branch)
  -k, --keep-going        Continue on errors (default: stop on first error)
  -d, --no-diff           Check that the command does not produce any diff
  -v, --verbose           Print command output while running
  -h, --help              Show this help and exit

NOTE: you can multiple commands by escaping ; and && with a backlash.

For instance:
$ forall-commits -- make build \&\& make test \; make format

EOF
  exit 1
}

# Parse arguments
OPTIONS=$(getopt \
  -o p:kdvh \
  --long pr:,keep-going,no-diff,verbose,help \
  -- "$@" \
)
eval set -- "$OPTIONS"

while true; do
  case "$1" in
    -p|--pr) PR_NUMBER="$2"; shift 2 ;;
    -k|--keep-going) KEEP_GOING="true"; shift ;;
    -d|--no-diff) NO_DIFF="true"; shift ;;
    -v|--verbose) VERBOSE="true"; shift ;;
    -h|--help) usage ;;
    --) shift; break ;;
  esac
done

# Remaining argument is the command
if [[ $# -lt 1 ]]; then
  echo "❌ No command provided"
  usage
else
  COMMAND="$*"
fi

# Save the current reference to return to later
HERE=$(git rev-parse --abbrev-ref HEAD)

# Setup trap to restore the original ref on exit
trap 'git checkout "$HERE" &>/dev/null' EXIT

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
  else
    echo "ℹ️ Detected PR number: #$PR_NUMBER"
  fi
fi

# Fetch PR commits
PR_COMMITS_JSON=$( \
  gh pr view "$PR_NUMBER" \
    --json commits \
    --jq '.commits[] | {sha: .oid, message: .messageHeadline}' \
)

# Run the specified command on each commit
FAILED_COMMITS="false"
while IFS= read -r commit; do
  COMMIT_SHA=$(jq -r '.sha' <<< "$commit")
  COMMIT_MESSAGE=$(jq -r .message <<< "$commit")
  COMMAND_OK="true"

  echo ""

  # Checkout the commit
  echo "⚡️ Checking out ${COMMIT_SHA:0:7}: $COMMIT_MESSAGE"
  git checkout "$COMMIT_SHA" &>/dev/null

  # Run the command
  echo "⚙️ Running: ${COMMAND[*]}"
  if [[ "$VERBOSE" == "true" ]]; then
    # Run command with output
    if ! eval "$COMMAND"; then
      COMMAND_OK="false"
      echo "❌ Command failed on commit ${COMMIT_SHA:0:7} ($COMMIT_MESSAGE)"
    fi
  else
    # Run command with output captured
    tmpfile=$(mktemp -t "forall-commits-${COMMIT_SHA:0:7}-XXXXXX.log")
    if ! eval "$COMMAND" &> "$tmpfile"; then
      COMMAND_OK="false"
      echo "❌ Command failed on commit ${COMMIT_SHA:0:7} ($COMMIT_MESSAGE)"
      echo "⚠️ Log is available at $tmpfile"
    else
      rm "$tmpfile"
    fi
  fi

  # Check for diffs if requested
  if [[ "$NO_DIFF" == "true" ]]; then
    echo "🔍 Checking for diffs"
    if ! git diff --exit-code &>/dev/null; then
      COMMAND_OK="false"
      echo "❌ Command produced a diff on commit ${COMMIT_SHA:0:7}"
      git diff
    fi
  fi

  # Continue with next commit or exit based on flag
  if [[ "$COMMAND_OK" == "false" ]]; then
    FAILED_COMMITS="true"
    if [[ "$KEEP_GOING" == "true" ]]; then
      continue
    else
      break
    fi
  fi
done <<< "$(jq -c '.' <<< "$PR_COMMITS_JSON")"

# Print summary
if [[ "$FAILED_COMMITS" == "true" ]]; then
  echo ""
  echo "❌ Some commits failed"
  exit 1
else
  echo ""
  echo "✅ All commits passed"
  exit 0
fi

