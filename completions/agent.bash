# bash completion for agent (agent-sync)
_agent_sync() {
  local cur prev commands
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"
  commands="sync compact status diff targets doctor migrate gather apply link revert pack mcp skills hooks help version"
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
    pack)
      COMPREPLY=($(compgen -W "add list update remove" -- "$cur"))
      return
      ;;
    mcp)
      COMPREPLY=($(compgen -W "add list remove sync snippet" -- "$cur"))
      return
      ;;
    skills)
      COMPREPLY=($(compgen -W "sync" -- "$cur"))
      return
      ;;
    hooks)
      COMPREPLY=($(compgen -W "claude codex gemini opencode launchd" -- "$cur"))
      return
      ;;
  esac
  case "$cur" in
    --*)
      COMPREPLY=($(compgen -W "--synthesizer --rewrite --no-compact --dry-run --only --skip --budget --jobs --force --keep-all --claude-model --claude-effort --codex-model --codex-effort --import --url --env --header --color --no-color" -- "$cur"))
      return
      ;;
  esac
  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "$commands" -- "$cur"))
  fi
}
complete -F _agent_sync agent
