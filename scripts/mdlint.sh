#!/usr/bin/env bash
set -euo pipefail

#@check 1  format  Prettier — table alignment, whitespace, list indentation
#@check 2  fix     Markdownlint auto-fix — heading structure, blank lines, code fences
#@check 3  report  Remaining unfixable issues → fed back to Claude with fix hints

# --- --help: print check summary from #@check tags in this script ---
if [ "${1:-}" = "--help" ]; then
  echo "mdlint — PostToolUse hook: auto-format markdown after Write/Edit"
  echo ""
  echo "Pipeline:"
  grep '^#@check' "$0" | sed 's/^#@check /  /'
  echo ""
  echo "Requires: prettier, markdownlint-cli2"
  exit 0
fi

# PostToolUse hook: auto-format and lint markdown files after Write or Edit
# Pipeline: prettier (formatting) → markdownlint --fix (structural) → report unfixable

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

# Step 1: Prettier — table alignment, whitespace, list indentation
if command -v prettier &>/dev/null; then
  prettier --write --prose-wrap preserve "$file_path" >/dev/null 2>&1 || true
fi

# Step 2: Markdownlint auto-fix — heading structure, blank lines, code fences
if command -v markdownlint-cli2 &>/dev/null; then
  markdownlint-cli2 --fix --config "$LINT_CONFIG" "$file_path" 2>/dev/null || true

  # Step 3: Report any remaining unfixable issues
  output=$(markdownlint-cli2 --config "$LINT_CONFIG" "$file_path" 2>&1) || true
  if [[ -n "$output" && "$output" == *"error(s)"* && "$output" != *"0 error(s)"* ]]; then
    errors=$(echo "$output" | grep "error MD" || true)
    if [[ -n "$errors" ]]; then
      {
        echo "MARKDOWN LINT — fix before continuing:"
        echo "$errors" | while IFS= read -r line; do
          rule=$(echo "$line" | grep -o 'MD[0-9]*/[a-z-]*' || true)
          case "$rule" in
            MD040/fenced-code-language)
              echo "  $line"
              echo "  → Add a language tag: \`\`\`text, \`\`\`json, \`\`\`markdown, etc."
              ;;
            MD031/blanks-around-fences)
              echo "  $line"
              echo "  → Add a blank line before/after the code fence."
              ;;
            MD022/blanks-around-headings)
              echo "  $line"
              echo "  → Add a blank line before/after the heading."
              ;;
            *)
              echo "  $line"
              ;;
          esac
        done
      } >&2
      # Exit 2 so Claude Code feeds stderr back to the model
      exit 2
    fi
  fi
fi

exit 0
