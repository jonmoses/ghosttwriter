# Ghosttwriter: launch Claude with the tab's color.
# Ghosttwriter sets TABCOLOR on every surface; `claude` then runs
# `/color $TABCOLOR` on start so its prompt bar matches the sidebar dot.
# Skipped when an argument could be a prompt, subcommand or flag value,
# and for print/help/version/resume.

[[ -o interactive && -n $TABCOLOR ]] || return 0

claude() {
  local a inject=1
  for a in "$@"; do
    case $a in
      -p|--print|-h|--help|-v|--version|-r|--resume|--resume=*) inject=0 ;;
      -*) ;;
      *) inject=0 ;;
    esac
  done
  if (( inject )) && [[ -n $TABCOLOR ]]; then
    command claude "$@" "/color $TABCOLOR"
  else
    command claude "$@"
  fi
}
