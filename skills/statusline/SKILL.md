---
name: statusline
description: Build, edit, or debug the Claude Code status line — the custom line rendered above the prompt via settings.json `statusLine`. Use whenever the user asks to change what the status line shows (model name, context-window meter, session/weekly rate-limit usage, reset countdowns, cwd, cost), asks why a segment is blank or missing, or wants the status line restored on a new machine. Documents the exact stdin JSON payload Claude Code provides, including the `rate_limits` fields that are absent from the public docs.
---

# Claude Code status line

The status line script lives at `~/.claude/statusline-command.sh`, wired up in
`~/.claude/settings.json`:

```json
"statusLine": { "type": "command", "command": "bash $HOME/.claude/statusline-command.sh" }
```

One file ships beside this one: `statusline-command.sh`, a working copy of the
current script. Copy it into place to restore the line on a new machine.

No captured payload is bundled — one was, but it carried live session usage and
cost figures, so it isn't kept on disk. Capture a fresh one when you need it
(see below); it takes seconds and is always more trustworthy than a stale fixture.

Current format:

```
Opus 5 [█░░░░░░░░░] 7% | Current session: 25%, Resets in 3 hr 17 min | Weekly: 37%, Resets in 3 days 5 hr
```

## The stdin payload

Claude Code pipes one JSON object to the command on every render. Fields the
script uses:

| Path | Meaning |
| --- | --- |
| `.model.display_name` | `"Opus 5"`, `"Sonnet 5"`, … |
| `.context_window.used_percentage` | 0–100; absent before the first message |
| `.context_window.total_input_tokens` / `.context_window.context_window_size` | fallback for computing the above |
| `.rate_limits.five_hour` | `{ used_percentage: 0-100, resets_at: <epoch seconds> }` — the "current session" quota |
| `.rate_limits.seven_day` | same shape — the weekly quota |
| `.workspace.current_dir` / `.cwd` | working directory |
| `.cost.total_cost_usd` | session spend |
| `.version`, `.output_style.name`, `.session_id`, `.transcript_path` | misc |

Also present depending on state: `.exceeds_200k_tokens`, `.fast_mode`,
`.effort.level`, `.thinking.enabled`, `.vim.mode`, `.agent.name`,
`.remote.session_id`, `.pr.{number,url,review_state,kind}`,
`.worktree.{name,path,branch,original_cwd,original_branch}`.

### rate_limits gotchas

- **The field is `used_percentage`, already 0-100.** Do **not** multiply by 100.
- **`resets_at` is epoch *seconds*, not milliseconds and not ISO-8601.**
- **The whole `rate_limits` key is conditional.** Claude Code only emits it once
  the process has seen `anthropic-ratelimit-unified-*` response headers, gated on
  `five_hour || seven_day`. In a fresh session, before the first API response
  lands, the key is missing entirely.
- Other keys that may appear alongside: `seven_day_opus`, `seven_day_sonnet`,
  `seven_day_overage_included`, `overage`, `extra_usage`.

### Verify the payload against a live capture, not the binary

An earlier version of this skill claimed the field was `utilization` (0..1),
derived by reverse-engineering the CLI binary. **That was wrong** and the segment
silently rendered as `—` in production while every synthetic test passed, because
the tests were built from the same bad assumption. The `utilization` shape is
real but internal — it's how Claude Code parses the HTTP response headers, not
what it puts in the status line payload.

So: **when a segment shows nothing, capture the real payload first.** Add a temp
dump at the top of the script, let one render land, then inspect:

```bash
# in statusline-command.sh, right after `input=$(cat)`:
printf '%s\n' "$input" > /tmp/statusline-payload.json
```

```bash
# in another shell, once a render has happened:
jq 'keys' /tmp/statusline-payload.json
jq '.rate_limits, .context_window' /tmp/statusline-payload.json
bash ~/.claude/statusline-command.sh < /tmp/statusline-payload.json  # replay
```

Remove the dump afterwards. Keeping a captured payload around to replay through
the script is the single highest-value test case — better than any hand-written
fixture.

The binary is still a fallback for questions a capture can't answer (what fields
*could* appear). Grep it by byte offset, never with a context pattern:

```bash
F=$(ls -d ~/.local/share/claude/versions/* | tail -1)
grep -a -b -o 'resets_at' "$F" | head        # offsets
dd if=$F bs=1 skip=$((OFFSET-900)) count=1800 2>/dev/null | tr -d '\0'
```

A `grep -o -E '.{400}pattern.{500}'` over the (very large) binary backtracks for
minutes and will time out. Byte offset then `dd` returns instantly. Treat
anything found this way as a hypothesis until a live capture confirms it.

## Rules for editing this script

1. **Every segment must degrade gracefully.** The payload is routinely partial:
   `{}` on startup, no `rate_limits` early, `resets_at: null`. The script must
   exit 0 and print something sensible for all of them — never a bare error or
   an empty line.
2. **Unknown values render as an em dash (`—`), and the label still renders.**
   `Current session: —, Resets in —` is preferred over a segment that silently
   disappears, because a vanishing segment reads as breakage.
3. **Parse the JSON in a single `jq` call** emitting `@tsv`, read with
   `IFS=$'\t' read -r`. The status line re-renders constantly; don't spawn six
   `jq` processes. Tab-splitting (not space-splitting) is also what keeps
   `"Opus 5"` and paths containing spaces from being torn into two fields.
4. **Colors via raw `printf` escapes**, no `\[ \]` readline wrappers — this is
   not a PS1, and those brackets show up literally.
5. **The `%` sign is conditional.** `segment()` appends it via
   `$([ "$p" = "—" ] || printf %%)` so a known value reads `25%` while an
   unknown one reads `—`, not `—%`. It looks like a redundant subshell; it
   isn't. Same reasoning for `as_pct` *failing* (rather than returning 0) on
   missing input — that's what lets `0%` and `—` stay distinguishable.
6. **Always test before declaring done.** If a live payload was captured for the
   task at hand, replay that first — it is the only test that can catch a wrong
   field name. Then the degenerate cases:

```bash
S=~/.claude/statusline-command.sh

bash "$S" < /tmp/statusline-payload.json      # if one was captured

now=$(date +%s)
jq -nc --argjson a $((now+17580)) --argjson b $((now+280800)) '{
  model:{display_name:"Opus 5"},
  context_window:{used_percentage:3.4},
  rate_limits:{five_hour:{used_percentage:1,resets_at:$a},
               seven_day:{used_percentage:35,resets_at:$b}}}' | bash "$S"

echo '{}'       | bash "$S"   # must not error
echo 'not json' | bash "$S"   # must not error
```

Cover at minimum: missing `rate_limits`, one quota present and the other absent,
`used_percentage: 0` (must render `0%`, not `—`), a sub-1% value (must not get
scaled), `resets_at: null`, `{}`, and non-JSON.
