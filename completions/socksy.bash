# bash completion for socksy
_socksy() {
  local cur prev words cword
  _init_completion 2>/dev/null || {
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cword=$COMP_CWORD
  }

  local cmds="set on off rotate run status test watch watchdog logs dns bypass save use list rm --version --help"

  if [ "$cword" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
    return
  fi

  local sub="${COMP_WORDS[1]}"
  case "$sub" in
    dns)
      COMPREPLY=( $(compgen -W "on off reset status" -- "$cur") ) ;;
    watchdog)
      COMPREPLY=( $(compgen -W "on off status" -- "$cur") ) ;;
    bypass)
      COMPREPLY=( $(compgen -W "list add rm reset" -- "$cur") ) ;;
    status)
      COMPREPLY=( $(compgen -W "--json" -- "$cur") ) ;;
    logs)
      COMPREPLY=( $(compgen -W "-f -n" -- "$cur") ) ;;
    use|rm)
      # complete saved profile names
      local names; names="$(socksy profiles 2>/dev/null)"
      COMPREPLY=( $(compgen -W "$names" -- "$cur") ) ;;
    set)
      COMPREPLY=( $(compgen -W "--type --country --sticky --session" -- "$cur") ) ;;
    run)
      # after --profile, a profile name; otherwise the flag or a command
      if [ "$prev" = "--profile" ]; then
        local names; names="$(socksy profiles 2>/dev/null)"
        COMPREPLY=( $(compgen -W "$names" -- "$cur") )
      elif [ "$cword" -eq 2 ]; then
        COMPREPLY=( $(compgen -W "--profile" -- "$cur") $(compgen -c -- "$cur") )
      else
        COMPREPLY=()
      fi ;;
    *) COMPREPLY=() ;;
  esac
}
complete -F _socksy socksy
