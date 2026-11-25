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

# Muted with `claude-speak off` (creates this file).
[ -e "$HOME/.claude/.speak-reply-off" ] && exit 0
# Muted for one session by starting it with `CLAUDE_SPEAK_OFF=1 claude`.
[ -n "$CLAUDE_SPEAK_OFF" ] && exit 0

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

# The first non-empty line, plus the last "Next:" line (the ADHD plugin's
# next action) when the reply has one and it is not the first line itself.
first=$(printf '%s\n' "$msg" | grep -m1 -v '^[[:space:]]*$' | clean)
next=$(printf '%s\n' "$msg" | grep -E '^[[:space:]>*_]*Next[*_]*:' | tail -n1 | clean)

line="$first"
if [ -n "$next" ] && [ "$next" != "$first" ]; then
    line=$(printf '%s\n%s' "$first" "$next")
fi

[ -z "$(printf '%s' "$line" | tr -d '[:space:]')" ] && exit 0

# Guess Dutch or English from common words in the whole reply (code blocks
# skipped): Dutch wins only when it has more hits than English.
lang=$(printf '%s\n' "$msg" | awk '
    /^[[:space:]]*```/ { code = !code; next }
    code { next }
    {
        n = split(tolower($0), w, /[^a-zà-ÿ]+/)
        for (i = 1; i <= n; i++) {
            if (w[i] ~ /^(de|het|een|niet|van|dat|dit|deze|je|jij|zijn|wordt|worden|ook|nog|wel|maar|voor|met|naar|bij|moet|kan|heb|hebt|wat|er|om|te|uit|nu|en|ik|zo|als|dan)$/) nl++
            if (w[i] ~ /^(the|a|an|not|of|that|this|these|you|is|are|be|will|also|still|but|for|with|to|at|must|can|have|what|there|it|and|on|in|so|if|then)$/) en++
        }
    }
    END { print (nl > en ? "nl" : "en") }')

voice="$voice_en"
[ "$lang" = nl ] && [ -f "$voice_nl" ] && voice="$voice_nl"
rate=$(jq -r '.audio.sample_rate // 22050' "$voice.json" 2>/dev/null)
[ -n "$rate" ] || rate=22050

# Stop whatever is still being read, in any session, so two voices never overlap.
mkdir -p "$piddir"
for f in "$piddir"/*.pid; do
    [ -f "$f" ] && kill -- -"$(cat "$f")" 2>/dev/null
    rm -f "$f"
done

# Fall back to spd-say when Piper or the voice is missing.
if [ ! -x "$piper" ] || [ ! -f "$voice" ]; then
    spd-say -C 2>/dev/null
    spd-say -l "$lang" -- "${line//$'\n'/ }" 2>/dev/null
    exit 0
fi

# Run detached in its own process group so the turn ends right away.
setsid bash -c '
    echo $$ > "$2"
    printf "%s\n" "$1" \
        | "$4" -m "$3" --output-raw 2>/dev/null \
        | aplay -q -r "$5" -f S16_LE -t raw -c 1 2>/dev/null
    rm -f "$2"
' _ "$line" "$pidfile" "$voice" "$piper" "$rate" </dev/null >/dev/null 2>&1 &

exit 0
