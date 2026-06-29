#!/usr/bin/env bash
# Shared auto-fix pass: prettier → markdownlint --fix.
# Source this file, then call: run_autofix <file_path> <lint_config>

run_autofix() {
  local fp="$1"
  local cfg="$2"
  command -v prettier &>/dev/null && \
    prettier --write --prose-wrap preserve "$fp" >/dev/null 2>&1 || true
  command -v markdownlint-cli2 &>/dev/null && \
    markdownlint-cli2 --fix --config "$cfg" "$fp" 2>/dev/null || true
}
