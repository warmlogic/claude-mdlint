#!/usr/bin/env bash
set -euo pipefail

#@check 1  scan    Find all modified/staged .md files in the git working tree
#@check 2  lint    Run markdownlint on each, collect unfixable errors
#@check 3  report  Surface up to 10 issues as a final safety net

# --- --help: print check summary from #@check tags in this script ---
if [ "${1:-}" = "--help" ]; then
  echo "mdlint-check — Stop hook: final markdown lint check on modified files"
  echo ""
  echo "Pipeline:"
  grep '^#@check' "$0" | sed 's/^#@check /  /'
  echo ""
  echo "Requires: markdownlint-cli2, git"
  exit 0
fi

# Stop hook: final markdown lint check on all modified .md files
# Safety net — catches anything missed during the session

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# Config priority: project > user home > plugin default.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.markdownlint.json" ]; then
  LINT_CONFIG="$CLAUDE_PROJECT_DIR/.markdownlint.json"
elif [ -f "$HOME/.markdownlint.json" ]; then
  LINT_CONFIG="$HOME/.markdownlint.json"
else
  LINT_CONFIG="$PLUGIN_ROOT/config/.markdownlint.json"
fi

if ! command -v markdownlint-cli2 &>/dev/null; then
  exit 0
fi

# Find modified/staged .md files
files=$(git diff --name-only --diff-filter=ACMR HEAD 2>/dev/null | grep '\.md$' || true)
staged=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep '\.md$' || true)
all_files=$(echo -e "$files\n$staged" | sort -u | grep -v '^$' || true)

if [[ -z "$all_files" ]]; then
  exit 0
fi

errors=""
while IFS= read -r f; do
  if [[ -f "$f" ]]; then
    out=$(markdownlint-cli2 --config "$LINT_CONFIG" "$f" 2>&1) || true
    if [[ "$out" == *"error(s)"* && "$out" != *"0 error(s)"* ]]; then
      file_errors=$(echo "$out" | grep "error MD" || true)
      if [[ -n "$file_errors" ]]; then
        errors="$errors$file_errors"$'\n'
      fi
    fi
  fi
done <<< "$all_files"

if [[ -n "$errors" ]]; then
  count=$(echo "$errors" | grep -c "error MD" || true)
  {
    echo "MARKDOWN LINT — $count unfixed issue(s) in modified files:"
    echo "$errors" | head -10
    if [[ $count -gt 10 ]]; then
      echo "  ... and $((count - 10)) more"
    fi
  } >&2
  # Exit 2 so Claude Code feeds stderr back to the model
  exit 2
fi

exit 0
