# AGENTS.md — mdlint developer guide

This is the canonical contributor guide, at the repo root. `.claude/CLAUDE.md` is a symlink to
this file, so Claude Code loads the same content as project memory.

Claude Code plugin that auto-formats and lints Markdown files. One PostToolUse hook in `scripts/` formats edited `.md` files and never blocks the agent.

## Running tests

```bash
bash tests/test-mdlint.sh   # must pass before committing
```

Tests use isolated `mktemp` git repos — they never touch the working tree.

## Project layout

```text
scripts/
  mdlint.sh          # PostToolUse: prettier → markdownlint --fix → leftover issues as additionalContext (always exit 0)
hooks/
  hooks.json         # hook registration: PostToolUse (Edit|Write|MultiEdit) only
config/
  .markdownlint.json # bundled default lint config
.claude-plugin/
  plugin.json        # name/description — unversioned; see "Unversioned" below
```

## Non-obvious design decisions

- **The hook never blocks.** Leftover issues go out as JSON on stdout (`{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"..."}}`) with exit 0, so Claude sees them as context. There is no Stop hook: PostToolUse already formats every Write/Edit, and a Stop-time check could only duplicate it or block the agent. A missing `prettier` or `markdownlint-cli2` makes the hook a no-op.
- **The PostToolUse hook command uses an `if`-gate** that runs `mdlint.sh` only for `.md` paths and cleanly no-ops for other edits.
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
