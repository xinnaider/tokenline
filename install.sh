#!/usr/bin/env bash
# ==============================================================================
# tokenline installer — copies tokenline.sh into the chosen Claude profile(s)
# and safely patches each settings.json (backup, merge-only, idempotent, never
# clobbers invalid JSON), mirroring the npm CLI in pure bash + jq.
#
# Runs on stock macOS bash 3.2. Animations only on a TTY; piped runs stay plain.
# See usage() / --help for flags.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKENLINE_SRC="$SCRIPT_DIR/tokenline.sh"

# --- Options -----------------------------------------------------------------
OPT_DIRS=()   # one or more --dir targets (repeatable)
OPT_YES=0
OPT_DRYRUN=0
OPT_PRINT=0
OPT_FORCE=0
OPT_THEME=""
OPT_WIDGET="auto"   # auto (prompt) | yes | no — optional macOS multi-account widget
WIDGET_ON=0         # resolved by decide_widget; gates the writer + reader

usage() {
  cat <<'EOF'
tokenline installer

Copies tokenline.sh into one or more Claude profile directories and patches
each settings.json (backup, merge-only statusLine, idempotent, never clobbers
invalid JSON). Pick a theme and the profile(s) interactively.

Usage:
  ./install.sh                 # interactive — pick a theme, then profile(s)
  ./install.sh --theme <name>  # full | minimal | compact | economics | limits
  ./install.sh --yes           # non-interactive — full theme into ~/.claude
  ./install.sh --dir <path>    # install into a specific dir (repeat for several)
  ./install.sh --dry-run       # show what would happen, write nothing
  ./install.sh --print         # only print the settings snippet
  ./install.sh --force         # replace a different existing statusLine
  ./install.sh --widget        # also set up the macOS widget (Perch), no prompt
  ./install.sh --no-widget     # skip the macOS widget prompt entirely

The macOS multi-account widget (Perch) is optional. When enabled, the statusLine
command gets a TOKENLINE_WIDGET=1 prefix (writer scoped to that command — your
shell env is untouched) and a reader is installed: the native Perch.app if Xcode
+ xcodegen are present, otherwise the SwiftBar plugin. See widget/README.md.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) OPT_DIRS+=("${2:-}"); shift 2 ;;
    --theme) OPT_THEME="${2:-}"; shift 2 ;;
    -y|--yes) OPT_YES=1; shift ;;
    --dry-run) OPT_DRYRUN=1; shift ;;
    --print) OPT_PRINT=1; shift ;;
    --force) OPT_FORCE=1; shift ;;
    --widget) OPT_WIDGET="yes"; shift ;;
    --no-widget) OPT_WIDGET="no"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown option: %s (try --help)\n' "$1" >&2; exit 2 ;;
  esac
done

# Theme catalog (must match tokenline.sh --theme names; full = default).
THEME_NAMES=(full minimal compact economics limits)
THEME_DESCS=(
  "everything — model · ctx · cache + economics + limits"
  "model · ctx% · cache state"
  "model · ctx · cache · saving%"
  "model · ctx · cache + per-turn economics"
  "model · ctx · cache + 5h/7d limit bars"
)
# Tallest preview (full); the preview area is padded to this so the menu block
# keeps a constant height for the fixed cursor-up redraw.
PREVIEW_H=4

# Unknown --theme falls back to full.
if [ -n "$OPT_THEME" ]; then
  case "$OPT_THEME" in
    full|minimal|compact|economics|limits) ;;
    *) printf 'unknown theme: %s (using full)\n' "$OPT_THEME" >&2; OPT_THEME="full" ;;
  esac
fi

# --- Presentation ------------------------------------------------------------
# Colors and animation only when stdout is a TTY and NO_COLOR is unset.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_ACCENT=$'\033[38;5;51m'; C_DIM=$'\033[38;5;244m'; C_OK=$'\033[38;5;46m'
  C_ERR=$'\033[38;5;196m'; C_WARN=$'\033[38;5;226m'; C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'; TTY=1
else
  C_ACCENT=""; C_DIM=""; C_OK=""; C_ERR=""; C_WARN=""; C_BOLD=""
  C_RESET=""; TTY=0
fi
ANIM=$TTY
[ "$OPT_DRYRUN" -eq 1 ] && ANIM=0

# Restore the cursor if the arrow-key menu is interrupted mid-draw.
[ "$TTY" -eq 1 ] && trap 'printf "\033[?25h"' EXIT INT TERM

