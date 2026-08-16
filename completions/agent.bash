# bash completion for agent (agent-sync)
_agent_sync() {
  local cur prev commands
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"
  commands="sync status diff targets doctor migrate gather apply link revert help version"
  case "$prev" in
    migrate)
      COMPREPLY=($(compgen -W "claude codex cursor continue windsurf goose" -- "$cur"))
      return
      ;;
    --synthesizer)
      COMPREPLY=($(compgen -W "auto claude codex deterministic" -- "$cur"))
      return
      ;;
    gather | apply | link)
      COMPREPLY=($(compgen -d -- "$cur"))
      return
      ;;
  esac
  case "$cur" in
    --*)
      COMPREPLY=($(compgen -W "--synthesizer --dry-run" -- "$cur"))
      return
      ;;
  esac
  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "$commands" -- "$cur"))
  fi
}
complete -F _agent_sync agent
