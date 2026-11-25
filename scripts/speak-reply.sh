#!/usr/bin/env bash
# Stop hook: speak the first non-empty line of Claude's last reply, and its
# last "Next:" line, with Piper.
# Reads the hook JSON on stdin; never blocks or fails the turn.

# Absolute path: /usr/bin/piper on Ubuntu is the libratbag mouse tool, not Piper TTS.
piper="$HOME/.local/bin/piper"
voices="$HOME/.local/share/piper-voices"
voice_en="$voices/en_US-lessac-medium.onnx"
voice_nl="$voices/nl_NL-pim-medium.onnx"
# One pid file per session, so `claude-speak stop --hook` (UserPromptSubmit)
# only stops speech started by its own session.
piddir="${XDG_RUNTIME_DIR:-/tmp}/claude-speak-reply"

# shellcheck source=state.sh
. "$(dirname "$0")/state.sh"

# Make one line speakable: drop URLs (a markdown link keeps its text) and
# markdown symbols, squeeze spaces.
clean() {
    sed -E \
        -e 's/\[([^]]*)\]\([^)]*\)/\1/g' \
        -e 's#<(https?|ftp)://[^>]*>##g' \
        -e 's#(https?|ftp)://[^[:space:])]*##g' \
        -e 's#www\.[^[:space:])]*##g' \
        -e 's/\(\s*\)//g' \
        | tr -d '*`#>_' \
        | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

input=$(cat)
msg=$(printf '%s' "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9-')
pidfile="$piddir/${session:-unknown}.pid"

# The prompt was a /speak command (flagged by the UserPromptSubmit hook): stay quiet.
skipfile="$piddir/${session:-unknown}.skip"
if [ -e "$skipfile" ]; then
    rm -f "$skipfile"
    exit 0
fi

# Muted for this session, by `CLAUDE_SPEAK_OFF=1`, or globally (see state.sh).
[ "$(effective_state "$session" | cut -d' ' -f1)" = off ] && exit 0

# The first non-empty line, plus the last "Next:" line (the ADHD plugin's
# next action) when the reply has one and it is not the first line itself.
first=$(printf '%s\n' "$msg" | grep -m1 -v '^[[:space:]]*$' | clean)
next=$(printf '%s\n' "$msg" | grep -E '^[[:space:]>*_]*Next[*_]*:' | tail -n1 | clean)

line="$first"
if [ -n "$next" ] && [ "$next" != "$first" ]; then
    line=$(printf '%s\n%s' "$first" "$next")
fi

[ -z "$(printf '%s' "$line" | tr -d '[:space:]')" ] && exit 0

# Guess Dutch or English from common words (code blocks skipped): Dutch wins
# only when it has more hits than English; a tie prints the fallback ($1).
guess_lang() {
    awk -v fallback="$1" '
    /^[[:space:]]*```/ { code = !code; next }
    code { next }
    {
        n = split(tolower($0), w, /[^a-zà-ÿ]+/)
        for (i = 1; i <= n; i++) {
            if (w[i] ~ /^(de|het|een|niet|van|dat|dit|deze|je|jij|zijn|wordt|worden|ook|nog|wel|maar|voor|met|naar|bij|moet|kan|heb|hebt|wat|er|om|te|uit|nu|en|ik|zo|als|dan)$/) nl++
            if (w[i] ~ /^(the|a|an|not|of|that|this|these|you|is|are|be|will|also|still|but|for|with|to|at|must|can|have|what|there|it|and|on|in|so|if|then)$/) en++
        }
    }
    END { print (nl > en ? "nl" : (en > nl ? "en" : fallback)) }'
}

# Each spoken line gets its own language, so an English line before a quoted
# Dutch text is still read in English. A line that ties falls back to the
# language of the whole reply.
reply_lang=$(printf '%s\n' "$msg" | guess_lang en)

# Arguments for the player: voice, sample rate, language, text, per line.
segments=()
use_piper=1
[ -x "$piper" ] || use_piper=0
while IFS= read -r l; do
    [ -z "$(printf '%s' "$l" | tr -d '[:space:]')" ] && continue
    lang=$(printf '%s\n' "$l" | guess_lang "$reply_lang")
    voice="$voice_en"
    [ "$lang" = nl ] && [ -f "$voice_nl" ] && voice="$voice_nl"
    [ -f "$voice" ] || use_piper=0
    rate=$(jq -r '.audio.sample_rate // 22050' "$voice.json" 2>/dev/null)
    [ -n "$rate" ] || rate=22050
    segments+=("$voice" "$rate" "$lang" "$l")
done <<< "$line"

# Stop whatever is still being read, in any session, so two voices never overlap.
mkdir -p "$piddir"
for f in "$piddir"/*.pid; do
    [ -f "$f" ] && kill -- -"$(cat "$f")" 2>/dev/null
    rm -f "$f"
done

# Fall back to spd-say when Piper or a voice is missing.
if [ "$use_piper" = 0 ]; then
    spd-say -C 2>/dev/null
    set -- "${segments[@]}"
    while [ $# -ge 4 ]; do
        spd-say -l "$3" -- "$4" 2>/dev/null
        shift 4
    done
    exit 0
fi

# Run detached in its own process group so the turn ends right away.
setsid bash -c '
    pidfile=$1 piper=$2
    shift 2
    echo $$ > "$pidfile"
    while [ $# -ge 4 ]; do
        printf "%s\n" "$4" \
            | "$piper" -m "$1" --output-raw 2>/dev/null \
            | aplay -q -r "$2" -f S16_LE -t raw -c 1 2>/dev/null
        shift 4
    done
    rm -f "$pidfile"
' _ "$pidfile" "$piper" "${segments[@]}" </dev/null >/dev/null 2>&1 &

exit 0
