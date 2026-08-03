# Claude Code status line

A custom [Claude Code](https://claude.com/claude-code) status line, plus a skill
documenting how it works and how to modify it safely.

Renders:

```
Opus 5 [█░░░░░░░░░] 7% | Current session: 25%, Resets in 3 hr 17 min | Weekly: 37%, Resets in 3 days 5 hr
```

Model name, a context-window meter, and the 5-hour / 7-day rate-limit quotas with
their reset countdowns.

## Contents

| Path | What it is |
| --- | --- |
| `statusline-command.sh` | The status line script. Reads the payload JSON on stdin, writes one line to stdout. |
| `skills/statusline/SKILL.md` | Skill documenting the stdin payload schema, the gotchas, and the rules for editing the script. |
| `skills/statusline/statusline-command.sh` | The skill's bundled copy of the script (kept in sync with the one at the root). |

## Install

```bash
git clone https://github.com/sicsGitHub/claude-code-statusline.git
cd claude-code-statusline

cp statusline-command.sh ~/.claude/
mkdir -p ~/.claude/skills
cp -r skills/statusline ~/.claude/skills/
```

Then register it in `~/.claude/settings.json` — merge rather than hand-edit, so
existing keys survive:

```bash
cd ~/.claude
jq --arg cmd "bash $HOME/.claude/statusline-command.sh" \
   '.statusLine = {type:"command", command:$cmd}' settings.json > settings.tmp \
  && mv settings.tmp settings.json
```

Restart Claude Code afterwards.

## Requirements

- `jq` — the only hard dependency
- `bash` 3.2+ (stock macOS `/bin/bash` is fine)
- A UTF-8 terminal, for `█ ░ —`

GNU `date` is **not** required. `date -d` appears only in the ISO-8601 branch of
`fmt_reset`, which real epoch-seconds payloads never reach.

## Note on the payload schema

`SKILL.md` documents fields that are not in the public Claude Code docs, observed
on version 2.1.220. They can change between releases. If the session or weekly
segment renders `—`, capture a live payload and check the field names before
assuming the script is broken — SKILL.md has the procedure.
