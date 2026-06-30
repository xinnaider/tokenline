#!/usr/bin/env bash
# Tests the opt-in widget snapshot writer in tokenline.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

# Never inherit the operator's own widget settings into the assertions below.
unset TOKENLINE_WIDGET TOKENLINE_WIDGET_DIR

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pay="test/fixtures/payload.json"

fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. Opt-out: dir configured but flag absent -> nothing written (gate works).
w1="$tmp/widget1"
TOKENLINE_WIDGET_DIR="$w1" XDG_RUNTIME_DIR="$tmp/rt1" bash tokenline.sh < "$pay" >/dev/null 2>&1 || true
[ -z "$(ls -A "$w1" 2>/dev/null || true)" ] || fail "wrote a snapshot without TOKENLINE_WIDGET=1"

# 2. Opt-in: writes <account>.json with the expected derived fields.
w="$tmp/widget2"
TOKENLINE_WIDGET=1 TOKENLINE_WIDGET_DIR="$w" CLAUDE_CONFIG_DIR=/x/trabalho \
  XDG_RUNTIME_DIR="$tmp/rt2" bash tokenline.sh < "$pay" >/dev/null 2>&1 || true
[ -f "$w/trabalho.json" ] || fail "snapshot not written"
jq -e '.schema==1' "$w/trabalho.json" >/dev/null || fail "bad schema"
jq -e '.account_key=="trabalho"' "$w/trabalho.json" >/dev/null || fail "bad account_key"
jq -e '.rate.five_hour.pct==95' "$w/trabalho.json" >/dev/null || fail "bad 5h pct"
jq -e '.rate.seven_day.pct==88' "$w/trabalho.json" >/dev/null || fail "bad 7d pct"
jq -e '.model=="Opus 4.8"' "$w/trabalho.json" >/dev/null || fail "bad model"
jq -e '.econ.read==18000' "$w/trabalho.json" >/dev/null || fail "bad econ.read"
jq -e '.saving_pct>0' "$w/trabalho.json" >/dev/null || fail "saving_pct not populated"

# 3. Account key falls back to 'default' when CLAUDE_CONFIG_DIR is unset.
#    env -u guards against a CLAUDE_CONFIG_DIR inherited from the host session.
w3="$tmp/widget3"
env -u CLAUDE_CONFIG_DIR TOKENLINE_WIDGET=1 TOKENLINE_WIDGET_DIR="$w3" \
  XDG_RUNTIME_DIR="$tmp/rt3" bash tokenline.sh < "$pay" >/dev/null 2>&1 || true
[ -f "$w3/default.json" ] || fail "missing default.json fallback"

# 4. Stdout is byte-identical with and without the flag.
a="$(XDG_RUNTIME_DIR="$tmp/rt4" bash tokenline.sh < "$pay" 2>/dev/null || true)"
b="$(TOKENLINE_WIDGET=1 TOKENLINE_WIDGET_DIR="$tmp/widget4" CLAUDE_CONFIG_DIR=/x/p \
     XDG_RUNTIME_DIR="$tmp/rt5" bash tokenline.sh < "$pay" 2>/dev/null || true)"
[ "$a" = "$b" ] || fail "stdout differs with TOKENLINE_WIDGET=1"

# 5. Concurrent sessions of one account must not flicker: a lower 5h from a
#    different, fresh session must not stomp a higher one; the owner can update.
w5="$tmp/widget5"; rt5="$tmp/rt5"
run5() { # $1=5h pct  $2=session id
  sed "s/\"used_percentage\":95/\"used_percentage\":$1/; s/sess-test/$2/" "$pay" \
    | TOKENLINE_WIDGET=1 TOKENLINE_WIDGET_DIR="$w5" CLAUDE_CONFIG_DIR=/x/acct \
      XDG_RUNTIME_DIR="$rt5" bash tokenline.sh >/dev/null 2>&1 || true
}
run5 77 sessA
jq -e '.rate.five_hour.pct==77' "$w5/acct.json" >/dev/null || fail "session A (77) not written"
run5 46 sessB
jq -e '.rate.five_hour.pct==77' "$w5/acct.json" >/dev/null || fail "lower session B stomped the higher 5h"
run5 80 sessA
jq -e '.rate.five_hour.pct==80' "$w5/acct.json" >/dev/null || fail "owner session could not update its own value"

echo "PASS: widget-writer"
