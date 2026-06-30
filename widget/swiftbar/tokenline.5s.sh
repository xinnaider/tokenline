#!/usr/bin/env bash
# <xbar.title>tokenline</xbar.title>
# <xbar.desc>Claude usage across multiple accounts</xbar.desc>
# <xbar.dependencies>jq</xbar.dependencies>
#
# SwiftBar/xbar plugin: reads tokenline widget snapshots (written by tokenline.sh
# when TOKENLINE_WIDGET=1) and shows per-account usage in the macOS menu bar.
# The menu bar shows the most-constrained account's 5h %; the dropdown lists one
# dense line per account. This is the throwaway prototype reader — same store and
# schema the native MenuBarExtra app consumes.
set -uo pipefail

# Pin C locale so awk/printf emit "3.8M" not "3,8M" under comma-decimal locales
# (e.g. pt_BR) — same reason tokenline.sh exports LC_ALL=C.
export LC_ALL=C

DIR="${TOKENLINE_WIDGET_DIR:-$HOME/Library/Application Support/tokenline/widget}"

command -v jq >/dev/null 2>&1 || { echo "tokenline ⚠"; echo "---"; echo "jq not found"; exit 0; }

shopt -s nullglob
files=("$DIR"/*.json)
if [ "${#files[@]}" -eq 0 ]; then
  echo "tokenline –"; echo "---"
  echo "No accounts yet (run a Claude session with TOKENLINE_WIDGET=1)"
  exit 0
fi

now="$(date +%s)"

color_for() { # $1 = integer pct -> SwiftBar color name
  if   [ "${1:-0}" -ge 86 ] 2>/dev/null; then echo red
  elif [ "${1:-0}" -ge 50 ] 2>/dev/null; then echo orange
  else echo green; fi
}

fmt_tokens() { # $1 = integer tokens -> 1.2M / 420k / 12
  awk -v v="${1:-0}" 'BEGIN {
    if (v >= 1000000) printf "%.1fM", v/1000000
    else if (v >= 1000) printf "%.0fk", v/1000
    else printf "%d", v }'
}

worst=-1
lines=()
for f in "${files[@]}"; do
  # Tab-separated so the model name ("Opus 4.8") keeps its space.
  IFS=$'\t' read -r key model p5 p7 ctx sv spend state age < <(
    jq -r --argjson now "$now" '
      [ .account_key, .model,
        (.rate.five_hour.pct|floor), (.rate.seven_day.pct|floor),
        (.context.used_pct|floor), (.saving_pct|floor),
        .spend.session_tokens, .cache.state,
        ($now - .updated_at) ] | @tsv' "$f" 2>/dev/null
  )
  [ -z "${key:-}" ] && continue
  [ "$p5" -gt "$worst" ] 2>/dev/null && worst="$p5"
  stale=""; [ "${age:-0}" -gt 90 ] 2>/dev/null && stale=" (idle)"
  spk="$(fmt_tokens "$spend")"
  c="$(color_for "$p5")"
  # Prettify the account key: split on - and _, capitalize each word.
  nm="$(printf '%s' "$key" | tr '_-' '  ' | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1)) substr($i,2)}1')"
  lines+=("$nm$stale  5h ${p5}% · 7d ${p7}% · ctx ${ctx}% · ${state} · save ${sv}% · ${spk} · ${model} | color=$c")
done

[ "$worst" -lt 0 ] && worst=0
echo "${worst}% | color=$(color_for "$worst")"
echo "---"
for l in "${lines[@]}"; do echo "$l"; done
