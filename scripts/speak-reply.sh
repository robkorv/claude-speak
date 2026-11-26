#!/usr/bin/env bash
# Stop hook: speak the first non-empty line of Claude's last reply, and its
# last "Next:" line, with Piper.
# Reads the hook JSON on stdin; never blocks or fails the turn.

# Absolute path: /usr/bin/piper on Ubuntu is the libratbag mouse tool, not Piper TTS.
piper="$HOME/.local/bin/piper"
# shellcheck source=state.sh
. "$(dirname "$0")/state.sh"
voice_en=$(voice_path en)
voice_nl=$(voice_path nl)

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
# stop_hook_active goes first: it is never empty, so read keeps the fields apart.
read -r stop_active session < <(printf '%s' "$input" \
    | jq -r '[.stop_hook_active // false, .session_id // ""] | @tsv' 2>/dev/null)
session=$(safe_id "$session")

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
    [ "$lang" = nl ] && voice="$voice_nl"
    # A missing voice sends the whole reply to spd-say, which reads each line
    # in its own language (rather than Dutch in the English Piper voice).
    [ -f "$voice" ] || use_piper=0
    rate=$(jq -r '.audio.sample_rate // 22050' "$voice.json" 2>/dev/null)
    [ -n "$rate" ] || rate=22050
    segments+=("$voice" "$rate" "$lang" "$l")
done <<< "$line"

id="${session:-unknown}"

# One pid file per reply, named <session>.<time>.pid, so `claude-speak stop
# --hook` (UserPromptSubmit and SessionEnd) only stops its own session's speech.
# The lock (see state.sh) makes picking the reply to wait for, writing this
# reply's pid file and marker, a finished reply's cleanup and `claude-speak
# stop` happen one at a time, so no one reads a half-written pid file or misses
# a new one.
lock_piddir

# This session's own speech is not cut off: a new reply that comes without a
# prompt (a background agent's result) waits for it, in order. A new prompt
# already stopped it (UserPromptSubmit hook), so a normal reply starts at once.
# Cut it off anyway when Claude goes on because a Stop hook blocked (this reply
# replaces the one before it), or when there is no session id to tell sessions
# apart. $own is the session whose speech is kept.
own="$id"
{ [ -z "$session" ] || [ "$stop_active" = true ]; } && own=""

# Stop what other sessions are still reading (and this session's, see above),
# so two voices never overlap. Killing an spd-say client does not stop the line
# it already sent, so cancel speech-dispatcher too when a stopped reply went
# there.
for f in "$piddir"/*.pid; do
    case "${f##*/}" in "$own".*) continue ;; esac
    stop_reply "$f"
done
cancel_spd=0
for f in "$piddir"/*.spd; do
    [ -e "$f" ] || continue
    case "${f##*/}" in "$own".*) continue ;; esac
    cancel_spd=1
    rm -f "$f"
done
[ "$cancel_spd" = 1 ] && spd-say -C 2>/dev/null

# The newest pid file of this session is the reply to wait for; the names have
# the same length and glob in time order.
prevfile=""
if [ -n "$own" ]; then
    prevs=("$piddir/$id".*.pid)
    [ -e "${prevs[-1]}" ] && prevfile="${prevs[-1]}"
fi
pidfile="$piddir/$id.${EPOCHREALTIME//[!0-9]/}.pid"
# Exists before the child starts, so the child doesn't take it for a stop.
: > "$pidfile"

# Fall back to spd-say (an empty $piper) when Piper or a voice is missing.
# spd-say has no process to kill, so a marker tells `claude-speak stop --hook`
# to cancel it. spd-say reads one line at a time (-w): a new spd-say line cuts
# off the one being read.
if [ "$use_piper" = 0 ]; then
    piper=""
    touch "$piddir/$id.spd"
fi

# Run detached in its own process group so the turn ends right away.
# The pid file is written here, not by the child, so a stop that comes right
# after the reply finds it; a missing pid file tells the child to stop. A stop
# kills the whole group, so the wait below ends with it.
# ($! is the group: setsid does not fork, as a background job leads no group.)
export -f is_reply
setsid bash -c '
    pidfile=$1 prevfile=$2 piper=$3
    shift 3
    # Wait for the reply before this one to finish (or be stopped).
    if [ -n "$prevfile" ]; then
        prev=$(cat "$prevfile" 2>/dev/null)
        is_reply "$prevfile" "$prev" && tail --pid="$prev" -f /dev/null
    fi
    while [ $# -ge 4 ] && [ -e "$pidfile" ]; do
        if [ -z "$piper" ]; then
            spd-say -w -l "$3" -- "$4" 2>/dev/null
        else
            printf "%s\n" "$4" \
                | "$piper" -m "$1" --output-raw 2>/dev/null \
                | aplay -q -r "$2" -f S16_LE -t raw -c 1 2>/dev/null
        fi
        shift 4
    done
    # The last reply of the session removes the spd-say marker, so a later
    # stop leaves other speech-dispatcher programs (a screen reader) alone.
    base=${pidfile%.*.pid}
    {
        flock -w 5 9 2>/dev/null
        rm -f "$pidfile"
        compgen -G "$base.*.pid" >/dev/null || rm -f "$base.spd"
    } 9>"${pidfile%/*}/.lock"
' _ "$pidfile" "$prevfile" "$piper" "${segments[@]}" \
    </dev/null >/dev/null 2>&1 9>&- &
echo $! > "$pidfile"

exit 0
