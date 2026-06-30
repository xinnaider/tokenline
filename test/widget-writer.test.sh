#!/usr/bin/env bash
# Tests the opt-in widget snapshot writer in tokenline.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

# Never inherit the operator's own widget settings into the assertions below.
unset TOKENLINE_WIDGET TOKENLINE_WIDGET_DIR

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pay="test/fixtures/payload.json"

fail() { echo "FAIL: $1" >&2; exit 1; }
one() { find "$1" -maxdepth 1 -name '*.json' 2>/dev/null | head -1; }   # the single snapshot in a dir

# 1. Opt-out: dir configured but flag absent -> nothing written (gate works).
w1="$tmp/widget1"
TOKENLINE_WIDGET_DIR="$w1" XDG_RUNTIME_DIR="$tmp/rt1" bash tokenline.sh < "$pay" >/dev/null 2>&1 || true
[ -z "$(ls -A "$w1" 2>/dev/null || true)" ] || fail "wrote a snapshot without TOKENLINE_WIDGET=1"

# 2. Opt-in: writes one <account>__<session>.json with the expected derived fields.
w="$tmp/widget2"
TOKENLINE_WIDGET=1 TOKENLINE_WIDGET_DIR="$w" CLAUDE_CONFIG_DIR=/x/trabalho \
  XDG_RUNTIME_DIR="$tmp/rt2" bash tokenline.sh < "$pay" >/dev/null 2>&1 || true
f="$(one "$w")"
[ -n "$f" ] && [ -f "$f" ] || fail "snapshot not written"
case "$f" in *trabalho__*.json) ;; *) fail "snapshot not named <account>__<session>" ;; esac
jq -e '.schema==1' "$f" >/dev/null || fail "bad schema"
jq -e '.account_key=="trabalho"' "$f" >/dev/null || fail "bad account_key"
jq -e '.session_id=="sess-test"' "$f" >/dev/null || fail "bad session_id"
jq -e '.rate.five_hour.pct==95' "$f" >/dev/null || fail "bad 5h pct"
jq -e '.context.used_pct==62' "$f" >/dev/null || fail "bad ctx"
jq -e '.model=="Opus 4.8"' "$f" >/dev/null || fail "bad model"
jq -e '.econ.read==18000' "$f" >/dev/null || fail "bad econ.read"
jq -e '.saving_pct>0' "$f" >/dev/null || fail "saving_pct not populated"

# 3. Unset CLAUDE_CONFIG_DIR maps to the default config dir (~/.claude) -> "claude".
w3="$tmp/widget3"
env -u CLAUDE_CONFIG_DIR TOKENLINE_WIDGET=1 TOKENLINE_WIDGET_DIR="$w3" \
  XDG_RUNTIME_DIR="$tmp/rt3" bash tokenline.sh < "$pay" >/dev/null 2>&1 || true
jq -e '.account_key=="claude"' "$(one "$w3")" >/dev/null 2>&1 || fail "unset config dir not keyed 'claude'"

# 4. Stdout is byte-identical with and without the flag.
a="$(XDG_RUNTIME_DIR="$tmp/rt4" bash tokenline.sh < "$pay" 2>/dev/null || true)"
b="$(TOKENLINE_WIDGET=1 TOKENLINE_WIDGET_DIR="$tmp/widget4" CLAUDE_CONFIG_DIR=/x/p \
     XDG_RUNTIME_DIR="$tmp/rt5" bash tokenline.sh < "$pay" 2>/dev/null || true)"
[ "$a" = "$b" ] || fail "stdout differs with TOKENLINE_WIDGET=1"

# 5. Internal subagents are not sessions: a subagent transcript writes nothing.
w6="$tmp/widget6"
sed 's#"transcript_path":""#"transcript_path":"/x/projects/p/subagents/s.jsonl"#' "$pay" \
  | TOKENLINE_WIDGET=1 TOKENLINE_WIDGET_DIR="$w6" CLAUDE_CONFIG_DIR=/x/acct \
    XDG_RUNTIME_DIR="$tmp/rt6" bash tokenline.sh >/dev/null 2>&1 || true
[ -z "$(ls -A "$w6" 2>/dev/null || true)" ] || fail "wrote a snapshot for a subagent"

# 6. Two sessions of one account -> two separate snapshot files.
w7="$tmp/widget7"
runs() { # $1 = session id
  sed 's/sess-test/'"$1"'/' "$pay" \
    | TOKENLINE_WIDGET=1 TOKENLINE_WIDGET_DIR="$w7" CLAUDE_CONFIG_DIR=/x/acct \
      XDG_RUNTIME_DIR="$tmp/rt7" bash tokenline.sh >/dev/null 2>&1 || true
}
runs sessA
runs sessB
[ -f "$w7/acct__sessA.json" ] && [ -f "$w7/acct__sessB.json" ] \
  || fail "concurrent sessions did not produce separate per-session files"

# 7. Working dir is captured from the payload (basename); branch empty off-repo.
w8="$tmp/widget8"
jq -c '. + {workspace:{current_dir:"/x/projects/my-proj"}}' "$pay" \
  | TOKENLINE_WIDGET=1 TOKENLINE_WIDGET_DIR="$w8" CLAUDE_CONFIG_DIR=/x/acct \
    XDG_RUNTIME_DIR="$tmp/rt8" bash tokenline.sh >/dev/null 2>&1 || true
jq -e '.dir=="my-proj"' "$(one "$w8")" >/dev/null 2>&1 || fail "working dir not captured"

echo "PASS: widget-writer"
