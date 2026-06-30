#!/usr/bin/env bash
# <xbar.title>tokenline</xbar.title>
# <xbar.desc>Claude usage across multiple accounts</xbar.desc>
# <xbar.dependencies>jq</xbar.dependencies>
#
# SwiftBar/xbar plugin: reads tokenline per-session snapshots (written by
# tokenline.sh when TOKENLINE_WIDGET=1), groups them by account, and shows each
# account's 5h/7d limit with its live sessions nested underneath. The menu bar
# shows the most-constrained account's 5h %. Same store/schema the native
# MenuBarExtra app consumes — this is the throwaway prototype reader.
set -uo pipefail

# Pin C locale so awk/jq emit "3.8M" not "3,8M" under comma-decimal locales.
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

jq -s -r --argjson now "$now" '
  def col(p): if p>=86 then "red" elif p>=50 then "orange" else "green" end;
  def fmt(v): if v>=1000000 then "\(((v/100000)|floor)/10)M"
              elif v>=1000 then "\((v/1000)|floor)k" else "\(v|floor)" end;
  def titlecase: split(" ") | map((.[0:1]|ascii_upcase) + .[1:]) | join(" ");
  def pretty(k): (k | gsub("[-_]"; " ") | titlecase);

  # Group per-session snapshots by account; pick the most-recently-active
  # session for the account-wide rate limit; count sessions still ticking.
  [ group_by(.account_key)[] | {
      key: .[0].account_key,
      live: ([ .[] | select((.updated_at // 0) > ($now - 30)) ] | length),
      active: (max_by(.active_at // .updated_at)),
      sessions: (sort_by(-(.active_at // .updated_at)))
    } ]
  | sort_by(-(.active.rate.five_hour.pct)) as $accts
  | ([ $accts[].active.rate.five_hour.pct ] | max // 0 | floor) as $worst

  | "\($worst)% | color=\(col($worst))",
    "---",
    ( $accts[]
      | (.active.rate.five_hour.pct|floor) as $p5
      | "\(pretty(.key))  5h \($p5)% · 7d \(.active.rate.seven_day.pct|floor)% · \(.live) sess | color=\(col($p5))",
        ( .sessions[]
          | "-- \(.model)  ctx \(.context.used_pct|floor)% · \(.cache.state) · \(fmt(.spend.session_tokens))"
        )
    )
' "${files[@]}"
