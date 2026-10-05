# mdlint

Auto-format markdown files written by Claude Code. One hook, and it never blocks the agent.

## How it works

### PostToolUse — `scripts/mdlint.sh` (triggered on Write/Edit/MultiEdit)

Runs immediately after Claude writes or edits a `.md` file:

1. Prettier formats tables, whitespace, list indentation
2. Markdownlint auto-fixes heading structure, blank lines, code fences
3. Issues markdownlint cannot auto-fix are passed to Claude as informational context (`hookSpecificOutput.additionalContext`, exit 0), with a fix hint for the common ones

A file that is fixed cleanly produces no output. The hook always exits 0 and does nothing if prettier or markdownlint is missing. There is no Stop hook.

Run `bash scripts/mdlint.sh --help` for the full check list.

## Lint config

The bundled default (`config/.markdownlint.json`) keeps markdownlint's default rules and turns off the ones that cannot be auto-fixed and are mostly noise in agent-written docs (MD013, MD018, MD025, MD033, MD036, MD041, MD059), limits MD024 to sibling headings, and aligns tables (MD060). Override it with `$CLAUDE_PROJECT_DIR/.markdownlint.json` or `$HOME/.markdownlint.json`.

Rules that can still leave a note after the fix pass: MD001, MD003, MD024, MD028, MD040, MD042, MD045, MD046, MD051, MD052, MD056.

## Known normalizations

Prettier rewrites single emphasis `*x*` to `_x_`; this is prettier's markdown printer, has no option, and is accepted — rendered output is identical.

## Installation

Enable the plugin in your Claude Code settings:

```json
{
  "enabledPlugins": {
    "mdlint@ai-plugin-marketplace": true
  }
}
```

## Dependencies

- `prettier` — `brew install prettier`
- `markdownlint-cli2` — `brew install markdownlint-cli2`

Both are optional — the hooks skip gracefully if either is missing.

## Configuration

The bundled `config/.markdownlint.json` enables:

- MD001: heading increment
- MD022: blanks around headings
- MD031: blanks around fences
- MD032: blanks around lists
- MD040: fenced code language
- MD060: table column style (aligned — Prettier produces this by default)

And disables:

- MD013: line length (no limit enforced)
- MD018: no space after hash on atx heading (a bare `#NNN` like `#463` is a paragraph, not a heading — fixing it would change document semantics)
- MD033: inline HTML (needed for some markdown features)
- MD041: first line heading (not every file starts with a heading)

To customize, place a `.markdownlint.json` in your project root, or `~/.markdownlint.json` as a personal default across projects. Resolution is project → `$HOME` → plugin default, and the winning file replaces the plugin default whole rather than merging with it — so start a personal or project file as a copy of `config/.markdownlint.json` and change only what you want; a rule the plugin default disables (like MD018, see above) comes back unless the copy keeps it off. To change the plugin default itself, edit `config/.markdownlint.json` in the plugin directory.
