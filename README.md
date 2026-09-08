# mdlint

Auto-format and lint markdown files written by Claude Code. Two hooks work together: one fires on every Write/Edit, the other runs at session end as a safety net.

## How it works

### PostToolUse — `scripts/mdlint.sh` (triggered on Write/Edit/MultiEdit)

Runs immediately after Claude writes or edits a `.md` file:

1. Prettier formats tables, whitespace, list indentation
2. Markdownlint auto-fixes heading structure, blank lines, code fences
3. Remaining unfixable issues are reported back to Claude with fix hints

Run `bash scripts/mdlint.sh --help` for the full check list.

### Stop — `scripts/mdlint-check.sh` (triggered at session end)

Scans all git-modified `.md` files when the session ends. Runs the same auto-fix pass as the PostToolUse hook (prettier + markdownlint --fix), then reports genuinely unfixable issues back to Claude. This covers background/headless sessions where PostToolUse never fires.

Run `bash scripts/mdlint-check.sh --help` for details.

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

To customize, place a `.markdownlint.json` in your project root or `~/.markdownlint.json` in your home directory — these override the plugin default. Resolution is project → `$HOME` → plugin default, and whichever file wins is used whole, not merged with the plugin config — so a rule you disabled in the plugin default (like MD018, see above) must also be disabled in any project or `$HOME` override, or it comes back. To change the plugin default itself, edit `config/.markdownlint.json` in the plugin directory.
