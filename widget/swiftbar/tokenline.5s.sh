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
              elif v>=1000 then "\(((v/100)|floor)/10)k" else "\(v|floor)" end;
  def titlecase: split(" ") | map((.[0:1]|ascii_upcase) + .[1:]) | join(" ");
  def pretty(k): (k | gsub("[-_]"; " ") | titlecase);
  def recency: (.active_at // .updated_at);

  # Group per-session snapshots by account. A session is shown only if its
  # window is still ticking AND it had a turn recently (idle ones are hidden).
  [ group_by(.account_key)[]
    | ([ .[] | select((.updated_at > ($now - 20)) and (recency > ($now - 900))) ]) as $shown
    | {
        key: .[0].account_key,
        live: ($shown | length),
        active: (if ($shown|length) > 0 then ($shown | max_by(recency)) else (max_by(.updated_at)) end),
        sessions: ($shown | sort_by(-recency))
      } ]
  | sort_by(-(.active.rate.five_hour.pct)) as $accts
  | ([ $accts[].active.rate.five_hour.pct ] | max // 0 | floor) as $worst

  | "\($worst)% | color=\(col($worst))",
    "---",
    ( $accts[]
      | (.active.rate.five_hour.pct|floor) as $p5
      | "\(pretty(.key))  5h \($p5)% · 7d \(.active.rate.seven_day.pct|floor)% · \(.live) sess | color=\(col($p5))",
        ( .sessions[]
          | (if (recency > ($now - 60)) then "🟢" else "🟡" end) as $sem
          | (if ((.dir // "") != "") then "  📁\(.dir)" else "" end) as $d
          | (if ((.branch // "") != "") then "  ⎇\(.branch)" else "" end) as $b
          | "-- \($sem) \(.model)  \(fmt(.context.tokens_used))/\(fmt(.context.size)) \(.context.used_pct|floor)% · \(.cache.state) · save \(.saving_pct|floor)% · \(fmt(.spend.session_tokens))\($d)\($b)"
        )
    )
' "${files[@]}"
