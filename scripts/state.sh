# Shared by speak-reply.sh and claude-speak (sourced, not run).
# Works out whether spoken replies are on for a session.
#
# Order, first match wins:
#   1. the session setting, made with `/speak-reply:speak on|off` in that session
#   2. CLAUDE_SPEAK_OFF=1 in the environment `claude` was started with
#   3. the global setting (`/speak-reply:speak global on|off`)

# Global mute flag (kept at this path since 0.1.0).
muteflag="$HOME/.claude/.speak-reply-off"
# Plugin data dir: passed in by the hook or command; fallback for a terminal alias.
datadir="${SPEAK_DATA:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/speak-reply-speak-reply}}"
sessiondir="$datadir/sessions"

# Keep only safe characters, so a session id can be used as a file name.
safe_id() { printf '%s' "$1" | tr -cd 'A-Za-z0-9-'; }

global_state() { [ -e "$muteflag" ] && echo off || echo on; }

# Prints "on" or "off" when the session has its own setting, nothing otherwise.
session_state() {
    local id; id=$(safe_id "$1")
    [ -n "$id" ] && [ -f "$sessiondir/$id" ] && head -n1 "$sessiondir/$id"
}

# Prints "on" or "off", plus why, as "<state> <source>".
effective_state() {
    local s; s=$(session_state "$1")
    if [ -n "$s" ]; then echo "$s session"
    elif [ -n "$CLAUDE_SPEAK_OFF" ]; then echo "off env"
    else echo "$(global_state) global"
    fi
}

# Voice for a language (en|nl): the plugin option (voice_en / voice_nl), else
# the default. An absolute path (or one starting with ~/ or $HOME/) is used as
# is; anything else, a bare name or a relative path, is looked up in the voices
# folder. The ".onnx" ending is optional, in any case. Surrounding whitespace
# is ignored.
voice_path() {
    local v
    case "$1" in
        nl) v="${CLAUDE_PLUGIN_OPTION_VOICE_NL:-}" ;;
        *) v="${CLAUDE_PLUGIN_OPTION_VOICE_EN:-}" ;;
    esac
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    if [ -z "$v" ]; then
        case "$1" in nl) v=nl_NL-pim-medium ;; *) v=en_US-lessac-medium ;; esac
    fi
    case "$v" in *.[oO][nN][nN][xX]) v="${v%.*}" ;; esac
    # shellcheck disable=SC2016  # a literal $HOME typed into the option
    case "$v" in
        "~/"*) v="$HOME/${v#"~/"}" ;;
        '$HOME/'*) v="$HOME/${v#'$HOME/'}" ;;
        '${HOME}/'*) v="$HOME/${v#'${HOME}/'}" ;;
        /*) ;;
        *) v="$HOME/.local/share/piper-voices/$v" ;;
    esac
    printf '%s.onnx\n' "$v"
}

# Pid files of the replies being read or waiting (<session>.<time>.pid), the
# spd-say markers (<session>.spd) and skip flags. One lock guards them.
piddir="${XDG_RUNTIME_DIR:-/tmp}/claude-speak-reply"

# Take the pid file lock on fd 9, held until the script exits. Children that
# outlive the script must close fd 9 (9>&-).
lock_piddir() {
    mkdir -p "$piddir" && exec 9>"$piddir/.lock" && flock -w 5 9 2>/dev/null
}

# True when process $2 is the reply that wrote pid file $1: the pid file is in
# its command line, so a pid reused by another program doesn't count.
is_reply() { [ -n "$2" ] && grep -qzxF -- "$1" "/proc/$2/cmdline" 2>/dev/null; }

# Stop one reply by its pid file and remove the file.
stop_reply() {
    [ -f "$1" ] || return 0
    local pid; pid=$(cat "$1" 2>/dev/null)
    is_reply "$1" "$pid" && kill -- -"$pid" 2>/dev/null
    rm -f "$1"
}
