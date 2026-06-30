#!/usr/bin/env bash
# Tests the SwiftBar prototype reader against per-session fixture snapshots.
set -euo pipefail
cd "$(dirname "$0")/.."

out="$(TOKENLINE_WIDGET_DIR=test/fixtures/widget bash widget/swiftbar/tokenline.5s.sh)"
fail() { echo "FAIL: $1" >&2; echo "--- output ---" >&2; echo "$out" >&2; exit 1; }

# Menu bar line (first line) shows the most-constrained account: 95%.
echo "$out" | head -1 | grep -q '95%' || fail "menu bar not the worst account"

# One account header per account, key prettified (Title Case).
echo "$out" | grep -q '^Trabalho ' || fail "missing Trabalho account header"
echo "$out" | grep -q '^Pessoal '  || fail "missing Pessoal account header"
echo "$out" | grep -q '^Cliente '  || fail "missing Cliente account header"

# Pessoal has two sessions in the fixtures -> session count reflects it.
echo "$out" | grep -qF '2 sess' || fail "session count not grouped per account"

# Sessions render as nested (--) sub-lines with model + ctx + spend (C-locale).
echo "$out" | grep -q '^-- '         || fail "no nested session lines"
echo "$out" | grep -qF 'Opus 4.8'    || fail "model name mangled"
echo "$out" | grep -qF '124k/200k'   || fail "missing per-session ctx tokens (used/total)"
echo "$out" | grep -qF 'save '       || fail "missing per-session saving%"
echo "$out" | grep -qF '3.8M'        || fail "spend not C-locale formatted"
echo "$out" | grep -qF '🟢'          || fail "missing session state semaphore"
echo "$out" | grep -qF '📁my-project' || fail "missing session working dir"
echo "$out" | grep -qF '⎇feat/login'  || fail "missing session git branch"

echo "PASS: swiftbar"
