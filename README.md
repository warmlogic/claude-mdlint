# mdlint

Auto-format and lint markdown files written by Claude Code. Runs prettier and markdownlint on every Write/Edit of a `.md` file.

## How it works

Run `bash scripts/mdlint.sh --help` for current checks.

**PostToolUse (Write/Edit):**

1. Prettier formats tables, whitespace, list indentation
2. Markdownlint auto-fixes heading structure, blank lines, code fences
3. Remaining unfixable issues are reported back to Claude with fix hints

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
