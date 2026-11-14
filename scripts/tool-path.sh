# Sourced by the hooks.json gate and every hook script, so they all find tools the same way.
# POSIX sh, since the gate's shell may not be bash.
# Claude Code hooks run in a non-login shell, where Homebrew's bin dirs may be off PATH:
# prepend them. MDLINT_TOOL_DIRS replaces the list (the test suite points it at stub dirs).
for _d in ${MDLINT_TOOL_DIRS-/opt/homebrew/bin /usr/local/bin}; do
  case ":$PATH:" in
    *":$_d:"*) ;;
    *) [ -d "$_d" ] && PATH="$_d:$PATH" ;;
  esac
done
export PATH
unset _d