nap() { [ "$ANIM" -eq 1 ] && sleep 0.04; return 0; }

hero() {
  printf '\n %s%stokenline%s\n' "$C_BOLD" "$C_ACCENT" "$C_RESET"
  printf ' %scache-aware statusline installer%s\n\n' "$C_DIM" "$C_RESET"
}

ok_line()   { printf ' %s✓%s %s\n' "$C_OK" "$C_RESET" "$1"; nap; }
warn_line() { printf ' %s!%s %s\n' "$C_WARN" "$C_RESET" "$1"; nap; }
err_line()  { printf ' %s✗%s %s\n' "$C_ERR" "$C_RESET" "$1" >&2; nap; }
note_line() { printf ' %s→ %s%s\n' "$C_DIM" "$1" "$C_RESET"; nap; }

# Decorative braille spinner (~$1s, label $2) that paces the reveal; real work
# runs right after. No-ops off a TTY.
spin_for() {
  local secs="$1" label="$2"
  [ "$ANIM" -eq 1 ] || return 0
  local frames=( ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏ )
  local n i=0
  n=$(awk -v s="$secs" 'BEGIN { printf "%d", s / 0.08 }')
  while [ "$i" -lt "$n" ]; do
    printf '\r %s%s%s %s' "$C_ACCENT" "${frames[$((i % 10))]}" "$C_RESET" "$label"
    i=$((i + 1)); sleep 0.08
  done
  printf '\r\033[K'
}

# --- Path helpers ------------------------------------------------------------
expand_path() {
  # Expand a leading ~ in user-typed paths. The quoted "~/" is matched
  # literally on purpose (we want the tilde character, not shell expansion).
  # shellcheck disable=SC2088
  case "$1" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${1#"~/"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

statusline_command() {
  # Quote only when the path has a space, to match the npm CLI byte-for-byte.
  local base
  case "$1" in
    *" "*) base="bash \"$1\"" ;;
    *) base="bash $1" ;;
  esac
  # Omit the flag for full (the default) so the command stays identical.
  if [ -n "$OPT_THEME" ] && [ "$OPT_THEME" != "full" ]; then
    base="$base --theme $OPT_THEME"
  fi
  # Widget opt-in: enable the per-account snapshot writer just for this command,
  # without touching the user's shell env. Default (off) stays byte-for-byte.
  if [ "${WIDGET_ON:-0}" -eq 1 ]; then
    base="TOKENLINE_WIDGET=1 $base"
  fi
  printf '%s' "$base"
}

# --- Dependency check --------------------------------------------------------
HAVE_JQ=0
check_deps() {
  local missing=0
  spin_for 0.5 "checking dependencies"

  # Check the PATH `bash` (what runs the statusline), not this interpreter
  # (3.2 on stock macOS). Ask it directly so a localized `--version` can't break.
  local bash_ver bash_major
  bash_ver=$(bash -c 'printf "%s.%s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"' 2>/dev/null)
  bash_major=${bash_ver%%.*}
  if [ -n "$bash_major" ] && [ "$bash_major" -ge 4 ] 2>/dev/null; then
    ok_line "bash $bash_ver"
  else
    err_line "bash 4+ required for the statusline (PATH bash is ${bash_ver:-unknown}). On macOS: brew install bash"
    missing=1
  fi

  if command -v jq >/dev/null 2>&1; then
    HAVE_JQ=1
    ok_line "jq $(jq --version 2>/dev/null)"
  else
    err_line "jq not found — install it (apt install jq / brew install jq)"
    missing=1
  fi

  if date -d "@0" >/dev/null 2>&1 || date -j -f "%s" 0 >/dev/null 2>&1; then
    ok_line "date (GNU or BSD)"
  else
    err_line "no usable date (need GNU -d or BSD -j)"
    missing=1
  fi

  if stat -c %Y . >/dev/null 2>&1 || stat -f %m . >/dev/null 2>&1; then
    ok_line "stat (GNU or BSD)"
  else
    err_line "no usable stat (need GNU -c or BSD -f)"
    missing=1
  fi

  if [ -f "$TOKENLINE_SRC" ]; then
    ok_line "tokenline.sh found"
  else
    err_line "tokenline.sh not found next to install.sh"
    missing=1
  fi

  return "$missing"
}

