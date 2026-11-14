#!/usr/bin/env bash
# SessionStart (startup): say once which tools are missing, what the PostToolUse hook
# skips without each, and how to install it. Silent when all are present; always exit 0.
# Plain stderr at exit 0 isn't shown to the user, so the note goes out as JSON systemMessage.
set -uo pipefail

source "$(dirname "$0")/tool-path.sh"

missing=""
note() {  # note <tool> <what is skipped without it>
  command -v "$1" >/dev/null 2>&1 && return
  missing="$missing\\n- $1: $2 Install: brew install $1"
}
note jq "nothing is formatted or linted (the hook needs jq to read each edit)."
note markdownlint-cli2 "markdown is not lint-fixed, and issues left in it are not reported (prettier still formats)."
note prettier "markdown is not formatted (markdownlint still fixes and reports)."

[ -n "$missing" ] || exit 0
# No jq to build the JSON: the strings above hold no quotes or backslashes, so printf is safe.
printf '{"systemMessage":"mdlint: missing tools, so markdown checks are skipped this session:%s"}\n' "$missing"
exit 0
