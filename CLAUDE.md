# CLAUDE.md — mdlint developer guide

Claude Code plugin that auto-formats and lints Markdown files. Two hooks share a common fix pass via a sourced helper; both live in `scripts/`.

## Running tests

```bash
bash tests/test-mdlint.sh   # must pass before committing
```

Tests use isolated `mktemp` git repos — they never touch the working tree.

## Project layout

```
scripts/
  _autofix.sh        # shared: run_autofix(file, config) — sourced by both scripts below
  mdlint.sh          # PostToolUse: prettier → markdownlint --fix → report unfixable → exit 2
  mdlint-check.sh    # Stop: same fix pass (bg-session coverage), then lint → report unfixable
hooks/
  hooks.json         # hook registration: PostToolUse (Edit|Write|MultiEdit) + Stop
config/
  .markdownlint.json # bundled default lint config
.claude-plugin/
  plugin.json        # name/version — bump version on every PR
```

## Non-obvious design decisions

- **PostToolUse fires in foreground sessions only; Stop fires in all sessions (including background/headless).** Both run the same autofix pass so bg sessions still get formatted. The shared `_autofix.sh` keeps them in sync and prevents drift.
- **The PostToolUse hook command uses an `if`-gate, not `|| true`.** `|| true` swallows `mdlint.sh`'s intentional `exit 2`, preventing unfixable-issue feedback from reaching the model. The `if`-gate lets the exit code propagate for `.md` files while cleanly no-op'ing for non-`.md` edits.
- **`_autofix.sh` is sourced, not executed.** Sourcing inherits the caller's PATH and `set -euo pipefail` without forking a subprocess.
- **Config priority** (runtime): `$CLAUDE_PROJECT_DIR/.markdownlint.json` → `$HOME/.markdownlint.json` → `config/.markdownlint.json`. Projects and users override the bundled default; the bundled default is the final fallback.

## Versioning

Bump `version` in `.claude-plugin/plugin.json` on every PR. Convention: `fix` → patch, `feat` → minor.

## Don't edit the plugin cache

The installed copy lives at `~/.claude/plugins/cache/ai-plugin-marketplace/mdlint/<version>/`. That directory is **overwritten on plugin update**. Edit the source repo, bump the version, then reinstall.