# --- Profile selection -------------------------------------------------------
CAND_PATHS=()
CAND_LABELS=()
add_candidate() {
  local p="$1" label="$2" existing
  if [ "${#CAND_PATHS[@]}" -gt 0 ]; then
    for existing in "${CAND_PATHS[@]}"; do
      [ "$existing" = "$p" ] && return 0
    done
  fi
  CAND_PATHS+=("$p")
  CAND_LABELS+=("$label")
}

discover_candidates() {
  add_candidate "$HOME/.claude" "default"
  local d
  shopt -s nullglob
  for d in "$HOME"/.claude-* "$HOME"/.claude_*; do
    [ -d "$d" ] && add_candidate "$d" "profile"
  done
  shopt -u nullglob
  [ -d "$PWD/.claude" ] && add_candidate "$PWD/.claude" "this project"
}

# Clip a string to $2 columns, adding an ellipsis, so a long path can't wrap and
# desync the redraw line count.
fit() {
  local s="$1" max="$2"
  if [ "$max" -lt 1 ]; then printf '%s' "$s"; return 0; fi
  if [ "${#s}" -gt "$max" ]; then printf '%s…' "${s:0:$((max - 1))}"; else printf '%s' "$s"; fi
}

# Menu state shared between select_arrows() and draw_menu().
CURSOR=0
CUSTOM_IDX=0
COLS=80
SEL=()

draw_menu() {
  local i box cur label
  for i in "${!CAND_PATHS[@]}"; do
    cur="  "; [ "$i" -eq "$CURSOR" ] && cur="${C_ACCENT}❯${C_RESET} "
    box="${C_DIM}◯${C_RESET}"; [ "${SEL[$i]:-0}" = "1" ] && box="${C_OK}◉${C_RESET}"
    label="${CAND_PATHS[$i]}"
    [ -n "${CAND_LABELS[$i]}" ] && label="$label  (${CAND_LABELS[$i]})"
    printf '   %s%s %s\033[K\n' "$cur" "$box" "$(fit "$label" "$((COLS - 8))")"
  done
  cur="  "; [ "$CURSOR" -eq "$CUSTOM_IDX" ] && cur="${C_ACCENT}❯${C_RESET} "
  printf '   %s  %scustom path…%s\033[K\n' "$cur" "$C_DIM" "$C_RESET"
}

# Arrow-key multi-select (pure bash + ANSI, no stty). Fills TARGETS.
select_arrows() {
  local total key k2 i
  CURSOR=0; SEL=()
  for i in "${!CAND_PATHS[@]}"; do SEL[i]=0; done
  CUSTOM_IDX=${#CAND_PATHS[@]}
  total=$((CUSTOM_IDX + 1))
  COLS=$(tput cols 2>/dev/null || printf 80)

  printf ' %sInstall to which profile?%s %s(↑/↓ move · space toggle · 1-9 quick · enter confirm)%s\n\n' \
    "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
  printf '\033[?25l'
  draw_menu

  while :; do
    IFS= read -rsn1 key || key=""
    if [ "$key" = $'\033' ]; then
      IFS= read -rsn2 -t 1 k2 2>/dev/null || k2=""
      key="$key$k2"
    fi
    case "$key" in
      $'\033[A'|$'\033OA') CURSOR=$(((CURSOR - 1 + total) % total)) ;;
      $'\033[B'|$'\033OB') CURSOR=$(((CURSOR + 1) % total)) ;;
      ' ') [ "$CURSOR" -ne "$CUSTOM_IDX" ] && SEL[CURSOR]=$((1 - ${SEL[CURSOR]:-0})) ;;
      [1-9])
        i=$((key - 1))
        if [ "$i" -lt "$CUSTOM_IDX" ]; then CURSOR=$i; SEL[i]=$((1 - ${SEL[i]:-0})); fi
        ;;
      ""|$'\n'|$'\r') break ;;
      q|Q|$'\033') CURSOR=-1; break ;;
      *) : ;;
    esac
    printf '\033[%dA' "$total"
    draw_menu
  done
  printf '\033[?25h\n'

  if [ "$CURSOR" -eq -1 ]; then err_line "cancelled"; exit 1; fi

  if [ "$CURSOR" -eq "$CUSTOM_IDX" ]; then
    local custom
    printf ' %sCustom path%s: ' "$C_BOLD" "$C_RESET"
    IFS= read -r custom || custom=""
    printf '\n'
    [ -n "$custom" ] || { err_line "no path given"; exit 1; }
    TARGETS=( "$(expand_path "$custom")" )
    return 0
  fi

  TARGETS=()
  for i in "${!CAND_PATHS[@]}"; do
    [ "${SEL[$i]:-0}" = "1" ] && TARGETS+=( "${CAND_PATHS[$i]}" )
  done
  [ "${#TARGETS[@]}" -gt 0 ] || TARGETS=( "${CAND_PATHS[$CURSOR]}" )
}

