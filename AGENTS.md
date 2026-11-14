# AGENTS.md — mdlint developer guide

This is the canonical contributor guide, at the repo root. `.claude/CLAUDE.md` is a symlink to
this file, so Claude Code loads the same content as project memory.

Claude Code plugin that auto-formats and lints Markdown files. A PostToolUse hook formats edited `.md` files and never blocks the agent; a SessionStart hook names any tool it is missing when a new session starts.

## Running tests

```bash
bash tests/test-mdlint.sh   # must pass before committing
```

Tests use isolated `mktemp` git repos — they never touch the working tree.

## Project layout

```text
scripts/
  mdlint.sh          # PostToolUse: prettier → markdownlint --fix → leftover issues as additionalContext (always exit 0)
  check-deps.sh      # SessionStart (startup): names missing jq / markdownlint-cli2 / prettier as systemMessage (always exit 0)
  tool-path.sh       # sourced by the hooks.json gate and both scripts: appends Homebrew bin dirs to PATH
hooks/
  hooks.json         # hook registration: SessionStart (startup) and PostToolUse (Edit|Write|MultiEdit)
config/
  .markdownlint.json # bundled default lint config
.claude-plugin/
  plugin.json        # name/description — unversioned; see "Unversioned" below
```

## Non-obvious design decisions

- **The hook never blocks.** Leftover issues go out as JSON on stdout (`{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"..."}}`) with exit 0, so Claude sees them as context. There is no Stop hook: PostToolUse already formats every Write/Edit, and a Stop-time check could only duplicate it or block the agent. A missing tool makes it skip that tool's step (no jq: the gate skips everything; no markdownlint-cli2: lint fix and report; no prettier: formatting).
- **Missing tools are named when a new session starts** ([runtime contract](https://github.com/warmlogic/ai-plugin-marketplace/blob/main/RUNTIME.md), rule 4). The PostToolUse hook stays fail-open and quiet on every edit; `check-deps.sh` runs on `startup` only and reports through JSON `systemMessage`, because a hook's plain stderr at exit 0 is not shown to the user. It builds that JSON with `printf`, since jq may be the missing tool. Hooks stay in the hook's process group (no `setsid`, `setpgid` or backgrounded daemon): Claude Code ends a timed-out hook by signaling that group.
- **Every hook finds tools the same way.** Hooks run in a non-login shell, so `tool-path.sh` appends `/opt/homebrew/bin` and `/usr/local/bin` to PATH (appends, so a tool already on PATH keeps the user's order), and the hooks.json gate (before its `jq`) and both scripts source it; otherwise the session-start check could disagree with what the edit hook finds. `MDLINT_TOOL_DIRS` (colon-separated) replaces that list, which is how the tests make a tool genuinely missing: trimming PATH alone doesn't, because the injection finds the Homebrew copy again.
- **The PostToolUse hook command uses an `if`-gate** that runs `mdlint.sh` only for `.md` paths and cleanly no-ops for other edits.
- **Config priority** (runtime): `$CLAUDE_PROJECT_DIR/.markdownlint.json` → `$HOME/.markdownlint.json` → `config/.markdownlint.json`. The winning file replaces the bundled default whole (no merge), so a personal or project file should start as a copy of the bundled one.
- **Tools run from the edited file's directory, on its basename.** markdownlint-cli2 lets a config discovered from cwd override `--config` for a file outside cwd, and hooks run with cwd = the project dir, so running from the file's dir makes `--config` win everywhere. The report therefore shows the basename; the message header carries the full path.

## Unversioned

This plugin carries no `version` field — not in `.claude-plugin/plugin.json`, nor in the
marketplace catalog entry. Claude Code keys an unversioned install by the git commit SHA of
the source, so every merge to `main` is a release: there is nothing to bump, and no separate
publish step beyond merging. `claude plugin validate .` warns "No version specified" for this
— that one warning is expected and accepted; don't add a `version` field to silence it.

The catalog entry for this plugin uses a GitHub `source`, so it must keep its own
`description`, kept verbatim equal to `.claude-plugin/plugin.json`'s `description` (a
GitHub-sourced entry shows nothing in `claude plugin` browse without it).

## Don't edit the plugin cache

The installed copy lives at `~/.claude/plugins/cache/ai-plugin-marketplace/mdlint/<sha12>/`
(the first 12 characters of the source commit's SHA). That directory is **overwritten on
plugin update**. Edit the source repo and reinstall — there's no version to bump.
