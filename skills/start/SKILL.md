---
name: start
description: Start the Attention Buddy floating icon again, for example after choosing Quit in its menu.
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/plugin-start.sh --manual)
---

!`${CLAUDE_PLUGIN_ROOT}/scripts/plugin-start.sh --manual`

The line above is the result of starting the Attention Buddy icon. Tell the user in one short
sentence what happened, based on that line. If the line above still shows the command instead of
its result, run that exact command with the Bash tool first, then tell the user.
