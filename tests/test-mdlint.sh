#!/usr/bin/env bash
# Test suite for mdlint.sh
# Run from repo root: bash tests/test-mdlint.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../scripts/mdlint.sh"
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

command -v markdownlint-cli2 >/dev/null 2>&1 || { echo "FAIL: markdownlint-cli2 is required to run this suite"; exit 1; }

echo "mdlint.sh test suite"
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
# auto-fixed (markdownlint cannot guess the language). The hook exits 0 and
# reports it as additionalContext.
# ---------------------------------------------------------------------------
echo ""
echo "--- mdlint.sh: lint error reporting ---"

tmp_md_lint=$(mktemp_md)
printf '# Title\n\n```\nsome code\n```\n' > "$tmp_md_lint"
printf '{"tool_input":{"file_path":"%s"}}' "$tmp_md_lint" | \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" >/dev/null 2>&1
exit_code=$?
if [ "$exit_code" -eq 0 ]; then
  ok "unfixable MD040 (missing code fence language) — exits 0 (non-blocking)"
else
  fail_test "unfixable MD040 — expected exit 0, got $exit_code"
fi

# Capture stdout for the next two assertions (run once, reuse output).
stderr_out=$(printf '{"tool_input":{"file_path":"%s"}}' "$tmp_md_lint" | \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" 2>/dev/null || true)

if echo "$stderr_out" | grep -q "markdownlint left 1 issue"; then
  ok "unfixable MD040 — informational header present in context"
else
  fail_test "unfixable MD040 — informational header missing from context"
fi

if echo "$stderr_out" | grep -q "Add a language tag"; then
  ok "unfixable MD040 — per-rule hint 'Add a language tag' present in context"
else
  fail_test "unfixable MD040 — per-rule hint missing from context"
fi

# ---------------------------------------------------------------------------
# mdlint.sh — markdownlint auto-fix
# MD026 (trailing heading punctuation) is auto-fixable by markdownlint only. These tests verify that
# markdownlint --fix actually runs and modifies the file, not just exits 0.
# ---------------------------------------------------------------------------
echo ""
echo "--- mdlint.sh: markdownlint auto-fix ---"

tmp_md_fix=$(mktemp_md)
printf '# Title\n\n## Done!\n\nText.\n' > "$tmp_md_fix"   # MD026: prettier leaves it, only markdownlint --fix repairs it
before=$(cat "$tmp_md_fix")
printf '{"tool_input":{"file_path":"%s"}}' "$tmp_md_fix" | \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" >/dev/null 2>&1
after=$(cat "$tmp_md_fix")
if [ "$before" != "$after" ]; then
  ok "MD026 auto-fix — markdownlint --fix strips trailing heading punctuation (prettier does not)"
else
  fail_test "MD026 auto-fix — file not modified; markdownlint --fix may not be running"
fi

# A file with both a fixable error (MD026) and an unfixable one (MD040) tests
# that the full pipeline runs: auto-fix applies what it can, then reports what
# it can't, and exits 2 so Claude gets the remaining error.
tmp_md_combo=$(mktemp_md)
printf '# Title\n\n## Done!\n\n```\ncode\n```\n' > "$tmp_md_combo"
before=$(cat "$tmp_md_combo")
printf '{"tool_input":{"file_path":"%s"}}' "$tmp_md_combo" | \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" >/dev/null 2>&1
combo_exit=$?
after=$(cat "$tmp_md_combo")
if [ "$combo_exit" -eq 0 ]; then
  ok "fixable (MD026) + unfixable (MD040) — exits 0 although MD040 cannot be auto-fixed"
else
  fail_test "fixable + unfixable — expected exit 0, got $combo_exit"
fi
if [ "$before" != "$after" ]; then
  ok "fixable (MD026) + unfixable (MD040) — file modified because MD026 was auto-fixed before reporting"
else
  fail_test "fixable + unfixable — file not modified; auto-fix may not have run before error report"
fi

# ---------------------------------------------------------------------------
# PostToolUse if-gate
# The if-gate runs mdlint.sh for .md files and exits 0 cleanly for non-.md
# files.
# ---------------------------------------------------------------------------
echo ""
echo "--- PostToolUse if-gate  ---"

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
if [ "$gate_exit" -eq 0 ]; then
  ok "PostToolUse if-gate — unfixable MD040 exits 0 (never blocks)"
else
  fail_test "PostToolUse if-gate — expected exit 0, got $gate_exit"
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
# hooks.json actual command
# Reads and executes the actual command string from hooks.json.
# ---------------------------------------------------------------------------
echo ""
echo "--- hooks.json actual command ---"

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
if [ "$hjson_exit" -eq 0 ]; then
  ok "hooks.json command — exits 0 for unfixable MD040 (actual hooks.json command string)"
else
  fail_test "hooks.json command — expected exit 0, got $hjson_exit"
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
# hooks.json commands under a plugin root containing a space
# Both hook commands must quote ${CLAUDE_PLUGIN_ROOT}; unquoted, bash
# word-splits the script path and neither hook runs. Copy the plugin into a
# spaced directory and execute both actual command strings from there.
# ---------------------------------------------------------------------------
echo ""
echo "--- hooks.json commands: plugin root with a space ---"

spaced_root="$(mktemp -d)/plugin root"
mkdir -p "$spaced_root"
cp -R "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/config" "$PLUGIN_ROOT/hooks" "$spaced_root/"
post_cmd=$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$spaced_root/hooks/hooks.json")

tmp_md_spaced=$(mktemp_md)
printf '# Title\n\n```\ncode\n```\n' > "$tmp_md_spaced"
spaced_exit=0
printf '{"tool_input":{"file_path":"%s"}}' "$tmp_md_spaced" | \
  CLAUDE_PLUGIN_ROOT="$spaced_root" bash -c "$post_cmd" >/dev/null 2>&1 || spaced_exit=$?
if [ "$spaced_exit" -eq 0 ]; then
  ok "hooks.json PostToolUse command — runs from a spaced plugin root (exit 0)"
else
  fail_test "hooks.json PostToolUse command — spaced plugin root: expected exit 0, got $spaced_exit (unquoted \${CLAUDE_PLUGIN_ROOT}?)"
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
# Config resolution is project .markdownlint.json
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

# ---------------------------------------------------------------------------
# Non-blocking report, silent fix, no Stop hook
# ---------------------------------------------------------------------------
echo ""
echo "--- non-blocking report ---"

# (a) Unfixable issue: exit 0, additionalContext JSON naming the rule.
tmp_a=$(mktemp_md)
printf '# Title\n\n```\ncode\n```\n' > "$tmp_a"
a_exit=0
a_out=$(printf '{"tool_input":{"file_path":"%s"}}' "$tmp_a" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" 2>/dev/null) || a_exit=$?
a_ctx=$(printf '%s' "$a_out" | jq -r 'select(.hookSpecificOutput.hookEventName == "PostToolUse") | .hookSpecificOutput.additionalContext' 2>/dev/null)
if [ "$a_exit" -eq 0 ] && echo "$a_ctx" | grep -q "MD040"; then
  ok "unfixable issue — exit 0 with PostToolUse additionalContext naming MD040"
else
  fail_test "unfixable issue — exit $a_exit, context: $a_ctx"
fi

# (b) Fixable file: fixed, and no output at all.
tmp_b=$(mktemp_md)
printf '# Title\nText right after heading.\n' > "$tmp_b"
before_b=$(cat "$tmp_b")
b_out=$(printf '{"tool_input":{"file_path":"%s"}}' "$tmp_b" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" 2>&1)
if [ "$before_b" != "$(cat "$tmp_b")" ] && [ -z "$b_out" ]; then
  ok "fixable file — fixed silently (no stdout/stderr)"
else
  fail_test "fixable file — output: [$b_out]"
fi

# (c) hooks.json registers no Stop hook.
if [ "$(jq '.hooks | has("Stop")' "$PLUGIN_ROOT/hooks/hooks.json")" = "false" ]; then
  ok "hooks.json has no Stop entry"
else
  fail_test "hooks.json still registers a Stop hook"
fi

# (d) The resolved config applies to a file outside the hook's cwd (markdownlint-cli2
# lets a config found from cwd override --config for such a file). MD036 is off in the bundled config.
tmp_d=$(mktemp_md)
printf '# Title\n\n**Bold heading**\n\nText.\n' > "$tmp_d"
other_cwd=$(mktemp -d)
printf '{"MD036": true}\n' > "$other_cwd/.markdownlint.json"   # a cwd config that must not shadow --config
d_out=$(cd "$other_cwd" && printf '{"tool_input":{"file_path":"%s"}}' "$tmp_d" | HOME="$(mktemp -d)" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" 2>&1)
if [ -z "$d_out" ]; then
  ok "config applies to a file outside cwd — no MD036 note"
else
  fail_test "config ignored outside cwd: $d_out"
fi

# (e) Precedence: project > $HOME > plugin default. Fake HOMEs only; the real one is never read.
bold_note() {  # bold_note <home> <project_dir or ""> -> hook output for a bold-as-heading file
  local f; f=$(mktemp_md)
  printf '# Title\n\n**Bold heading**\n\nText.\n' > "$f"
  printf '{"tool_input":{"file_path":"%s"}}' "$f" | HOME="$1" CLAUDE_PROJECT_DIR="$2" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" 2>&1
}
empty_home=$(mktemp -d)
home_on=$(mktemp -d);  printf '{"MD036": true}\n'  > "$home_on/.markdownlint.json"
proj_off=$(mktemp -d); printf '{"MD036": false}\n' > "$proj_off/.markdownlint.json"
proj_on=$(mktemp -d);  printf '{"MD036": true}\n'  > "$proj_on/.markdownlint.json"

plugin_out=$(bold_note "$empty_home" "")
home_out=$(bold_note "$home_on" "")
proj_beats_home_out=$(bold_note "$home_on" "$proj_off")
proj_out=$(bold_note "$empty_home" "$proj_on")

# Positive controls: an MD036-on config (home or project) DOES report, so the empty outputs mean
# the file was examined under a config that turns MD036 off, not skipped.
if echo "$home_out" | grep -q "MD036" && echo "$proj_out" | grep -q "MD036"; then
  ok "config precedence — positive control: MD036-on home and project configs report MD036"
else
  fail_test "config precedence — home beats plugin / project config: home=[$home_out] project=[$proj_out]"
fi
if [ -z "$plugin_out" ]; then
  ok "config precedence — plugin default applies when neither project nor home config exists"
else
  fail_test "config precedence — plugin default: $plugin_out"
fi
if [ -z "$proj_beats_home_out" ]; then
  ok "config precedence — project config beats \$HOME config"
else
  fail_test "config precedence — project did not beat home: $proj_beats_home_out"
fi

# --- Summary ---
echo ""
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && exit 0 || exit 1
