#!/usr/bin/env bash
# Test suite for mdlint.sh and mdlint-check.sh
# Run from repo root: bash plugins/mdlint/tests/test-mdlint.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../scripts/mdlint.sh"
CHECK_HOOK="$SCRIPT_DIR/../scripts/mdlint-check.sh"
PLUGIN_ROOT="$SCRIPT_DIR/.."

pass=0
fail=0
tn=0

# BSD mktemp (macOS) requires X's at the end — create without extension then rename.
mktemp_md() {
  local t
  t=$(mktemp /tmp/test-mdlint-XXXXXX)
  mv "$t" "${t}.md"
  echo "${t}.md"
}

# Create an isolated git repo with one empty commit so git diff works cleanly.
setup_git_repo() {
  local dir
  dir=$(mktemp -d)
  git -C "$dir" init -q
  git -C "$dir" -c user.email=t@t.com -c user.name=T commit --allow-empty -q -m "init"
  echo "$dir"
}

# Pipe a PostToolUse JSON payload into the hook.
run_hook() {
  local file_path="$1"
  printf '{"tool_input":{"file_path":"%s"}}' "$file_path" | \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" >/dev/null 2>&1
}

# Run hook with a minimal PATH that excludes /opt/homebrew/bin (simulates CC hook env).
run_hook_minimal_path() {
  local file_path="$1"
  printf '{"tool_input":{"file_path":"%s"}}' "$file_path" | \
    env -i HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" >/dev/null 2>&1
}

ok() { pass=$((pass+1)); tn=$((tn+1)); echo "  Test $tn ok: $1"; }
fail_test() { fail=$((fail+1)); tn=$((tn+1)); echo "  Test $tn FAIL: $1"; }

expect_exit() {
  local label="$1" expected="$2" file="$3"
  run_hook "$file"
  local actual=$?
  if [ "$actual" -eq "$expected" ]; then ok "$label"; else fail_test "$label (expected exit $expected, got $actual)"; fi
}

echo "mdlint.sh + mdlint-check.sh test suite"
echo "======================================="

# ---------------------------------------------------------------------------
# mdlint.sh — early-exit / skip
# These tests verify the hook exits immediately without processing when the
# file path doesn't need formatting.
# ---------------------------------------------------------------------------
echo ""
echo "--- mdlint.sh: early-exit / skip ---"

tmp_txt=$(mktemp /tmp/test-mdlint-XXXXXX)
printf 'not markdown\n' > "$tmp_txt"
expect_exit "non-.md file — hook skips immediately, exits 0" 0 "$tmp_txt"

expect_exit "nonexistent .md path — hook skips if file does not exist, exits 0" 0 "/tmp/test-mdlint-does-not-exist-12345.md"

tmp_md=$(mktemp_md)
printf '# Hello\n\nClean file.\n' > "$tmp_md"
expect_exit "clean .md with no issues — prettier + markdownlint run cleanly, exits 0" 0 "$tmp_md"

# ---------------------------------------------------------------------------
# mdlint.sh — PATH regression
# CC hooks run in a non-login shell. Before the fix, /opt/homebrew/bin was
# missing from PATH, causing jq (called before PATH injection) to crash and
# prettier/markdownlint-cli2 to silently no-op.
# ---------------------------------------------------------------------------
echo ""
echo "--- mdlint.sh: PATH regression ---"

tmp_md_path=$(mktemp_md)
printf '# Title\n\nSome content.\n' > "$tmp_md_path"
run_hook_minimal_path "$tmp_md_path"
if [ $? -eq 0 ]; then
  ok "minimal PATH env — hook runs without error (jq + all tools reachable after injection)"
else
  fail_test "minimal PATH env — hook errored; PATH injection may have regressed"
fi

# prettier normalizes |Name|Value| → | Name | Value |; file change proves the
# binary was actually found and executed, not just silently skipped.
tmp_md_prettier=$(mktemp_md)
printf '|Name|Value|\n|---|---|\n|Ada|42|\n' > "$tmp_md_prettier"
before=$(cat "$tmp_md_prettier")
run_hook_minimal_path "$tmp_md_prettier"
after=$(cat "$tmp_md_prettier")
if [ "$before" != "$after" ]; then
  ok "minimal PATH env — prettier found and reformatted table (PATH injection confirmed effective)"
else
  fail_test "minimal PATH env — prettier did not modify file; binaries may not be found"
fi

