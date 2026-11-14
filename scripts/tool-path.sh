# Sourced by every hook script so they all find tools the same way.
# Claude Code hooks run in a non-login shell, where Homebrew's bin dirs may be off PATH:
# prepend them. MDLINT_TOOL_DIRS replaces the list (the test suite points it at stub dirs).
for _d in ${MDLINT_TOOL_DIRS-/opt/homebrew/bin /usr/local/bin}; do
  [[ -d "$_d" && ":$PATH:" != *":$_d:"* ]] && export PATH="$_d:$PATH"
done
unset _d
