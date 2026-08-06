#compdef socksy
# zsh completion for socksy

_socksy() {
  local -a cmds
  cmds=(
    'set:apply a proxy now'
    'on:re-apply the last proxy'
    'off:turn the proxy off'
    'rotate:re-apply the last proxy with a fresh exit IP'
    'run:run one command through the relay only'
    'status:show current state'
    'test:print the current exit IP'
    'watch:live exit-IP loop'
    'watchdog:auto-restart the relay when the exit goes bad'
    'logs:show the relay journal'
    'dns:remote DNS for Firefox (on|off|reset|status)'
    'bypass:manage the GNOME no-proxy list'
    'save:remember a proxy under a name'
    'use:apply a saved proxy (or last)'
    'list:list saved proxies'
    'rm:forget a saved proxy'
  )

  if (( CURRENT == 2 )); then
    _describe 'command' cmds
    return
  fi

  case "${words[2]}" in
    dns)
      _values 'dns action' on off reset status ;;
    watchdog)
      _values 'watchdog action' on off status ;;
    bypass)
      _values 'bypass action' list add rm reset ;;
    status)
      _values 'flag' '--json' ;;
    logs)
      _values 'flag' '-f' '-n' ;;
    use|rm)
      local -a names
      names=(${(f)"$(socksy profiles 2>/dev/null)"})
      _describe 'profile' names ;;
    set)
      _values 'flag' '--type' '--country' '--sticky' '--session' ;;
    run)
      if [[ "${words[CURRENT-1]}" == "--profile" ]]; then
        local -a names
        names=(${(f)"$(socksy profiles 2>/dev/null)"})
        _describe 'profile' names
      elif (( CURRENT == 3 )); then
        _alternative 'flags:flag:((--profile))' 'commands:command:_command_names -e'
      else
        _normal
      fi ;;
  esac
}

_socksy "$@"
