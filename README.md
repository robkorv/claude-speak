# claude-speak

A Claude Code plugin (named `speak-reply`) that reads the first line of each Claude reply out loud, plus its last line starting with `Next:` (the next action from the [i-have-adhd](https://github.com/ayghri/i-have-adhd) plugin). It uses [Piper](https://github.com/OHF-Voice/piper1-gpl), an offline neural voice, and falls back to `spd-say` (speech-dispatcher, preinstalled on Ubuntu) when Piper is missing.

- URLs are skipped; a markdown link keeps its link text.
- Each reply is read in Dutch or English: the hook counts common Dutch and English words in the reply (code blocks skipped) and uses the Dutch voice only when Dutch words win.
- Sending your next prompt stops the speech of that session. A new reply in any session cuts off speech from the other sessions, so two voices never overlap.

Built and tested on Ubuntu.

## Install

1. Install the tools:

   ```bash
   sudo apt install pipx jq
   pipx install piper-tts
   ```

2. Download the English and Dutch voices (63 MB each):

   ```bash
   mkdir -p ~/.local/share/piper-voices
   ~/.local/share/pipx/venvs/piper-tts/bin/python -m piper.download_voices --data-dir ~/.local/share/piper-voices en_US-lessac-medium nl_NL-pim-medium
   ```

3. Check the voice works:

   ```bash
   echo "Hello" | ~/.local/bin/piper -m ~/.local/share/piper-voices/en_US-lessac-medium.onnx --output-raw | aplay -q -r 22050 -f S16_LE -t raw -c 1
   ```

4. Install the plugin, inside Claude Code:

   ```
   /plugin marketplace add robkorv/claude-speak
   /plugin install speak-reply@speak-reply
   ```

5. Restart `claude`. The first line of the next reply is spoken. When Piper or a voice is missing, a warning shows at session start.

The plugin calls Piper as `~/.local/bin/piper` on purpose: `/usr/bin/piper` on Ubuntu is the libratbag mouse-configuration app (package `piper`), not Piper TTS.

## Control it

Inside Claude Code:

| Command | What it does |
|---|---|
| `/speak` or `/speak stop` | stop the reply being read now, in every session |
| `/speak off` | mute until turned back on; creates `~/.claude/.speak-reply-off`, so it survives restarts |
| `/speak on` | unmute |
| `/speak status` | show whether it is on or off |

The reply to a `/speak` command is never read out loud.

Mute one session only: start it with `CLAUDE_SPEAK_OFF=1 claude`. Hooks inherit the environment `claude` was started with, so other sessions keep talking.

From a terminal, the same control script is in the plugin cache. An alias for `~/.bashrc`:

```bash
alias claude-speak='bash "$(ls -d ~/.claude/plugins/cache/speak-reply/speak-reply/*/ | sort -V | tail -n1)scripts/claude-speak"'
```

## Moving from the hand-made hooks

If you set this up before by hand (`~/.claude/hooks/speak-reply.sh` and `~/.local/bin/claude-speak`), remove the old Stop and UserPromptSubmit hooks, or every reply is spoken twice:

```bash
jq 'del(.hooks.Stop, .hooks.UserPromptSubmit) | if .hooks == {} then del(.hooks) else . end' ~/.claude/settings.json > ~/.claude/settings.json.tmp && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
rm ~/.claude/hooks/speak-reply.sh ~/.local/bin/claude-speak
```

This removes all Stop and UserPromptSubmit hooks in that file, so check `jq .hooks ~/.claude/settings.json` first if you have others.

## Remove

```
/plugin uninstall speak-reply@speak-reply
```

## License

MIT
