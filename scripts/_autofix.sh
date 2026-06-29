#!/usr/bin/env bash
# Shared auto-fix pass: prettier → markdownlint --fix.
# Source this file, then call: run_autofix <file_path> <lint_config>

run_autofix() {
  local fp="$1"
  local cfg="$2"
  if command -v prettier &>/dev/null; then
    prettier --write --prose-wrap preserve "$fp" >/dev/null 2>&1 || true
  fi
  if command -v markdownlint-cli2 &>/dev/null; then
    markdownlint-cli2 --fix --config "$cfg" "$fp" 2>/dev/null || true
  fi
}