# Typed fallback for terminals without cursor control (TERM=dumb). Reads a line
# of space-separated numbers, or 'c' for a custom path. Fills TARGETS.
select_typed() {
  printf ' %sInstall to which profile?%s\n' "$C_BOLD" "$C_RESET"
  local i
  for i in "${!CAND_PATHS[@]}"; do
    local suffix=""
    [ -n "${CAND_LABELS[$i]}" ] && suffix=" ${C_DIM}(${CAND_LABELS[$i]})${C_RESET}"
    printf '   %s%d)%s %s%s\n' "$C_DIM" "$((i + 1))" "$C_RESET" "${CAND_PATHS[$i]}" "$suffix"
  done
  printf '   %sc)%s custom path…\n' "$C_DIM" "$C_RESET"
  printf '\n %sSelect%s %s[Enter=default, e.g. 1 3, or c]%s: ' "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"

  local reply
  read -r reply || reply=""
  printf '\n'
  case "$reply" in
    "") TARGETS=( "${CAND_PATHS[0]}" ) ;;
    c|C)
      local custom
      printf ' %sCustom path%s: ' "$C_BOLD" "$C_RESET"
      read -r custom || custom=""
      printf '\n'
      [ -n "$custom" ] || { err_line "no path given"; exit 1; }
      TARGETS=( "$(expand_path "$custom")" )
      ;;
    *)
      local tok
      for tok in $reply; do
        case "$tok" in
          *[!0-9]*) warn_line "ignoring '$tok' (not a number)" ;;
          *)
            if [ "$tok" -ge 1 ] && [ "$tok" -le "${#CAND_PATHS[@]}" ]; then
              TARGETS+=( "${CAND_PATHS[$((tok - 1))]}" )
            else
              warn_line "ignoring '$tok' (out of range)"
            fi
            ;;
        esac
      done
      [ "${#TARGETS[@]}" -gt 0 ] || TARGETS=( "${CAND_PATHS[0]}" )
      ;;
  esac
}

# --- Theme selection ---------------------------------------------------------
THEME_CURSOR=0

# Colored mock of each theme, matching the live statusline layout/palette, so
# the preview shows what gets installed. One statusline line per printf line.
theme_preview() {
  local g=$'\033[38;5;244m' r=$'\033[0m' gb=$'\033[01;32m' cy=$'\033[38;5;51m'
  local ye=$'\033[38;5;226m' mg=$'\033[38;5;201m' og=$'\033[38;5;208m'
  local gr=$'\033[38;5;46m' dg=$'\033[38;5;240m' dot
  dot="${g} · ${r}"
  local l1="Opus 4.8 ${g}| ctx: ${r}${gb}46.2k/200.0k (42%)${r} ${g}| [5m] cache: ${gr}4:05 HOT${r}"
  local econ="${g}read(0.1x): ${cy}40.0k${r} ${g}write(1.25x): ${ye}5.0k${r} ${g}new(1x): ${mg}1.2k${r} ${g}output(5x): ${gr}800${r} ${g}eq: ${og}15.4k${r} ${g}saving: ${gr}69%${r}"
  local sep="${dg}──────────────────────────────${r}"
  local rl="${g}5h: ${r}${gr}███${dg}░░░░░░░${r} ${gr}30%${r}  ${g}7d: ${r}${gr}█${dg}░░░░░░░░░${r} ${gr}12%${r}"
  case "$1" in
    full)      printf '%s\n%s\n%s\n%s\n' "$l1" "$econ" "$sep" "$rl" ;;
    economics) printf '%s\n%s\n' "$l1" "$econ" ;;
    limits)    printf '%s\n%s\n%s\n' "$l1" "$sep" "$rl" ;;
    minimal)   printf 'Opus 4.8%s%sctx %s%s42%%%s%s%scache %sHOT%s\n' \
                 "$dot" "$g" "$r" "$gb" "$r" "$dot" "$g" "$gr" "$r" ;;
    compact)   printf 'Opus 4.8%s%sctx %s%s46.2k/200.0k 42%%%s%s%scache 4:05 %sHOT%s%s%ssave %s69%%%s\n' \
                 "$dot" "$g" "$r" "$gb" "$r" "$dot" "$g" "$gr" "$r" "$dot" "$g" "$gr" "$r" ;;
  esac
}

