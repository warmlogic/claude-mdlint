# AGENTS.md — mdlint developer guide

This is the canonical contributor guide, at the repo root. `.claude/CLAUDE.md` is a symlink to
this file, so Claude Code loads the same content as project memory.

Claude Code plugin that auto-formats and lints Markdown files. Two hooks live in `scripts/`; PostToolUse formats and records edited paths, Stop lints them.

## Running tests

```bash
bash tests/test-mdlint.sh   # must pass before committing
```

Tests use isolated `mktemp` git repos — they never touch the working tree.

## Project layout

```text
scripts/
  _autofix.sh        # run_autofix(file, config) — sourced by mdlint.sh
  mdlint.sh          # PostToolUse: prettier → markdownlint --fix → report unfixable → exit 2; records the path per session_id
  mdlint-check.sh    # Stop: lint-only over the session's recorded paths → report unfixable → exit 2
hooks/
  hooks.json         # hook registration: PostToolUse (Edit|Write|MultiEdit) + Stop
config/
  .markdownlint.json # bundled default lint config
.claude-plugin/
  plugin.json        # name/description — unversioned; see "Unversioned" below
```

## Non-obvious design decisions

- **Stop is scoped to the session's own edits.** PostToolUse appends each edited `.md` path to `$TMPDIR/mdlint-sessions/<session_id>.list` (`session_id` comes from the hook's stdin JSON); Stop lints only the paths on its own session's list that still exist, never rewrites, and deletes the list on exit 0. It does not scan the git tree, so a session whose cwd sits in another agent's worktree neither touches nor reports that agent's files. A session with no PostToolUse edits (for example a background session where that hook does not fire) has no list and Stop is a no-op.
- **The PostToolUse hook command uses an `if`-gate, not `|| true`.** `|| true` swallows `mdlint.sh`'s intentional `exit 2`, preventing unfixable-issue feedback from reaching the model. The `if`-gate lets the exit code propagate for `.md` files while cleanly no-op'ing for non-`.md` edits.
- **`_autofix.sh` is sourced, not executed.** Sourcing inherits the caller's PATH and `set -euo pipefail` without forking a subprocess.
- **Config priority** (runtime): `$CLAUDE_PROJECT_DIR/.markdownlint.json` → `$HOME/.markdownlint.json` → `config/.markdownlint.json`. Projects and users override the bundled default; the bundled default is the final fallback.

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
