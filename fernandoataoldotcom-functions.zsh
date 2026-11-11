# Personal zsh functions, auto-loaded by oh-my-zsh from $ZSH_CUSTOM.

# go-rebase: interactive rebase from the merge-base with the default branch.
go-rebase() {
    default_branch="main"


    # Parse flags
    while [[ $# -gt 0 ]]; do
      key="$1"
      case $key in
        (-b|--default-branch)
          default_branch="$2"
          shift
          shift
          ;;
        (--help)
          echo "Usage: go-rebase [options]"
          echo ""
          echo "Options:"
          echo "  -b, --default-branch VALUE    Set the default branch to rebase from merge-base (default: main)"
          echo "  --help              Show this help message and exit"
          return
          ;;
        (*)
          echo "Unknown option: $key"
          echo "Run 'go-rebase --help' for usage information."
          return
          ;;
      esac
    done

    git rebase -i $(git merge-base $default_branch $(git rev-parse --abbrev-ref HEAD))
}

# claude: a bare `claude` in an interactive shell starts the session with a
# /color that no other live session on this VM is using (least-used, random
# among ties). It reads Claude Code's undocumented session registry
# (~/.claude/sessions/<pid>.json) and the agent-color entries in transcripts.
# If those look different, it warns and picks at random, since a plain random
# pick looks the same as a smart one. Any arguments, and Claude's own shell
# (CLAUDECODE=1), pass straight through.
claude() {
  if [[ $# -gt 0 || ! -o interactive || -n "$CLAUDECODE" ]]; then
    command claude "$@"
    return
  fi
  local color state="${XDG_CACHE_HOME:-$HOME/.cache}/claude-session-color"
  color="$(_claude_pick_color)"
  # Marks this launch for the canary; backdated so a transcript written in the
  # same second still counts as newer.
  mkdir -p "${state:h}" && touch -d '1 minute ago' "$state"
  command claude /color "$color"
}

_claude_pick_color() {
  local -a colors used least
  local -A count
  local f pid sid c min problem
  local state="${XDG_CACHE_HOME:-$HOME/.cache}/claude-session-color"
  colors=(red blue green yellow purple orange pink cyan)
  if ! command -v jq >/dev/null 2>&1; then
    problem="jq is missing"
  elif [[ ! -d ~/.claude/sessions ]]; then
    problem="~/.claude/sessions does not exist"
  else
    for f in ~/.claude/sessions/*.json(N); do
      pid="${f:t:r}"
      [[ "$pid" == <-> ]] && kill -0 "$pid" 2>/dev/null || continue
      sid="$(jq -r '.sessionId // empty' "$f" 2>/dev/null)"
      if [[ -z "$sid" ]]; then
        problem="${f:t} has no sessionId"
        break
      fi
      c="$(_claude_session_color ~/.claude/projects/*/"$sid".jsonl(N))"
      [[ -n "$c" ]] && used+=("$c")
    done
    # Canary: the color set by the last wrapped launch must show up in a
    # transcript written since then.
    if [[ -z "$problem" && -f "$state" ]] \
      && [[ -z "$(_claude_session_color ~/.claude/projects/*/*.jsonl(Ne:'[[ $REPLY -nt $state ]]':))" ]]; then
      problem="the color set at the last launch is not in any transcript since"
    fi
  fi
  if [[ -n "$problem" ]]; then
    used=()
    print -u2 "claude: picking a random session color, because Claude Code's session data looks different ($problem)."
    print -u2 "claude: update _claude_pick_color in fernandoataoldotcom-functions.zsh."
    sleep 2
  fi
  for c in $colors; do count[$c]=0; done
  for c in $used; do (( ${+count[$c]} )) && (( count[$c]++ )); done
  min=${${(on)count}[1]}
  for c in $colors; do (( count[$c] == min )) && least+=("$c"); done
  print -r -- "${least[RANDOM % $#least + 1]}"
}

# Prints the last color set in the given transcripts, or nothing.
_claude_session_color() {
  (( $# )) || return 0
  grep -hF '"type":"agent-color"' "$@" 2>/dev/null \
    | jq -r 'select(.type == "agent-color") | .agentColor // empty' 2>/dev/null | tail -n 1
}
