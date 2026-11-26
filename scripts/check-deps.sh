#!/usr/bin/env bash
# SessionStart hook: clean up old session settings, and warn when Piper or a
# voice is missing (speech then falls back to spd-say). Prints nothing when
# everything is in place.
piper="$HOME/.local/bin/piper"
# Delete session on/off settings older than 30 days (see state.sh).
# shellcheck source=state.sh
. "$(dirname "$0")/state.sh"
[ -d "$sessiondir" ] && find "$sessiondir" -type f -mtime +30 -delete 2>/dev/null

missing=()
[ -x "$piper" ] || missing+=("Piper (~/.local/bin/piper)")
for lang in en nl; do
    v=$(voice_path "$lang")
    [ -f "$v" ] || missing+=("voice ${v/#$HOME/\~}")
done
command -v jq >/dev/null || missing+=("jq")
[ ${#missing[@]} -eq 0 ] && exit 0
msg="speak-reply: missing $(IFS=,; echo "${missing[*]}" | sed 's/,/, /g'). See the README install steps; until then replies use spd-say."
jq -n --arg m "$msg" '{systemMessage: $m}' 2>/dev/null || echo "$msg" >&2
exit 0
