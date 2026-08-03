#!/bin/bash
# Claude Code status line.
#
# Renders:
#   Opus 5 [█░░░░░░░░░] 7% | Current session: 25%, Resets in 3 hr 17 min | Weekly: 37%, Resets in 3 days 5 hr
#
# Fields come from the JSON payload Claude Code writes to stdin:
#   .model.display_name
#   .context_window.used_percentage  (fallback: total_input_tokens / context_window_size)
#   .rate_limits.five_hour  = { used_percentage: 0-100, resets_at: <epoch seconds> }
#   .rate_limits.seven_day  = same shape
# rate_limits is only present once the session has seen rate-limit headers, so
# every segment degrades gracefully when its data is missing.

input=$(cat)

IFS=$'\t' read -r model ctx_pct sess_pct sess_reset week_pct week_reset < <(
    printf '%s' "$input" | jq -r '
        # A rate-limit window reports used_percentage (0-100). Older/internal
        # shapes use utilization (0..1), so accept that as a fallback.
        def pct($o): if $o == null then "-"
                     elif ($o.used_percentage // null) != null then $o.used_percentage
                     elif ($o.utilization // null) != null then $o.utilization * 100
                     else "-" end;

        (.model.display_name // "Claude") as $model
        | (.context_window.used_percentage //
           (if (.context_window.total_input_tokens // null) != null
               and (.context_window.context_window_size // 0) > 0
            then .context_window.total_input_tokens / .context_window.context_window_size * 100
            else null end)) as $ctx
        | .rate_limits as $rl
        | [ $model,
            (if $ctx == null then "-" else $ctx end),
            pct($rl.five_hour // null),
            ($rl.five_hour.resets_at // "-"),
            pct($rl.seven_day // null),
            ($rl.seven_day.resets_at // "-")
          ] | @tsv
    ' 2>/dev/null
)

# Fall back to a bare model name if jq failed or produced nothing.
[ -z "$model" ] && model="Claude"

esc=$'\033'
dim="${esc}[02m"; bold="${esc}[01m"; off="${esc}[00m"

# "Resets in ..." from an epoch-second (or ISO-8601) timestamp.
fmt_reset() {
    local at=$1 now secs d h m
    case "$at" in
        ''|'-'|null) return 1 ;;
        *[!0-9]*) at=$(date -d "$at" +%s 2>/dev/null) || return 1 ;;
    esac
    now=$(date +%s)
    secs=$(( at - now ))
    [ "$secs" -le 0 ] && { printf 'Resets now'; return 0; }
    d=$(( secs / 86400 )); h=$(( secs % 86400 / 3600 )); m=$(( secs % 3600 / 60 ))
    if   [ "$d" -gt 0 ]; then printf 'Resets in %d %s %d hr' "$d" "$([ "$d" -eq 1 ] && echo day || echo days)" "$h"
    elif [ "$h" -gt 0 ]; then printf 'Resets in %d hr %d min' "$h" "$m"
    else                      printf 'Resets in %d min' "$m"
    fi
}

# Round a float percentage to an integer; fails on "-" / empty.
as_pct() {
    case "$1" in ''|'-'|null) return 1 ;; esac
    printf '%.0f' "$1" 2>/dev/null
}

# 10-cell meter, colored by how full it is.
bar() {
    local pct=$1 filled i out color
    filled=$(( (pct + 5) / 10 ))
    [ "$filled" -gt 10 ] && filled=10
    [ "$filled" -lt 0 ] && filled=0
    if   [ "$pct" -ge 90 ]; then color="${esc}[01;31m"
    elif [ "$pct" -ge 70 ]; then color="${esc}[01;33m"
    else                        color="${esc}[01;32m"
    fi
    out=""
    for ((i = 0; i < 10; i++)); do
        if [ "$i" -lt "$filled" ]; then out+="█"; else out+="░"; fi
    done
    printf '%s[%s%s%s]%s' "$dim" "$color" "$out" "$dim" "$off"
}

line="${bold}${model}${off}"

if p=$(as_pct "$ctx_pct"); then
    line+=" $(bar "$p") ${p}%"
fi

# Both rate-limit segments always render. Their data only lands once the
# session has seen rate-limit headers from the API, so until then the labels
# show with an em dash in place of the missing number.
segment() {
    local label=$1 raw_pct=$2 reset=$3 p r
    p=$(as_pct "$raw_pct") || p="—"
    r=$(fmt_reset "$reset") || r="Resets in —"
    printf '%s: %s%s, %s' "$label" "$p" "$([ "$p" = "—" ] || printf %%)" "$r"
}

line+=" ${dim}|${off} $(segment "Current session" "$sess_pct" "$sess_reset")"
line+=" ${dim}|${off} $(segment "Weekly" "$week_pct" "$week_reset")"

printf '%s\n' "$line"
