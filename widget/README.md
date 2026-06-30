# tokenline — macOS multi-account widget

A macOS menu bar widget that aggregates Claude usage across **N accounts** (one
per `CLAUDE_CONFIG_DIR`). Same data as the `tokenline.sh` statusline — model,
context, cache, per-turn economics, saving %, 5h/7d rate limits — but shown per
account, always visible in the menu bar. The bar shows the most-constrained
account's 5h %; the dropdown lists one dense block per account.

It's **opt-in** and **macOS-only**. The statusline itself is unchanged unless you
turn the writer on.

## How it works

`tokenline.sh` is the sensor: the rate-limit and per-turn economics only exist in
the per-second stdin payload, so capture has to ride along with the statusline.
When `TOKENLINE_WIDGET=1`, after rendering, it writes a small **derived** snapshot
per account (never the raw payload) to a shared dir. Two readers consume the same
store: a SwiftBar bash plugin (quick) and a native SwiftUI app (polished).

```
session (CLAUDE_CONFIG_DIR=trabalho) ─┐
session (CLAUDE_CONFIG_DIR=pessoal)  ─┤ tokenline.sh + TOKENLINE_WIDGET=1
session (CLAUDE_CONFIG_DIR=cliente)  ─┘        │ writes <account>.json
                                               ▼
            ~/Library/Application Support/tokenline/widget/<account>.json (0700)
                                               │
                         ┌─────────────────────┴─────────────────────┐
                   SwiftBar plugin                          MenuBarExtra app
```

## 1. Enable the writer

In each account's shell (where `CLAUDE_CONFIG_DIR` points at that account's
config), export:

```bash
export TOKENLINE_WIDGET=1
# CLAUDE_CONFIG_DIR already distinguishes the account, e.g. ~/.claude-trabalho
```

The account key is `basename "$CLAUDE_CONFIG_DIR"` (falls back to `default`).
Snapshots land in `~/Library/Application Support/tokenline/widget/` (override with
`TOKENLINE_WIDGET_DIR`). Each file is `schema:1`:

```json
{"schema":1,"account_key":"trabalho","model":"Opus 4.8",
 "context":{"used_pct":62,"size":200000,"tokens_used":124000},
 "cache":{"state":"HOT","ttl_label":"5m"},
 "econ":{"read":18000,"write":2100,"new":3400,"output":1200,"eq":24000},
 "saving_pct":71,
 "rate":{"five_hour":{"pct":78,"resets_at":"..."},"seven_day":{"pct":41,"resets_at":"..."}},
 "spend":{"session_tokens":1240000},"updated_at":1782783346}
```

## 2a. SwiftBar (quick)

Install [SwiftBar](https://github.com/swiftbar/SwiftBar) (`brew install swiftbar`),
then drop the plugin into your SwiftBar plugin folder:

```bash
cp widget/swiftbar/tokenline.5s.sh "$HOME/Library/Application Support/SwiftBar/Plugins/"
chmod +x "$HOME/Library/Application Support/SwiftBar/Plugins/tokenline.5s.sh"
```

It refreshes every 5s. The menu bar shows the worst 5h %; the dropdown lists each
account.

## 2b. Native app (polished)

Requires Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`):

```bash
cd widget/macos/App
xcodegen generate
xcodebuild -project TokenlineWidget.xcodeproj -scheme TokenlineWidget -configuration Debug build
# or: open TokenlineWidget.xcodeproj   # then Run
```

The built `TokenlineWidget.app` is a menu bar agent (`LSUIElement`, no Dock icon).

- **Friendly names:** edit `~/Library/Application Support/tokenline/labels.json`:
  ```json
  { "trabalho": {"label":"Trabalho","order":0}, "cliente": {"label":"Cliente X","order":1} }
  ```
- **Launch at login:** toggle it in the app's Settings (uses `SMAppService`).

The testable core lives in `widget/macos/TokenlineWidgetKit` (`swift test`).

## Layout

`widget/`
- `swiftbar/tokenline.5s.sh` — SwiftBar/xbar reader
- `macos/TokenlineWidgetKit/` — SwiftPM kit (Snapshot, Store, Labels) + tests
- `macos/App/` — `MenuBarExtra` app (XcodeGen `project.yml`, `LSUIElement`)