# Clip to $2 *visible* columns, copying ANSI escapes through without counting
# them (so a colored preview line never wraps and desyncs the redraw count).
clip_visible() {
  local s="$1" max="$2" out="" vis=0 i=0 n=${#1} ch
  while [ "$i" -lt "$n" ]; do
    ch="${s:i:1}"
    if [ "$ch" = $'\033' ]; then
      while [ "$i" -lt "$n" ]; do
        ch="${s:i:1}"; out="$out$ch"; i=$((i + 1))
        [ "$ch" = "m" ] && break
      done
      continue
    fi
    [ "$vis" -ge "$max" ] && break
    out="$out$ch"; vis=$((vis + 1)); i=$((i + 1))
  done
  printf '%s\033[0m' "$out"
}

draw_theme() {
  local i cur_m line n=0
  for i in "${!THEME_NAMES[@]}"; do
    cur_m="  "; [ "$i" -eq "$THEME_CURSOR" ] && cur_m="${C_ACCENT}❯${C_RESET} "
    printf '   %s%s%-10s%s %s%s%s\033[K\n' \
      "$cur_m" "$C_BOLD" "${THEME_NAMES[$i]}" "$C_RESET" "$C_DIM" "${THEME_DESCS[$i]}" "$C_RESET"
  done
  printf '\033[K\n'
  printf '   %spreview%s\033[K\n' "$C_DIM" "$C_RESET"
  while IFS= read -r line; do
    printf '     %s\033[K\n' "$(clip_visible "$line" "$((COLS - 6))")"; n=$((n + 1))
  done < <(theme_preview "${THEME_NAMES[$THEME_CURSOR]}")
  while [ "$n" -lt "$PREVIEW_H" ]; do printf '\033[K\n'; n=$((n + 1)); done
}

# Single-select arrow menu for the theme. Fills OPT_THEME.
choose_theme() {
  # Explicit flag, non-interactive, or dumb terminal: keep current (default full).
  if [ -n "$OPT_THEME" ]; then return 0; fi
  if ! { [ -t 0 ] && [ -t 1 ]; } || [ "${TERM:-dumb}" = "dumb" ]; then
    OPT_THEME="full"; return 0
  fi

  local total=${#THEME_NAMES[@]} key k2 i
  THEME_CURSOR=0
  COLS=$(tput cols 2>/dev/null || printf 80)
  printf ' %sChoose a theme%s %s(↑/↓ move · enter select)%s\n\n' \
    "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
  # Fixed block height (preview padded to PREVIEW_H) for a cursor-up redraw —
  # CUU is portable, SCO save/restore isn't.
  local block=$((total + 2 + PREVIEW_H))
  printf '\033[?25l'
  draw_theme
  while :; do
    IFS= read -rsn1 key || key=""
    if [ "$key" = $'\033' ]; then IFS= read -rsn2 -t 1 k2 2>/dev/null || k2=""; key="$key$k2"; fi
    case "$key" in
      $'\033[A'|$'\033OA') THEME_CURSOR=$(((THEME_CURSOR - 1 + total) % total)) ;;
      $'\033[B'|$'\033OB') THEME_CURSOR=$(((THEME_CURSOR + 1) % total)) ;;
      [1-9]) i=$((key - 1)); [ "$i" -lt "$total" ] && THEME_CURSOR=$i ;;
      ""|$'\n'|$'\r') break ;;
      q|Q|$'\033') OPT_THEME="full"; printf '\033[?25h\n'; return 0 ;;
      *) : ;;
    esac
    printf '\033[%dA' "$block"
    draw_theme
  done
  printf '\033[?25h\n'
  OPT_THEME="${THEME_NAMES[$THEME_CURSOR]}"
}

