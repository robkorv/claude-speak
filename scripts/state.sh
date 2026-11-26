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
# the default. A bare name is looked up in the voices folder; a value with a
# slash is used as a path. The ".onnx" ending is optional.
voice_path() {
    local v
    case "$1" in
        nl) v="${CLAUDE_PLUGIN_OPTION_VOICE_NL:-nl_NL-pim-medium}" ;;
        *) v="${CLAUDE_PLUGIN_OPTION_VOICE_EN:-en_US-lessac-medium}" ;;
    esac
    v="${v%.onnx}"
    case "$v" in
        "~/"*) v="$HOME/${v#"~/"}" ;;
        */*) ;;
        *) v="$HOME/.local/share/piper-voices/$v" ;;
    esac
    printf '%s.onnx\n' "$v"
}
