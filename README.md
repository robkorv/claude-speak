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
| `/speak-reply:speak` or `/speak-reply:speak stop` | stop the reply being read now, in every session |
| `/speak-reply:speak off` | mute **this session** |
| `/speak-reply:speak on` | unmute **this session**, even when global is off |
| `/speak-reply:speak global off` | mute all sessions; creates `~/.claude/.speak-reply-off`, so it survives restarts |
| `/speak-reply:speak global on` | unmute all sessions |
| `/speak-reply:speak status` | show this session's and the global setting |

The reply to a `/speak-reply:speak` command is never read out loud.

Which setting wins, first match:

1. the session setting, made with `on` or `off` in that session
2. `CLAUDE_SPEAK_OFF=1` in the environment `claude` was started with (mutes that session from the start)
3. the global setting

So "global off, but on in this one session" works, and so does the reverse.

Session settings are kept in the plugin's data folder (`~/.claude/plugins/data/speak-reply-speak-reply/sessions/`), so they survive a reboot and `claude --resume`. Settings older than 30 days are deleted at session start.

From a terminal, the same control script is in the plugin cache. It has no session there, so only `stop`, `status`, `global on` and `global off` work. An alias for `~/.zshrc` or `~/.bashrc`:

```bash
alias claude-speak='bash "$(ls -d ~/.claude/plugins/cache/speak-reply/speak-reply/*/ | sort -V | tail -n1)scripts/claude-speak"'
```

## Upgrading from 0.1.0

`off` and `on` now switch only the current session. Use `global off` and `global on` for what `off` and `on` did before. An existing global mute stays in place.

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