# Fills the global TARGETS array with the directories to install into.
TARGETS=()
choose_targets() {
  if [ "${#OPT_DIRS[@]}" -gt 0 ]; then
    TARGETS=()
    local d
    for d in "${OPT_DIRS[@]}"; do TARGETS+=( "$(expand_path "$d")" ); done
    return 0
  fi
  if [ "$OPT_YES" -eq 1 ]; then
    TARGETS=( "$HOME/.claude" )
    return 0
  fi

  discover_candidates

  # Interactive needs a TTY on both ends. Arrow menu when the terminal supports
  # cursor moves; typed fallback for TERM=dumb; default when not interactive.
  if [ -t 0 ] && [ -t 1 ]; then
    if [ "${TERM:-dumb}" = "dumb" ]; then select_typed; else select_arrows; fi
  else
    TARGETS=( "${CAND_PATHS[0]}" )
  fi
}

# --- Settings patching (mirrors the npm CLI's safety contract) ---------------
print_manual() {
  local cmd="$1"
  printf '\n Add this to your settings.json, inside the top-level object:\n\n'
  printf '  "statusLine": {\n'
  printf '    "type": "command",\n'
  printf '    "command": "%s",\n' "$cmd"
  printf '    "refreshInterval": 1\n'
  printf '  }\n\n'
}

patch_settings() {
  local settings="$1" cmd="$2"

  if [ "$HAVE_JQ" -ne 1 ]; then
    warn_line "jq missing — can't patch $settings safely"
    print_manual "$cmd"
    return 0
  fi

  if [ ! -f "$settings" ]; then
    jq -n --arg c "$cmd" \
      '{statusLine:{type:"command",command:$c,refreshInterval:1}}' > "$settings"
    ok_line "settings → $settings (created)"
    return 0
  fi

  if ! jq empty "$settings" >/dev/null 2>&1; then
    err_line "invalid JSON in $settings — left untouched"
    print_manual "$cmd"
    return 0
  fi

  local existing
  existing=$(jq -r '.statusLine.command // empty' "$settings")
  if [ "$existing" = "$cmd" ]; then
    ok_line "settings → $settings (already configured)"
    return 0
  fi
  if [ -n "$existing" ] && [ "$OPT_FORCE" -ne 1 ]; then
    warn_line "a different statusLine exists in $settings — re-run with --force to replace"
    return 0
  fi

  cp "$settings" "$settings.bak"
  jq --arg c "$cmd" \
    '.statusLine={type:"command",command:$c,refreshInterval:1}' \
    "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
  local verb="added"; [ -n "$existing" ] && verb="replaced"
  ok_line "settings → $settings ($verb, backup → settings.json.bak)"
}

install_one() {
  local dir="$1"
  local script_path="$dir/tokenline.sh"
  local settings="$dir/settings.json"
  local cmd; cmd=$(statusline_command "$script_path")

  if [ "$OPT_DRYRUN" -eq 1 ]; then
    note_line "would copy  → $script_path"
    note_line "would patch → $settings"
    return 0
  fi

  spin_for 0.4 "installing into $dir"
  mkdir -p "$dir"
  cp "$TOKENLINE_SRC" "$script_path"
  chmod 755 "$script_path"
  ok_line "script → $script_path"
  patch_settings "$settings" "$cmd"
}

# --- macOS widget (Perch) — optional, never required -------------------------
# Resolves WIDGET_ON before the install loop so statusline_command can add the
# writer prefix. The reader (native app / SwiftBar plugin) is installed after.
decide_widget() {
  WIDGET_ON=0
  [ "$(uname -s)" = "Darwin" ] || return 0    # the reader is macOS-only
  case "$OPT_WIDGET" in
    yes) WIDGET_ON=1; return 0 ;;
    no)  return 0 ;;
    *)   ;;                                    # auto → preserve/prompt
  esac
  # Preserve an existing setup: if any target already has the writer enabled,
  # keep it on. Re-running the installer must never silently disable the widget.
  local t
  for t in "${TARGETS[@]}"; do
    if [ -f "$t/settings.json" ] && grep -q 'TOKENLINE_WIDGET=1' "$t/settings.json" 2>/dev/null; then
      WIDGET_ON=1
      note_line "widget already enabled — keeping it on"
      return 0
    fi
  done
  { [ -t 0 ] && [ -t 1 ]; } || return 0
  printf '\n %sAlso set up the macOS multi-account widget (Perch)?%s %s[y/N]%s ' \
    "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
  local reply; IFS= read -r reply || reply=""
  case "$reply" in y|Y|yes|Yes|YES) WIDGET_ON=1 ;; esac
}

