---
description: Stop spoken replies, or turn them on/off for this session or globally
argument-hint: "[stop|on|off|global on|global off|status]"
allowed-tools: Bash
---
!`SPEAK_SESSION="${CLAUDE_SESSION_ID}" SPEAK_DATA="${CLAUDE_PLUGIN_DATA}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/claude-speak" $ARGUMENTS 2>&1 || true`

Reply with only the output line above, nothing else.
