#!/usr/bin/env bash
set -euo pipefail

#@check 1  scan    Read the .md paths this session edited (recorded by the PostToolUse hook)
#@check 2  lint    Lint each path that still exists, collect unfixed errors
#@check 3  report  Surface up to 10 issues as a final safety net; drop the list on a clean exit

# --- --help: print check summary from #@check tags in this script ---
if [ "${1:-}" = "--help" ]; then
  echo "mdlint-check — Stop hook: lint the .md files this session edited"
  echo ""
  echo "Pipeline:"
  grep '^#@check' "$0" | sed 's/^#@check /  /'
  echo ""
  echo "Requires: markdownlint-cli2, jq"
  exit 0
fi

# Stop hook: final markdown lint check on the .md files this session edited.
# Lint only, never rewrites; files the session did not edit are out of scope.

# CC hooks run in a non-login shell — /opt/homebrew/bin isn't on PATH by default
for _d in /opt/homebrew/bin /usr/local/bin; do
  [[ -d "$_d" && ":$PATH:" != *":$_d:"* ]] && export PATH="$_d:$PATH"
done
unset _d

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# Config priority: project > user home > plugin default.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.markdownlint.json" ]; then
  LINT_CONFIG="$CLAUDE_PROJECT_DIR/.markdownlint.json"
elif [ -f "$HOME/.markdownlint.json" ]; then
  LINT_CONFIG="$HOME/.markdownlint.json"
else
  LINT_CONFIG="$PLUGIN_ROOT/config/.markdownlint.json"
fi

# Paths this session edited (deduplicated; the list is keyed by session_id)
session_id=$(jq -r '.session_id // ""')
list="${TMPDIR:-/tmp}/mdlint-sessions/$session_id.list"
if [[ ! "$session_id" =~ ^[A-Za-z0-9_-]+$ ]] || [[ ! -s "$list" ]]; then
  exit 0
fi

errors=""
if command -v markdownlint-cli2 &>/dev/null; then
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    out=$(markdownlint-cli2 --config "$LINT_CONFIG" "$f" 2>&1) && f_lint_exit=0 || f_lint_exit=$?
    if [[ $f_lint_exit -ne 0 ]]; then
      file_errors=$(echo "$out" | grep "error MD" || true)
      if [[ -n "$file_errors" ]]; then
        errors="$errors$file_errors"$'\n'
      fi
    fi
  done < <(sort -u "$list")
fi

if [[ -n "$errors" ]]; then
  count=$(echo "$errors" | grep -c "error MD" || true)
  {
    echo "MARKDOWN LINT — $count unfixed issue(s) in files edited this session:"
    echo "$errors" | head -10
    if [[ $count -gt 10 ]]; then
      echo "  ... and $((count - 10)) more"
    fi
  } >&2
  # Exit 2 so Claude Code feeds stderr back to the model
  exit 2
fi

rm -f "$list"
exit 0
