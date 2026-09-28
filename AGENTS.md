# AGENTS.md — mdlint developer guide

This is the canonical contributor guide, at the repo root. `.claude/CLAUDE.md` is a symlink to
this file, so Claude Code loads the same content as project memory.

Claude Code plugin that auto-formats and lints Markdown files. Two hooks share a common fix pass via a sourced helper; both live in `scripts/`.

## Running tests

```bash
bash tests/test-mdlint.sh   # must pass before committing
```

Tests use isolated `mktemp` git repos — they never touch the working tree.

## Project layout

```text
scripts/
  _autofix.sh        # shared: run_autofix(file, config) — sourced by both scripts below
  mdlint.sh          # PostToolUse: prettier → markdownlint --fix → report unfixable → exit 2
  mdlint-check.sh    # Stop: same fix pass (bg-session coverage), then lint → report unfixable
hooks/
  hooks.json         # hook registration: PostToolUse (Edit|Write|MultiEdit) + Stop
config/
  .markdownlint.json # bundled default lint config
.claude-plugin/
  plugin.json        # name/description — unversioned; see "Unversioned" below
```

## Non-obvious design decisions

- **PostToolUse fires in foreground sessions only; Stop fires in all sessions (including background/headless).** Both run the same autofix pass so bg sessions still get formatted. The shared `_autofix.sh` keeps them in sync and prevents drift.
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