# ---------------------------------------------------------------------------
# mdlint.sh — lint error reporting
# MD040 (fenced-code-language) is enabled in the plugin config and cannot be
# auto-fixed (markdownlint cannot guess the language). The hook must exit 2
# so Claude Code feeds the error back to the model.
# ---------------------------------------------------------------------------
echo ""
echo "--- mdlint.sh: lint error reporting ---"

tmp_md_lint=$(mktemp_md)
printf '# Title\n\n```\nsome code\n```\n' > "$tmp_md_lint"
printf '{"tool_input":{"file_path":"%s"}}' "$tmp_md_lint" | \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" >/dev/null 2>&1
exit_code=$?
if [ "$exit_code" -eq 2 ]; then
  ok "unfixable MD040 (missing code fence language) — exits 2 to surface error to Claude"
else
  fail_test "unfixable MD040 — expected exit 2, got $exit_code"
fi

# Capture stderr for the next two assertions (run once, reuse output).
stderr_out=$(printf '{"tool_input":{"file_path":"%s"}}' "$tmp_md_lint" | \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" 2>&1 >/dev/null || true)

if echo "$stderr_out" | grep -q "MARKDOWN LINT"; then
  ok "unfixable MD040 — 'MARKDOWN LINT' header present in stderr"
else
  fail_test "unfixable MD040 — 'MARKDOWN LINT' header missing from stderr"
fi

if echo "$stderr_out" | grep -q "Add a language tag"; then
  ok "unfixable MD040 — per-rule hint 'Add a language tag' present in stderr"
else
  fail_test "unfixable MD040 — per-rule hint missing from stderr"
fi

# ---------------------------------------------------------------------------
# mdlint.sh — markdownlint auto-fix
# MD022 (blanks-around-headings) is auto-fixable. These tests verify that
# markdownlint --fix actually runs and modifies the file, not just exits 0.
# ---------------------------------------------------------------------------
echo ""
echo "--- mdlint.sh: markdownlint auto-fix ---"

tmp_md_fix=$(mktemp_md)
printf '# Title\nText with no blank line after heading.\n' > "$tmp_md_fix"
before=$(cat "$tmp_md_fix")
printf '{"tool_input":{"file_path":"%s"}}' "$tmp_md_fix" | \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" >/dev/null 2>&1
after=$(cat "$tmp_md_fix")
if [ "$before" != "$after" ]; then
  ok "MD022 auto-fix — markdownlint adds blank line after heading, file content changed"
else
  fail_test "MD022 auto-fix — file not modified; markdownlint --fix may not be running"
fi

# A file with both a fixable error (MD022) and an unfixable one (MD040) tests
# that the full pipeline runs: auto-fix applies what it can, then reports what
# it can't, and exits 2 so Claude gets the remaining error.
tmp_md_combo=$(mktemp_md)
printf '# Title\nText right after heading.\n\n```\ncode\n```\n' > "$tmp_md_combo"
before=$(cat "$tmp_md_combo")
printf '{"tool_input":{"file_path":"%s"}}' "$tmp_md_combo" | \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" >/dev/null 2>&1
combo_exit=$?
after=$(cat "$tmp_md_combo")
if [ "$combo_exit" -eq 2 ]; then
  ok "fixable (MD022) + unfixable (MD040) — exits 2 because MD040 cannot be auto-fixed"
else
  fail_test "fixable + unfixable — expected exit 2, got $combo_exit"
fi
if [ "$before" != "$after" ]; then
  ok "fixable (MD022) + unfixable (MD040) — file modified because MD022 was auto-fixed before reporting"
else
  fail_test "fixable + unfixable — file not modified; auto-fix may not have run before error report"
fi

# ---------------------------------------------------------------------------
# mdlint-check.sh — Stop hook
# mdlint-check.sh runs on Stop (end of session) and scans all modified/staged
# .md files in the git working tree. Tests use an isolated temp git repo so
# they don't interfere with or depend on the state of this repo.
# ---------------------------------------------------------------------------
echo ""
echo "--- mdlint-check.sh: Stop hook ---"

# No staged or unstaged .md changes → nothing to lint, exits 0 immediately.
tmp_repo=$(setup_git_repo)
(cd "$tmp_repo" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CHECK_HOOK") >/dev/null 2>&1
if [ $? -eq 0 ]; then
  ok "no modified .md files in repo — exits 0, nothing to lint"
else
  fail_test "no modified .md files — expected exit 0"
fi

# A staged .md with valid content → markdownlint finds no errors, exits 0.
tmp_repo=$(setup_git_repo)
printf '# Title\n\nClean content.\n' > "$tmp_repo/test.md"
git -C "$tmp_repo" add test.md
(cd "$tmp_repo" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CHECK_HOOK") >/dev/null 2>&1
if [ $? -eq 0 ]; then
  ok "staged clean .md — markdownlint finds no errors, exits 0"
else
  fail_test "staged clean .md — expected exit 0"
fi

# A staged .md with an unfixable MD040 error → auto-fix runs but can't fix it,
# then lint exits 2 and reports to stderr.
tmp_repo=$(setup_git_repo)
printf '# Title\n\n```\ncode\n```\n' > "$tmp_repo/test.md"
git -C "$tmp_repo" add test.md
check_exit=0
check_stderr=$(cd "$tmp_repo" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CHECK_HOOK" 2>&1 >/dev/null) || check_exit=$?
if [ "$check_exit" -eq 2 ]; then
  ok "staged .md with MD040 error — exits 2 to surface unfixed issue at session end"
else
  fail_test "staged .md with MD040 error — expected exit 2, got $check_exit"
fi
if echo "$check_stderr" | grep -q "MARKDOWN LINT"; then
  ok "staged .md with MD040 error — 'MARKDOWN LINT' header present in stderr"
else
  fail_test "staged .md with MD040 error — 'MARKDOWN LINT' header missing from stderr"
fi

# PATH regression for mdlint-check.sh. If PATH injection fails, markdownlint-cli2
# is not found and the script exits 0 via the early-exit guard — silently hiding
# errors. Exit 2 here proves both that markdownlint-cli2 was found AND that it ran.
tmp_repo=$(setup_git_repo)
printf '# Title\n\n```\ncode\n```\n' > "$tmp_repo/test.md"
git -C "$tmp_repo" add test.md
(cd "$tmp_repo" && env -i HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CHECK_HOOK") >/dev/null 2>&1
if [ $? -eq 2 ]; then
  ok "minimal PATH env — markdownlint-cli2 found via PATH injection, error correctly reported"
else
  fail_test "minimal PATH env — expected exit 2; PATH injection may have regressed (silent exit 0 = binary not found)"
fi

# ---------------------------------------------------------------------------
# mdlint-check.sh: Stop hook auto-fix (Bug 1)
# After the fix, mdlint-check.sh must run the same prettier + markdownlint
# --fix pass that mdlint.sh does, so background sessions (no PostToolUse)
# still get formatted at Stop.
# ---------------------------------------------------------------------------
echo ""
echo "--- mdlint-check.sh: Stop hook auto-fix (Bug 1) ---"

# A staged .md with ONLY a prettier-fixable issue (misaligned MD060 table)
# should be auto-formatted by mdlint-check.sh and exit 0.
tmp_repo=$(setup_git_repo)
printf '| A | B |\n| --- | --- |\n| short | a much longer value here |\n' > "$tmp_repo/table.md"
git -C "$tmp_repo" add table.md
before_table=$(cat "$tmp_repo/table.md")
fix_exit=0
(cd "$tmp_repo" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CHECK_HOOK") >/dev/null 2>&1 || fix_exit=$?
after_table=$(cat "$tmp_repo/table.md")
if [ "$before_table" != "$after_table" ]; then
  ok "Stop hook autofix — misaligned table auto-formatted by mdlint-check.sh (bg-session fix)"
else
  fail_test "Stop hook autofix — table not formatted; mdlint-check.sh does not run prettier"
fi
if [ "$fix_exit" -eq 0 ]; then
  ok "Stop hook autofix — exits 0 after auto-fixing a prettier-only issue (no residual errors)"
else
  fail_test "Stop hook autofix — expected exit 0 after auto-fix, got $fix_exit"
fi

# A staged .md with a no-language fenced block (MD040, not auto-fixable) should
# still exit 2 after the fix attempt, with the error reported in stderr.
tmp_repo=$(setup_git_repo)
printf '# Title\n\n```\ncode\n```\n' > "$tmp_repo/unfixable.md"
git -C "$tmp_repo" add unfixable.md
unfixable_exit=0
unfixable_stderr=$(cd "$tmp_repo" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CHECK_HOOK" 2>&1 >/dev/null) || unfixable_exit=$?
if [ "$unfixable_exit" -eq 2 ]; then
  ok "Stop hook autofix — unfixable MD040 still exits 2 after fix attempt"
else
  fail_test "Stop hook autofix — unfixable MD040: expected exit 2, got $unfixable_exit"
fi
if echo "$unfixable_stderr" | grep -q "MD040"; then
  ok "Stop hook autofix — MD040 error present in stderr after failed fix attempt"
else
  fail_test "Stop hook autofix — MD040 missing from stderr"
fi

# ---------------------------------------------------------------------------
# PostToolUse if-gate (Bug 2)
# The old '|| true' swallowed mdlint.sh's exit 2 for unfixable issues.
# The new 'if'-based gating must let exit 2 propagate for .md files while
# still exiting 0 cleanly for non-.md files.
# ---------------------------------------------------------------------------
echo ""
echo "--- PostToolUse if-gate (Bug 2) ---"

run_if_gate() {
  local payload="$1"
  (
    input=$(printf '%s' "$payload")
    if printf '%s' "$input" | jq -e '(.tool_input.file_path // "") | endswith(".md")' >/dev/null 2>&1; then
      printf '%s' "$input" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK"
    fi
  )
}

tmp_md_gate=$(mktemp_md)
printf '# Title\n\n```\ncode\n```\n' > "$tmp_md_gate"
gate_payload=$(printf '{"tool_input":{"file_path":"%s"}}' "$tmp_md_gate")
run_if_gate "$gate_payload" >/dev/null 2>&1
gate_exit=$?
if [ "$gate_exit" -eq 2 ]; then
  ok "PostToolUse if-gate — exit 2 from mdlint.sh propagates to caller (unfixable MD040)"
else
  fail_test "PostToolUse if-gate — expected exit 2, got $gate_exit; exit code may be swallowed"
fi

tmp_txt_gate=$(mktemp /tmp/test-mdlint-XXXXXX)
printf 'not markdown\n' > "$tmp_txt_gate"
txt_payload=$(printf '{"tool_input":{"file_path":"%s"}}' "$tmp_txt_gate")
run_if_gate "$txt_payload" >/dev/null 2>&1
txt_exit=$?
if [ "$txt_exit" -eq 0 ]; then
  ok "PostToolUse if-gate — non-.md file exits 0 cleanly (no false positive)"
else
  fail_test "PostToolUse if-gate — non-.md should exit 0, got $txt_exit"
fi

# ---------------------------------------------------------------------------
# hooks.json actual command (Bug 2 regression)
# Tests that hooks.json was correctly updated to the if-gate form by reading
# and executing the actual command string from hooks.json. If the old '|| true'
# form is still present, the exit-2 test below will fail.
# ---------------------------------------------------------------------------
echo ""
echo "--- hooks.json actual command (Bug 2 regression) ---"

hook_cmd=$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$PLUGIN_ROOT/hooks/hooks.json")

run_hooks_json_cmd() {
  local payload="$1"
  (
    export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
    printf '%s' "$payload" | eval "$hook_cmd"
  )
}

tmp_md_hjson=$(mktemp_md)
printf '# Title\n\n```\ncode\n```\n' > "$tmp_md_hjson"
hjson_payload=$(printf '{"tool_input":{"file_path":"%s"}}' "$tmp_md_hjson")
run_hooks_json_cmd "$hjson_payload" >/dev/null 2>&1
hjson_exit=$?
if [ "$hjson_exit" -eq 2 ]; then
  ok "hooks.json command — exit 2 propagates for unfixable MD040 (actual hooks.json command string)"
else
  fail_test "hooks.json command — expected exit 2, got $hjson_exit (hooks.json may not have been updated)"
fi

tmp_txt_hjson=$(mktemp /tmp/test-mdlint-XXXXXX)
printf 'not markdown\n' > "$tmp_txt_hjson"
txt_hjson_payload=$(printf '{"tool_input":{"file_path":"%s"}}' "$tmp_txt_hjson")
run_hooks_json_cmd "$txt_hjson_payload" >/dev/null 2>&1
txt_hjson_exit=$?
if [ "$txt_hjson_exit" -eq 0 ]; then
  ok "hooks.json command — non-.md input exits 0 cleanly"
else
  fail_test "hooks.json command — non-.md should exit 0, got $txt_hjson_exit"
fi

# ---------------------------------------------------------------------------
# Stop hook: markdownlint --fix leg + fix-then-lint ordering
# Verify that markdownlint --fix runs (not just prettier) and that autofix
# runs BEFORE the lint check (so fixable issues are cleaned up first).
# ---------------------------------------------------------------------------
echo ""
echo "--- Stop hook: markdownlint --fix leg + fix-then-lint ordering ---"

# MD022 (blank line after heading) is fixed by markdownlint --fix, not prettier.
# Before fix: "# Title\nText right after heading.\n" (no blank line)
# After fix:  "# Title\n\nText right after heading.\n" (blank line added)
tmp_repo=$(setup_git_repo)
printf '# Title\nText right after heading.\n' > "$tmp_repo/md022.md"
git -C "$tmp_repo" add md022.md
before_md022=$(cat "$tmp_repo/md022.md")
(cd "$tmp_repo" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CHECK_HOOK") >/dev/null 2>&1
after_md022=$(cat "$tmp_repo/md022.md")
if [ "$before_md022" != "$after_md022" ]; then
  ok "Stop hook autofix — MD022 auto-fixed by markdownlint --fix (not prettier)"
else
  fail_test "Stop hook autofix — MD022 not fixed; markdownlint --fix leg may not run in Stop hook"
fi

# Combo: MD022 (fixable) + MD040 (unfixable).
# Proves fix-then-lint ordering: file modified (MD022 fixed) AND exit 2 (MD040 remains).
tmp_repo=$(setup_git_repo)
printf '# Title\nText right after heading.\n\n```\ncode\n```\n' > "$tmp_repo/combo.md"
git -C "$tmp_repo" add combo.md
before_combo=$(cat "$tmp_repo/combo.md")
combo_exit=0
(cd "$tmp_repo" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CHECK_HOOK") >/dev/null 2>&1 || combo_exit=$?
after_combo=$(cat "$tmp_repo/combo.md")
if [ "$combo_exit" -eq 2 ]; then
  ok "Stop hook fix-then-lint — MD040 still exits 2 after autofix (unfixable error persists)"
else
  fail_test "Stop hook fix-then-lint — expected exit 2, got $combo_exit"
fi
if [ "$before_combo" != "$after_combo" ]; then
  ok "Stop hook fix-then-lint — file modified (MD022 auto-fixed before lint check ran)"
else
  fail_test "Stop hook fix-then-lint — file not modified; autofix may not run before lint"
fi

# ---------------------------------------------------------------------------
# mdlint.sh — semantics-preserving fixture
# The hook must never change document MEANING: a bare "#NNN" line is a
# paragraph (no space after '#'), not an ATX heading (MD018 --fix would
# insert one and turn it into a real heading), and a fenced code block in a
# language prettier recognizes must not be reformatted by that language's
# printer (embeddedLanguageFormatting must be off). Round-trip the fixture
# through the real hook and assert it comes out byte-identical.
# ---------------------------------------------------------------------------
echo ""
echo "--- mdlint.sh: semantics-preserving fixture ---"

# Source fixture is ".in" (non-.md) so the mdlint hook never touches the
# committed copy; the test copies it to a real .md path before piping it
# through the hook, then asserts the .md came out byte-identical to the .in.
#
# Config resolution is project .markdownlint.json -> $HOME/.markdownlint.json
# -> plugin config (config/.markdownlint.json), no merge. This test must
# exercise the PLUGIN's own config, not whatever the operator happens to have
# in their real $HOME or project dir, so it runs with a throwaway HOME and an
# empty CLAUDE_PROJECT_DIR — neither can shadow the plugin config.
fixture_src="$SCRIPT_DIR/fixtures/semantics-preserved.md.in"
tmp_semantics=$(mktemp_md)
cp "$fixture_src" "$tmp_semantics"
tmp_home=$(mktemp -d)
tmp_project_dir=$(mktemp -d)
printf '{"tool_input":{"file_path":"%s"}}' "$tmp_semantics" | \
  HOME="$tmp_home" CLAUDE_PROJECT_DIR="$tmp_project_dir" \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" >/dev/null 2>&1
if cmp -s "$fixture_src" "$tmp_semantics"; then
  ok "semantics-preserved fixture — byte-identical after the hook (no #NNN-to-heading, no fenced-code reformat)"
else
  fail_test "semantics-preserved fixture — hook changed file content; diff:"
  diff "$fixture_src" "$tmp_semantics" || true
fi

# --- Summary ---
echo ""
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && exit 0 || exit 1
