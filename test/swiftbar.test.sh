#!/usr/bin/env bash
# Tests the SwiftBar prototype reader against fixture snapshots.
set -euo pipefail
cd "$(dirname "$0")/.."

out="$(TOKENLINE_WIDGET_DIR=test/fixtures/widget bash widget/swiftbar/tokenline.5s.sh)"
fail() { echo "FAIL: $1" >&2; echo "--- output ---" >&2; echo "$out" >&2; exit 1; }

# Menu bar line (first line) shows the most-constrained account: 95%.
echo "$out" | head -1 | grep -q '95%' || fail "menu bar not the worst account"

# Dropdown has one line per account, with the key prettified (Title Case).
echo "$out" | grep -q '^Trabalho ' || fail "missing trabalho line"
echo "$out" | grep -q '^Pessoal '  || fail "missing pessoal line"
echo "$out" | grep -q '^Cliente '  || fail "missing cliente line"

# Dense fields are present and the model name keeps its space.
echo "$out" | grep -q 'save 71%'   || fail "missing saving field"
echo "$out" | grep -qF 'Opus 4.8'  || fail "model name mangled (IFS split?)"
echo "$out" | grep -qF '3.8M'      || fail "spend not C-locale formatted (comma decimal?)"

echo "PASS: swiftbar"
