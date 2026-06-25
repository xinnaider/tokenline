#!/usr/bin/env bash
# ==============================================================================
# tokenline installer
#
# Verifies dependencies and prints the Claude Code settings.json snippet that
# enables the statusline. It does NOT edit your settings file — it prints the
# block so you can paste it where you want (global or per-project).
#
# Usage:
#   ./install.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKENLINE="$SCRIPT_DIR/tokenline.sh"

c_green=$'\033[0;32m'; c_red=$'\033[0;31m'; c_yellow=$'\033[0;33m'; c_reset=$'\033[0m'
ok()   { printf '%s✓%s %s\n' "$c_green"  "$c_reset" "$1"; }
warn() { printf '%s!%s %s\n'      "$c_yellow" "$c_reset" "$1"; }
err()  { printf '%s✗%s %s\n' "$c_red"    "$c_reset" "$1"; }

printf '\ntokenline — dependency check\n'
printf '%s\n' "--------------------------------"

missing=0

# bash 4+ (mapfile/associative features)
if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
  ok "bash ${BASH_VERSION%%(*}"
else
  err "bash 4+ required (found ${BASH_VERSION%%(*}). macOS ships 3.2 — see README roadmap."
  missing=1
fi

# jq — the JSON parser the statusline depends on
if command -v jq >/dev/null 2>&1; then
  ok "jq $(jq --version 2>/dev/null)"
else
  err "jq not found — install it (apt install jq / brew install jq)"
  missing=1
fi

# GNU date (-d): used to parse ISO timestamps from the transcript
if date -d "@0" >/dev/null 2>&1; then
  ok "GNU date (-d)"
else
  err "GNU date (-d) missing — BSD/macOS date differs (see README roadmap)"
  missing=1
fi

# GNU stat (-c): mtime fallback for the cache timer
if stat -c %Y . >/dev/null 2>&1; then
  ok "GNU stat (-c)"
else
  err "GNU stat (-c) missing — BSD/macOS stat differs (see README roadmap)"
  missing=1
fi

# the script itself
if [ -f "$TOKENLINE" ]; then
  chmod +x "$TOKENLINE" 2>/dev/null || true
  ok "tokenline.sh found"
else
  err "tokenline.sh not found next to install.sh"
  missing=1
fi

printf '\n'
if [ "$missing" -ne 0 ]; then
  warn "Missing dependencies above. tokenline targets Linux/WSL2 for v1;"
  warn "macOS/Windows support is on the roadmap (see README)."
  printf '\n'
fi

printf 'Add this to %s/.claude/settings.json\n' "$HOME"
printf '(or your project .claude/settings.json), inside the top-level object:\n\n'
cat <<EOF
  "statusLine": {
    "type": "command",
    "command": "bash $TOKENLINE",
    "refreshInterval": 1
  }
EOF
printf '\nThen restart Claude Code. Enjoy your cache-aware statusline.\n\n'
