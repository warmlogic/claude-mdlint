# Sourced by the hooks.json gate and every hook script, so they all find tools the same way.
# Claude Code hooks run in a non-login shell, where Homebrew's bin dirs may be off PATH:
# prepend them. One assignment, no word-splitting, so it works in sh, bash and zsh.
# MDLINT_TOOL_DIRS (colon-separated) replaces the list; the test suite points it at stub dirs.
export PATH="${MDLINT_TOOL_DIRS:-/opt/homebrew/bin:/usr/local/bin}:$PATH"