install_swiftbar_plugin() {
  local plugin="$SCRIPT_DIR/widget/swiftbar/tokenline.5s.sh"
  local sbdir="$HOME/Library/Application Support/SwiftBar/Plugins"
  if [ -d "$sbdir" ] && [ -f "$plugin" ]; then
    if cp "$plugin" "$sbdir/" 2>/dev/null; then
      chmod +x "$sbdir/tokenline.5s.sh" 2>/dev/null || true
      ok_line "SwiftBar plugin → ${sbdir/#$HOME/~}/tokenline.5s.sh"
      return 0
    fi
    warn_line "couldn't copy the SwiftBar plugin — see widget/README.md"
    return 1
  fi
  note_line "reader: install SwiftBar + copy widget/swiftbar/, or build the app — see widget/README.md"
}

build_perch_app() {
  local app="$SCRIPT_DIR/widget/macos/App"
  spin_for 0.4 "building Perch.app (this takes a moment)"
  ( cd "$app" && xcodegen generate >/dev/null 2>&1 \
      && xcodebuild -project TokenlineWidget.xcodeproj -scheme TokenlineWidget \
           -configuration Release -derivedDataPath build build >/dev/null 2>&1 ) \
    || { warn_line "native build failed — falling back to SwiftBar"; return 1; }

  local built="$app/build/Build/Products/Release/TokenlineWidget.app"
  [ -d "$built" ] || { warn_line "build produced no .app — see widget/README.md"; return 1; }

  # Stop a running copy first — replacing a live .app bundle on disk leaves a
  # dead, unclickable "ghost" menu bar item.
  pkill -f '/Perch.app/Contents/MacOS/' 2>/dev/null || true
  pkill -f '/TokenlineWidget.app/Contents/MacOS/' 2>/dev/null || true
  sleep 1

  local dest="/Applications/Perch.app"
  if ! { rm -rf "$dest" 2>/dev/null && cp -R "$built" "$dest" 2>/dev/null; }; then
    dest="$HOME/Applications/Perch.app"
    mkdir -p "$HOME/Applications" 2>/dev/null || true
    rm -rf "$dest" 2>/dev/null || true
    cp -R "$built" "$dest" 2>/dev/null \
      || { warn_line "couldn't install Perch.app (built at $built)"; return 1; }
  fi
  ok_line "Perch.app → ${dest/#$HOME/~}"
  open "$dest" 2>/dev/null || true
  ok_line "Perch launched — colored bars appear in the menu bar"
}

setup_widget_reader() {
  [ "${WIDGET_ON:-0}" -eq 1 ] || return 0
  if [ "$OPT_DRYRUN" -eq 1 ]; then
    note_line "would install the Perch reader (native app or SwiftBar plugin)"
    return 0
  fi
  printf '\n'
  if command -v xcodegen >/dev/null 2>&1 && command -v xcodebuild >/dev/null 2>&1 \
       && [ -d "$SCRIPT_DIR/widget/macos/App" ]; then
    build_perch_app || install_swiftbar_plugin
  else
    install_swiftbar_plugin
  fi
  note_line "start a Claude session in an installed profile so snapshots appear"
}

# --- Main --------------------------------------------------------------------
hero

# --print: keep the original copy-paste workflow, no writes.
if [ "$OPT_PRINT" -eq 1 ]; then
  cmd=$(statusline_command "$TOKENLINE_SRC")
  print_manual "$cmd"
  exit 0
fi

if ! check_deps; then
  printf '\n'
  warn_line "Missing dependencies above. On macOS: brew install bash jq."
  warn_line "Fix them, then re-run ./install.sh."
  exit 1
fi
printf '\n'

choose_theme
printf '\n'
choose_targets
decide_widget   # resolves WIDGET_ON before install so the command can opt the writer in

for t in "${TARGETS[@]}"; do
  install_one "$t"
done

setup_widget_reader

if [ "$OPT_DRYRUN" -eq 1 ]; then
  printf '\n %s[dry-run] nothing was written.%s\n\n' "$C_DIM" "$C_RESET"
else
  printf '\n %s%sDone.%s Restart Claude Code to see the statusline.\n' "$C_BOLD" "$C_OK" "$C_RESET"
  [ "$WIDGET_ON" -eq 1 ] && printf ' %sPerch%s shows your accounts in the menu bar.\n' "$C_BOLD" "$C_RESET"
  printf '\n'
fi
