#!/usr/bin/env bash
set -euo pipefail

#@check 1  fix     Prettier + markdownlint auto-fix — tables, whitespace, heading structure, blank lines
#@check 2  report  Issues left after the fix → non-blocking context for Claude (exit 0)

# CC hooks run in a non-login shell — /opt/homebrew/bin isn't on PATH by default
for _d in /opt/homebrew/bin /usr/local/bin; do
  [[ -d "$_d" && ":$PATH:" != *":$_d:"* ]] && export PATH="$_d:$PATH"
done
unset _d

# --- --help: print check summary from #@check tags in this script ---
if [ "${1:-}" = "--help" ]; then
  echo "mdlint — PostToolUse hook: auto-format markdown after Write/Edit"
  echo ""
  echo "Pipeline:"
  grep '^#@check' "$0" | sed 's/^#@check /  /'
  echo ""
  echo "Requires: jq, markdownlint-cli2 (prettier optional). Never blocks: always exits 0."
  exit 0
fi

# PostToolUse hook: auto-format and lint markdown files after Write or Edit
# Pipeline: prettier (formatting) → markdownlint --fix (structural) → report leftovers

# Early exit: read file_path first, skip non-markdown before any other work
file_path=$(jq -r '.tool_input.file_path // ""')

if [[ "$file_path" != *.md ]] || [[ ! -f "$file_path" ]]; then
  exit 0
fi

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# Config priority: project > user home > plugin default.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.markdownlint.json" ]; then
  LINT_CONFIG="$CLAUDE_PROJECT_DIR/.markdownlint.json"
elif [ -f "$HOME/.markdownlint.json" ]; then
  LINT_CONFIG="$HOME/.markdownlint.json"
else
  LINT_CONFIG="$PLUGIN_ROOT/config/.markdownlint.json"
fi

# Step 1: Prettier, then markdownlint --fix (each fails open when missing)
if command -v prettier &>/dev/null; then
  prettier --write --prose-wrap preserve --embedded-language-formatting off "$file_path" >/dev/null 2>&1 || true
fi
command -v markdownlint-cli2 &>/dev/null || exit 0
markdownlint-cli2 --fix --config "$LINT_CONFIG" "$file_path" >/dev/null 2>&1 || true

# Step 2: Report what is left, as context rather than an error
output=$(markdownlint-cli2 --config "$LINT_CONFIG" "$file_path" 2>&1) || true
errors=$(echo "$output" | grep "error MD" || true)
[[ -n "$errors" ]] || exit 0

count=$(echo "$errors" | wc -l | tr -d ' ')
hinted=$(echo "$errors" | while IFS= read -r line; do
  echo "  $line"
  case "$line" in
    *MD040/*) echo "  → Add a language tag: \`\`\`text, \`\`\`json, \`\`\`markdown, etc." ;;
    *MD031/*) echo "  → Add a blank line before/after the code fence." ;;
    *MD022/*) echo "  → Add a blank line before/after the heading." ;;
  esac
done)

jq -n --arg ctx "markdownlint left $count issue(s) it can't auto-fix in $file_path (informational, not blocking):
$hinted" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
exit 0
