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

Scans all git-modified `.md` files when the session ends — catches files modified by shell commands or git operations that never triggered a PostToolUse event. Reports unfixable issues back to Claude; does **not** auto-fix (silent rewrites at session end would be surprising).

Run `bash scripts/mdlint-check.sh --help` for details.

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

And disables:

- MD013: line length (too noisy for AI-generated content)
- MD033: inline HTML (needed for some markdown features)
- MD041: first line heading (not every file starts with a heading)
- MD060: link/image style (no preference)

To customize, edit `config/.markdownlint.json` in the plugin directory.
