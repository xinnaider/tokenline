# macOS Multi-Account Menu Bar Widget — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a macOS menu bar widget that aggregates Claude usage across N accounts (one per `CLAUDE_CONFIG_DIR`), fed by an opt-in snapshot writer inside `tokenline.sh`.

**Architecture:** `tokenline.sh` is the sensor — on each render it optionally writes a small *derived* JSON snapshot per account to a shared dir. Two readers consume the same store: a throwaway SwiftBar bash plugin (fast validation) and the product, a SwiftUI `MenuBarExtra` app. The app polls the dir, picks the most-constrained account for the bar, and renders a dense block per account.

**Tech Stack:** Bash 4+/jq/coreutils (writer + SwiftBar), Swift 5.9 / SwiftUI `MenuBarExtra` (macOS 13+), Swift Package Manager (testable kit), XcodeGen (app project from `project.yml`).

## Global Constraints

- Never crash the host CLI: writer runs isolated, never `exit≠0`, never blocks the rendered line. (from spec / AGENTS.md)
- Statusline stdout MUST be byte-identical with and without `TOKENLINE_WIDGET=1`. (from spec)
- Writer is opt-in: default OFF, zero behavior change unless `TOKENLINE_WIDGET=1`. (from spec)
- Never write the raw stdin payload to disk — only derived metrics. (from AGENTS.md)
- ShellCheck-clean: `shellcheck -s bash tokenline.sh` passes. (from AGENTS.md / CI)
- No new hard runtime deps beyond bash 4+, jq, GNU/BSD coreutils. (XcodeGen is dev-only build tooling, not a runtime dep.)
- Store dir: `~/Library/Application Support/tokenline/widget/`, mode `0700`. (from spec)
- Account key = `basename "$CLAUDE_CONFIG_DIR"` (fallback `default`). (from spec)
- App: macOS 13+, non-sandboxed, `LSUIElement = YES`, bundle id `tech.inbrace.tokenline.widget`. (from spec)
- Gasto in tokens only (session-cumulative); `$` and "today" are out of scope. (from spec)

## File Structure

- `tokenline.sh` — **modify**: expose `eq_tokens`; add `_widget_snapshot` writer + opt-in call.
- `test/widget-writer.test.sh` — **create**: bash test for the writer.
- `test/fixtures/payload.json` — **create**: sample stdin payload.
- `.github/workflows/ci.yml` — **modify**: run the bash test.
- `widget/swiftbar/tokenline.5s.sh` — **create**: SwiftBar plugin (reader #1).
- `test/swiftbar.test.sh` + `test/fixtures/widget/*.json` — **create**: plugin test + fixtures.
- `widget/macos/TokenlineWidgetKit/Package.swift` — **create**: SPM package.
- `widget/macos/TokenlineWidgetKit/Sources/TokenlineWidgetKit/Snapshot.swift` — **create**: Codable model.
- `widget/macos/TokenlineWidgetKit/Sources/TokenlineWidgetKit/Store.swift` — **create**: loader + selection + staleness.
- `widget/macos/TokenlineWidgetKit/Tests/TokenlineWidgetKitTests/*.swift` — **create**: unit tests.
- `widget/macos/App/project.yml` — **create**: XcodeGen project.
- `widget/macos/App/Info.plist` — **create**: `LSUIElement`.
- `widget/macos/App/Sources/*.swift` — **create**: `MenuBarExtra` app + views + model.
- `widget/macos/App/Sources/Labels.swift` + settings/login — **create**: labels.json + `SMAppService`.
- `widget/README.md` — **create**: build/run/install docs.

---

## Task 1: Snapshot writer in `tokenline.sh`

**Files:**
- Modify: `tokenline.sh` (expose `eq_tokens`; add `_widget_snapshot`; call at end of main)

**Interfaces:**
- Consumes (existing globals after the render pipeline): `model`, `used_pct`, `tokens_limit`, `tokens_used`, `cache_state`, `ttl_label`, `cur_cread`, `cur_cwrite`, `cur_input`, `cur_output`, `eq_tokens`, `saving_pct`, `rl_5h_pct`, `rl_5h_reset`, `rl_7d_pct`, `rl_7d_reset`, `session_id`, `now`, `_runtime_dir`.
- Produces: file `<TOKENLINE_WIDGET_DIR>/<account>.json` matching the snapshot schema (schema:1).

- [ ] **Step 1: Expose `eq_tokens`** — in `compute_turn_breakdown` (around line 435), remove `eq_tokens` from the `local` declarations so the writer can read it. Change:

```bash
    local eq_tokens
    local uncached_eq
```
to:
```bash
    local uncached_eq
```
(`eq_tokens` is now assigned as a global; it is only set inside the token branch, so the writer must default it.)

- [ ] **Step 2: Add the writer function** — insert before the `# --- 7. Compose and Render Output ---` section:

```bash
# --- Widget snapshot writer (opt-in via TOKENLINE_WIDGET=1) ---------------------
# Emits a small DERIVED snapshot per account so an external macOS menu bar app can
# aggregate usage across multiple CLAUDE_CONFIG_DIR accounts. Never writes the raw
# stdin payload — only computed metrics. Must never affect the rendered line: all
# failures are swallowed and it returns 0.
_num() { case "${1:-}" in ''|*[!0-9.]*) printf 0 ;; *) printf '%s' "$1" ;; esac; }

_widget_snapshot() {
  [ "${TOKENLINE_WIDGET:-0}" = "1" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local dir="${TOKENLINE_WIDGET_DIR:-$HOME/Library/Application Support/tokenline/widget}"
  local key="${CLAUDE_CONFIG_DIR:-default}"
  key="$(basename "$key")"
  mkdir -p "$dir" 2>/dev/null || return 0
  chmod 700 "$dir" 2>/dev/null

  local out="$dir/$key.json"
  local stamp="$_runtime_dir/widgetlast-${session_id:-default}"

  # Throttle: skip if fingerprint unchanged AND written < 5s ago.
  local fp="${rl_5h_pct}|${rl_7d_pct}|${used_pct}|${saving_pct}|${tokens_used}|${model}"
  local prev_t="" prev_fp=""
  if [ -f "$stamp" ]; then
    IFS='|' read -r prev_t prev_fp < "$stamp"
    if [ "$fp" = "$prev_fp" ] && [ $(( now - ${prev_t:-0} )) -lt 5 ]; then
      return 0
    fi
  fi

  # Cumulative session spend (tokens): grow on a new turn (tokens_used changed).
  local spend_file="$_runtime_dir/widgetspend-${session_id:-default}"
  local spend last_tok
  spend="$(awk '{print $1}' "$spend_file" 2>/dev/null)"; spend="$(_num "$spend")"
  last_tok="$(awk '{print $2}' "$spend_file" 2>/dev/null)"; last_tok="$(_num "$last_tok")"
  if [ "${tokens_used:-0}" -ne "$last_tok" ] 2>/dev/null; then
    spend=$(( spend + $(_num "$cur_input") + $(_num "$cur_output") ))
    printf '%s %s\n' "$spend" "${tokens_used:-0}" > "$spend_file" 2>/dev/null
  fi

  jq -nc \
    --arg key "$key" --arg sid "${session_id:-}" --arg model "${model:-}" \
    --argjson up "$(_num "$used_pct")" --argjson sz "$(_num "$tokens_limit")" --argjson tu "$(_num "$tokens_used")" \
    --arg cs "${cache_state:-}" --arg ttl "${ttl_label:-}" \
    --argjson r "$(_num "$cur_cread")" --argjson w "$(_num "$cur_cwrite")" --argjson n "$(_num "$cur_input")" \
    --argjson o "$(_num "$cur_output")" --argjson eq "$(_num "$eq_tokens")" --argjson sv "$(_num "$saving_pct")" \
    --argjson p5 "$(_num "$rl_5h_pct")" --arg r5 "${rl_5h_reset:-}" \
    --argjson p7 "$(_num "$rl_7d_pct")" --arg r7 "${rl_7d_reset:-}" \
    --argjson spend "$(_num "$spend")" --argjson ts "$(_num "$now")" \
    '{schema:1, account_key:$key, session_id:$sid, model:$model,
      context:{used_pct:$up, size:$sz, tokens_used:$tu},
      cache:{state:$cs, ttl_label:$ttl},
      econ:{read:$r, write:$w, new:$n, output:$o, eq:$eq},
      saving_pct:$sv,
      rate:{five_hour:{pct:$p5, resets_at:$r5}, seven_day:{pct:$p7, resets_at:$r7}},
      spend:{session_tokens:$spend}, updated_at:$ts}' \
    > "$out.tmp" 2>/dev/null && mv "$out.tmp" "$out" 2>/dev/null

  printf '%s|%s\n' "${now:-0}" "$fp" > "$stamp" 2>/dev/null
  return 0
}
```

- [ ] **Step 3: Call the writer at the end of main** — find the final render call in the main flow (after `compute_turn_breakdown` and the `printf` that emits the lines). Add, as the last statement before the script ends:

```bash
( _widget_snapshot ) 2>/dev/null || true
```

- [ ] **Step 4: ShellCheck**

Run: `shellcheck -s bash tokenline.sh`
Expected: no output (clean exit 0).

- [ ] **Step 5: Manual smoke test**

```bash
TOKENLINE_WIDGET=1 TOKENLINE_WIDGET_DIR=/tmp/tlw CLAUDE_CONFIG_DIR=/x/trabalho \
  bash tokenline.sh < test/fixtures/payload.json >/dev/null
jq . /tmp/tlw/trabalho.json
```
Expected: valid JSON with `"account_key":"trabalho"`, `rate.five_hour.pct` 95.
(Fixture is created in Task 2 Step 1 — create it first if running standalone.)

- [ ] **Step 6: Commit**

```bash
git add tokenline.sh
git commit -m "feat(widget): opt-in per-account snapshot writer in tokenline.sh"
```

---

## Task 2: Writer test + CI wiring

**Files:**
- Create: `test/fixtures/payload.json`, `test/widget-writer.test.sh`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `tokenline.sh` writer from Task 1.
- Produces: `test/fixtures/payload.json` (reused by later tasks), runnable `bash test/widget-writer.test.sh` (exit 0 = pass).

- [ ] **Step 1: Create the fixture** — `test/fixtures/payload.json`:

```json
{"model":{"display_name":"Opus 4.8"},"session_id":"sess-test","transcript_path":"","context_window":{"used_percentage":62,"context_window_size":200000,"current_usage":{"input_tokens":3400,"output_tokens":1200,"cache_creation_input_tokens":2100,"cache_read_input_tokens":18000}},"rate_limits":{"five_hour":{"used_percentage":95,"resets_at":"2026-06-29T17:05:00Z"},"seven_day":{"used_percentage":88,"resets_at":"2026-07-02T00:00:00Z"}}}
```

- [ ] **Step 2: Write the failing test** — `test/widget-writer.test.sh`:

```bash
#!/usr/bin/env bash
# Tests the opt-in widget snapshot writer in tokenline.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pay="test/fixtures/payload.json"

fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. Opt-out: no flag -> no file written.
rt="$tmp/rt1"; mkdir -p "$rt"
XDG_RUNTIME_DIR="$rt" bash tokenline.sh < "$pay" >/dev/null 2>&1 || true
[ -z "$(ls -A "$tmp"/widget1 2>/dev/null || true)" ] || fail "wrote file without TOKENLINE_WIDGET"

# 2. Opt-in: writes <account>.json with expected fields.
w="$tmp/widget2"
TOKENLINE_WIDGET=1 TOKENLINE_WIDGET_DIR="$w" CLAUDE_CONFIG_DIR=/x/trabalho \
  XDG_RUNTIME_DIR="$tmp/rt2" bash tokenline.sh < "$pay" >/dev/null 2>&1 || true
[ -f "$w/trabalho.json" ] || fail "snapshot not written"
jq -e '.account_key=="trabalho"' "$w/trabalho.json" >/dev/null || fail "bad account_key"
jq -e '.rate.five_hour.pct==95' "$w/trabalho.json" >/dev/null || fail "bad 5h pct"
jq -e '.model=="Opus 4.8"' "$w/trabalho.json" >/dev/null || fail "bad model"
jq -e '.econ.read==18000' "$w/trabalho.json" >/dev/null || fail "bad econ.read"

# 3. Stdout identical with and without the flag.
a="$(XDG_RUNTIME_DIR="$tmp/rt3" bash tokenline.sh < "$pay" 2>/dev/null || true)"
b="$(TOKENLINE_WIDGET=1 TOKENLINE_WIDGET_DIR="$tmp/widget3" CLAUDE_CONFIG_DIR=/x/p \
     XDG_RUNTIME_DIR="$tmp/rt4" bash tokenline.sh < "$pay" 2>/dev/null || true)"
[ "$a" = "$b" ] || fail "stdout differs with TOKENLINE_WIDGET=1"

echo "PASS: widget-writer"
```

- [ ] **Step 3: Run it — expect PASS** (after Task 1 is implemented)

Run: `bash test/widget-writer.test.sh`
Expected: `PASS: widget-writer` (exit 0). If Task 1 is incomplete it FAILs with a `FAIL:` line.

- [ ] **Step 4: Wire into CI** — in `.github/workflows/ci.yml`, in the job that runs ShellCheck, add a step after the shellcheck step:

```yaml
      - name: Widget writer test
        run: bash test/widget-writer.test.sh
```
(Ensure `jq` is available on the runner; ubuntu-latest ships it. Add `sudo apt-get install -y jq` only if the job lacks it.)

- [ ] **Step 5: Commit**

```bash
chmod +x test/widget-writer.test.sh
git add test/fixtures/payload.json test/widget-writer.test.sh .github/workflows/ci.yml
git commit -m "test(widget): cover snapshot writer; run in CI"
```

---

## Task 3: SwiftBar prototype (reader #1)

**Files:**
- Create: `widget/swiftbar/tokenline.5s.sh`, `test/swiftbar.test.sh`, `test/fixtures/widget/trabalho.json`, `test/fixtures/widget/pessoal.json`, `test/fixtures/widget/cliente.json`

**Interfaces:**
- Consumes: snapshot store (`<dir>/*.json`, schema:1) from Task 1.
- Produces: SwiftBar stdout — menu bar line, then `---`, then one dropdown line per account.

- [ ] **Step 1: Create reader fixtures** — three files under `test/fixtures/widget/`:

`trabalho.json`:
```json
{"schema":1,"account_key":"trabalho","session_id":"s1","model":"Opus 4.8","context":{"used_pct":62,"size":200000,"tokens_used":124000},"cache":{"state":"HOT","ttl_label":"5m"},"econ":{"read":18000,"write":2100,"new":3400,"output":1200,"eq":24000},"saving_pct":71,"rate":{"five_hour":{"pct":78,"resets_at":"2026-06-29T17:20:00Z"},"seven_day":{"pct":41,"resets_at":"2026-07-02T00:00:00Z"}},"spend":{"session_tokens":1240000},"updated_at":4102444800}
```
`pessoal.json`: same shape, `account_key":"pessoal"`, `model":"Sonnet 4.6"`, `five_hour.pct":23`, `seven_day.pct":12`, `cache.state":"COLD"`, `saving_pct":64`, `spend.session_tokens":420000`.
`cliente.json`: `account_key":"cliente"`, `model":"Opus 4.8"`, `five_hour.pct":95`, `seven_day.pct":88`, `saving_pct":71`, `spend.session_tokens":3800000`.
(Use `updated_at":4102444800` — year 2100 — so the staleness check never fires in tests.)

- [ ] **Step 2: Write the plugin** — `widget/swiftbar/tokenline.5s.sh`:

```bash
#!/usr/bin/env bash
# <xbar.title>tokenline</xbar.title>
# <xbar.desc>Claude usage across multiple accounts</xbar.desc>
# SwiftBar/xbar plugin: reads tokenline widget snapshots and shows per-account usage.
set -uo pipefail
DIR="${TOKENLINE_WIDGET_DIR:-$HOME/Library/Application Support/tokenline/widget}"

command -v jq >/dev/null 2>&1 || { echo "tokenline ⚠"; echo "---"; echo "jq not found"; exit 0; }

shopt -s nullglob
files=("$DIR"/*.json)
if [ "${#files[@]}" -eq 0 ]; then
  echo "tokenline –"; echo "---"; echo "No accounts yet (run a Claude session with TOKENLINE_WIDGET=1)"
  exit 0
fi

now="$(date +%s)"
color_for() { # $1=pct -> color name
  if   [ "${1%.*}" -ge 86 ] 2>/dev/null; then echo red
  elif [ "${1%.*}" -ge 50 ] 2>/dev/null; then echo orange
  else echo green; fi
}

worst=-1
declare -a lines
for f in "${files[@]}"; do
  read -r key model p5 p7 ctx sv spend st age < <(
    jq -r --argjson now "$now" '
      [ .account_key, .model, (.rate.five_hour.pct|floor), (.rate.seven_day.pct|floor),
        (.context.used_pct|floor), (.saving_pct|floor), .spend.session_tokens,
        .cache.state, ($now - .updated_at) ] | @tsv' "$f" 2>/dev/null
  )
  [ -z "${key:-}" ] && continue
  [ "$p5" -gt "$worst" ] 2>/dev/null && worst="$p5"
  stale=""; [ "${age:-0}" -gt 90 ] 2>/dev/null && stale=" (idle)"
  spk="$(awk -v v="$spend" 'BEGIN{ if(v>=1e6)printf "%.1fM",v/1e6; else if(v>=1e3)printf "%.0fk",v/1e3; else printf "%d",v }')"
  c="$(color_for "$p5")"
  lines+=("$key$stale  5h ${p5}% · 7d ${p7}% · ctx ${ctx}% · save ${sv}% · ${spk} · ${model} | color=$c")
done

[ "$worst" -lt 0 ] && worst=0
echo "${worst}% | color=$(color_for "$worst")"
echo "---"
for l in "${lines[@]}"; do echo "$l"; done
```

- [ ] **Step 3: Write the failing test** — `test/swiftbar.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(TOKENLINE_WIDGET_DIR=test/fixtures/widget bash widget/swiftbar/tokenline.5s.sh)"
fail() { echo "FAIL: $1" >&2; echo "$out" >&2; exit 1; }
# Bar line shows the worst account (95%).
echo "$out" | head -1 | grep -q '95%' || fail "bar not worst account"
# Dropdown has a line per account.
echo "$out" | grep -q '^trabalho ' || fail "missing trabalho"
echo "$out" | grep -q '^cliente ' || fail "missing cliente"
echo "$out" | grep -q 'save 71%' || fail "missing saving"
echo "PASS: swiftbar"
```

- [ ] **Step 4: Run — expect PASS**

Run: `bash test/swiftbar.test.sh`
Expected: `PASS: swiftbar`.

- [ ] **Step 5: Add the plugin test to CI** — append to the CI shellcheck job:

```yaml
      - name: SwiftBar plugin test
        run: bash test/swiftbar.test.sh
```
Also extend the ShellCheck invocation to cover the new scripts, e.g. `shellcheck -s bash tokenline.sh widget/swiftbar/tokenline.5s.sh test/*.sh`.

- [ ] **Step 6: Commit**

```bash
chmod +x widget/swiftbar/tokenline.5s.sh test/swiftbar.test.sh
git add widget/swiftbar test/swiftbar.test.sh test/fixtures/widget .github/workflows/ci.yml
git commit -m "feat(widget): SwiftBar prototype reader + test"
```

---

## Task 4: SwiftPM kit — Snapshot model

**Files:**
- Create: `widget/macos/TokenlineWidgetKit/Package.swift`
- Create: `widget/macos/TokenlineWidgetKit/Sources/TokenlineWidgetKit/Snapshot.swift`
- Create: `widget/macos/TokenlineWidgetKit/Tests/TokenlineWidgetKitTests/SnapshotTests.swift`

**Interfaces:**
- Produces: `public struct Snapshot: Codable, Identifiable, Equatable` with nested `Context`, `Cache`, `Econ`, `Rate`, `Window`, `Spend`; `id == account_key`.

- [ ] **Step 1: Package manifest** — `Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TokenlineWidgetKit",
    platforms: [.macOS(.v13)],
    products: [.library(name: "TokenlineWidgetKit", targets: ["TokenlineWidgetKit"])],
    targets: [
        .target(name: "TokenlineWidgetKit"),
        .testTarget(name: "TokenlineWidgetKitTests", dependencies: ["TokenlineWidgetKit"]),
    ]
)
```

- [ ] **Step 2: Write the failing test** — `Tests/TokenlineWidgetKitTests/SnapshotTests.swift`:

```swift
import XCTest
@testable import TokenlineWidgetKit

final class SnapshotTests: XCTestCase {
    func testDecodesSchema1() throws {
        let json = """
        {"schema":1,"account_key":"trabalho","session_id":"s1","model":"Opus 4.8",
         "context":{"used_pct":62,"size":200000,"tokens_used":124000},
         "cache":{"state":"HOT","ttl_label":"5m"},
         "econ":{"read":18000,"write":2100,"new":3400,"output":1200,"eq":24000},
         "saving_pct":71,
         "rate":{"five_hour":{"pct":78,"resets_at":"x"},"seven_day":{"pct":41,"resets_at":"y"}},
         "spend":{"session_tokens":1240000},"updated_at":4102444800}
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(Snapshot.self, from: json)
        XCTAssertEqual(s.account_key, "trabalho")
        XCTAssertEqual(s.id, "trabalho")
        XCTAssertEqual(s.rate.five_hour.pct, 78, accuracy: 0.01)
        XCTAssertEqual(s.econ.read, 18000)
        XCTAssertEqual(s.spend.session_tokens, 1240000)
    }
}
```

- [ ] **Step 3: Run — expect FAIL** (type not defined)

Run: `cd widget/macos/TokenlineWidgetKit && swift test`
Expected: build failure, `cannot find 'Snapshot' in scope`.

- [ ] **Step 4: Implement the model** — `Sources/TokenlineWidgetKit/Snapshot.swift`:

```swift
import Foundation

public struct Snapshot: Codable, Identifiable, Equatable {
    public struct Context: Codable, Equatable {
        public var used_pct: Double; public var size: Int; public var tokens_used: Int
    }
    public struct Cache: Codable, Equatable {
        public var state: String; public var ttl_label: String
    }
    public struct Econ: Codable, Equatable {
        public var read: Int; public var write: Int; public var new: Int
        public var output: Int; public var eq: Int
    }
    public struct Window: Codable, Equatable {
        public var pct: Double; public var resets_at: String
    }
    public struct Rate: Codable, Equatable {
        public var five_hour: Window; public var seven_day: Window
    }
    public struct Spend: Codable, Equatable { public var session_tokens: Int }

    public var schema: Int
    public var account_key: String
    public var session_id: String
    public var model: String
    public var context: Context
    public var cache: Cache
    public var econ: Econ
    public var saving_pct: Double
    public var rate: Rate
    public var spend: Spend
    public var updated_at: Int

    public var id: String { account_key }
}
```

- [ ] **Step 5: Run — expect PASS**

Run: `swift test`
Expected: `testDecodesSchema1` passes.

- [ ] **Step 6: Commit**

```bash
git add widget/macos/TokenlineWidgetKit
git commit -m "feat(widget): SwiftPM kit with Snapshot Codable model"
```

---

## Task 5: SwiftPM kit — Store (load, select worst, staleness)

**Files:**
- Create: `widget/macos/TokenlineWidgetKit/Sources/TokenlineWidgetKit/Store.swift`
- Create: `widget/macos/TokenlineWidgetKit/Tests/TokenlineWidgetKitTests/StoreTests.swift`

**Interfaces:**
- Consumes: `Snapshot` (Task 4).
- Produces: `public struct AccountView: Identifiable, Equatable { let snapshot; let isStale; var id }`; `public final class Store { init(dir:); func load(now:) -> [AccountView]; func worstFiveHour(_:) -> Double?; static var defaultDir }`.

- [ ] **Step 1: Write the failing test** — `StoreTests.swift`:

```swift
import XCTest
@testable import TokenlineWidgetKit

final class StoreTests: XCTestCase {
    private func writeFixture(_ dir: URL, key: String, p5: Double, updated: Int) throws {
        let j = """
        {"schema":1,"account_key":"\(key)","session_id":"s","model":"Opus 4.8",
         "context":{"used_pct":10,"size":200000,"tokens_used":1},
         "cache":{"state":"HOT","ttl_label":"5m"},
         "econ":{"read":1,"write":1,"new":1,"output":1,"eq":1},"saving_pct":50,
         "rate":{"five_hour":{"pct":\(p5),"resets_at":"x"},"seven_day":{"pct":1,"resets_at":"y"}},
         "spend":{"session_tokens":1},"updated_at":\(updated)}
        """
        try j.data(using: .utf8)!.write(to: dir.appendingPathComponent("\(key).json"))
    }

    func testLoadSortsAndDetectsStaleAndWorst() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1000)
        try writeFixture(dir, key: "a", p5: 30, updated: 1000)      // fresh
        try writeFixture(dir, key: "b", p5: 95, updated: 1000)      // fresh, worst
        try writeFixture(dir, key: "c", p5: 99, updated: 800)       // stale (200s old)
        // a corrupt file must be ignored.
        try "{not json".data(using: .utf8)!.write(to: dir.appendingPathComponent("bad.json"))

        let store = Store(dir: dir)
        let views = store.load(now: now)
        XCTAssertEqual(views.map(\.snapshot.account_key), ["c", "b", "a"]) // sorted by 5h desc
        XCTAssertTrue(views.first { $0.snapshot.account_key == "c" }!.isStale)
        XCTAssertFalse(views.first { $0.snapshot.account_key == "b" }!.isStale)
        XCTAssertEqual(store.worstFiveHour(views), 95) // stale 'c' excluded
    }
}
```

- [ ] **Step 2: Run — expect FAIL** (`cannot find 'Store'`)

Run: `swift test`
Expected: build failure.

- [ ] **Step 3: Implement the store** — `Sources/TokenlineWidgetKit/Store.swift`:

```swift
import Foundation

public struct AccountView: Identifiable, Equatable {
    public let snapshot: Snapshot
    public let isStale: Bool
    public var id: String { snapshot.account_key }
    public init(snapshot: Snapshot, isStale: Bool) {
        self.snapshot = snapshot; self.isStale = isStale
    }
}

public final class Store {
    public static let staleAfter: TimeInterval = 90
    public let dir: URL
    public init(dir: URL) { self.dir = dir }

    public static var defaultDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("tokenline/widget", isDirectory: true)
    }

    /// Loads all <account>.json, tolerating missing/corrupt files. Sorted by 5h pct desc.
    public func load(now: Date = Date()) -> [AccountView] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        let dec = JSONDecoder()
        var out: [AccountView] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let snap = try? dec.decode(Snapshot.self, from: data) else { continue }
            let age = now.timeIntervalSince1970 - Double(snap.updated_at)
            out.append(AccountView(snapshot: snap, isStale: age > Store.staleAfter))
        }
        return out.sorted { $0.snapshot.rate.five_hour.pct > $1.snapshot.rate.five_hour.pct }
    }

    /// Highest 5h pct across non-stale accounts; nil if none fresh.
    public func worstFiveHour(_ views: [AccountView]) -> Double? {
        views.filter { !$0.isStale }.map { $0.snapshot.rate.five_hour.pct }.max()
    }
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `swift test`
Expected: both test classes pass.

- [ ] **Step 5: Commit**

```bash
git add widget/macos/TokenlineWidgetKit
git commit -m "feat(widget): store loader with staleness and worst-account selection"
```

---

## Task 6: MenuBarExtra app (dense dropdown)

**Files:**
- Create: `widget/macos/App/project.yml`, `widget/macos/App/Info.plist`
- Create: `widget/macos/App/Sources/TokenlineWidgetApp.swift`, `WidgetModel.swift`, `DropdownView.swift`, `Format.swift`

**Interfaces:**
- Consumes: `TokenlineWidgetKit` (`Store`, `AccountView`, `Snapshot`).
- Produces: a runnable `.app` showing the worst 5h% in the bar and a dense block per account.

- [ ] **Step 1: XcodeGen project** — `widget/macos/App/project.yml`:

```yaml
name: TokenlineWidget
options:
  bundleIdPrefix: tech.inbrace.tokenline
  deploymentTarget:
    macOS: "13.0"
packages:
  TokenlineWidgetKit:
    path: ../TokenlineWidgetKit
targets:
  TokenlineWidget:
    type: application
    platform: macOS
    sources: [Sources]
    info:
      path: Info.plist
      properties:
        LSUIElement: true
        CFBundleDisplayName: tokenline
    dependencies:
      - package: TokenlineWidgetKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: tech.inbrace.tokenline.widget
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        ENABLE_HARDENED_RUNTIME: YES
        CODE_SIGN_IDENTITY: "-"
```

- [ ] **Step 2: Info.plist** — `widget/macos/App/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>tokenline</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
```

- [ ] **Step 3: Formatting helpers** — `Sources/Format.swift`:

```swift
import SwiftUI
import TokenlineWidgetKit

enum Palette {
    static func color(forPct p: Double) -> Color {
        if p >= 86 { return .red }
        if p >= 50 { return .orange }
        return .green
    }
}

func fmtTokens(_ v: Int) -> String {
    if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1_000_000) }
    if v >= 1_000 { return String(format: "%.0fk", Double(v) / 1_000) }
    return "\(v)"
}
```

- [ ] **Step 4: Model** — `Sources/WidgetModel.swift`:

```swift
import SwiftUI
import Combine
import TokenlineWidgetKit

@MainActor
final class WidgetModel: ObservableObject {
    @Published var accounts: [AccountView] = []
    @Published var barLabel: String = "–"

    private let store: Store
    private var timer: Timer?
    private var source: DispatchSourceFileSystemObject?

    init(store: Store = Store(dir: Store.defaultDir)) {
        self.store = store
        try? FileManager.default.createDirectory(at: store.dir, withIntermediateDirectories: true)
        reload()
        // Poll fallback (also refreshes staleness without a new write).
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        watchDir()
    }

    private func watchDir() {
        let fd = open(store.dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename], queue: .main)
        s.setEventHandler { [weak self] in self?.reload() }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
    }

    func reload() {
        let views = store.load()
        accounts = views
        if let worst = store.worstFiveHour(views) {
            barLabel = "\(Int(worst))%"
        } else {
            barLabel = views.isEmpty ? "–" : "idle"
        }
    }

    deinit { timer?.invalidate(); source?.cancel() }
}
```

- [ ] **Step 5: Dropdown view** — `Sources/DropdownView.swift`:

```swift
import SwiftUI
import TokenlineWidgetKit

struct DropdownView: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONTAS").font(.caption2).foregroundStyle(.secondary)
            if model.accounts.isEmpty {
                Text("Nenhuma conta ainda.\nRode uma sessão Claude com TOKENLINE_WIDGET=1.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(model.accounts) { AccountBlock(view: $0) }
            }
            Divider()
            Button("Sair") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 320)
    }
}

struct AccountBlock: View {
    let view: AccountView
    private var s: Snapshot { view.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(s.account_key).fontWeight(.semibold)
                if view.isStale { Text("idle").font(.caption2).foregroundStyle(.secondary) }
                else { Text(s.cache.state).font(.caption2).foregroundStyle(.orange) }
                Spacer()
                Text(s.model).font(.caption2).foregroundStyle(.secondary)
            }
            ProgressView(value: min(s.rate.five_hour.pct, 100), total: 100)
                .tint(Palette.color(forPct: s.rate.five_hour.pct))
            HStack(spacing: 8) {
                Text("5h \(Int(s.rate.five_hour.pct))%").foregroundStyle(Palette.color(forPct: s.rate.five_hour.pct))
                Text("7d \(Int(s.rate.seven_day.pct))%")
                Text("ctx \(Int(s.context.used_pct))%")
                Text("save \(Int(s.saving_pct))%").foregroundStyle(.green)
                Text(fmtTokens(s.spend.session_tokens))
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .opacity(view.isStale ? 0.5 : 1)
    }
}
```

- [ ] **Step 6: App entry** — `Sources/TokenlineWidgetApp.swift`:

```swift
import SwiftUI

@main
struct TokenlineWidgetApp: App {
    @StateObject private var model = WidgetModel()
    var body: some Scene {
        MenuBarExtra {
            DropdownView(model: model)
        } label: {
            Text(model.barLabel)
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 7: Generate, build, run**

Run:
```bash
brew list xcodegen >/dev/null 2>&1 || brew install xcodegen
cd widget/macos/App && xcodegen generate && \
  xcodebuild -project TokenlineWidget.xcodeproj -scheme TokenlineWidget -configuration Debug build
```
Then launch the built `.app` (path printed by xcodebuild, under DerivedData) and confirm a percentage appears in the menu bar; click it to see the dense per-account list. (Manual verification — no automated UI test.)

- [ ] **Step 8: Commit**

```bash
echo "*.xcodeproj/" >> widget/macos/App/.gitignore
echo "DerivedData/" >> widget/macos/App/.gitignore
git add widget/macos/App
git commit -m "feat(widget): SwiftUI MenuBarExtra app with dense per-account dropdown"
```

---

## Task 7: Labels, settings, launch-at-login

**Files:**
- Create: `widget/macos/App/Sources/Labels.swift`, `SettingsView.swift`
- Modify: `widget/macos/App/Sources/WidgetModel.swift` (apply labels), `DropdownView.swift` (display label + open Settings), `TokenlineWidgetApp.swift` (Settings scene)
- Create: `widget/macos/TokenlineWidgetKit/Tests/TokenlineWidgetKitTests/LabelsTests.swift`
- Create: `widget/macos/TokenlineWidgetKit/Sources/TokenlineWidgetKit/Labels.swift` (move label logic into the testable kit)

**Interfaces:**
- Produces in kit: `public struct Labels { static func load(_ url:) -> [String:String]; func displayName(for key:) }` reading `labels.json` (`{ "trabalho": {"label":"Trabalho","order":0} }`); tolerant of missing file → identity mapping.

- [ ] **Step 1: Failing test for labels (in kit)** — `Tests/TokenlineWidgetKitTests/LabelsTests.swift`:

```swift
import XCTest
@testable import TokenlineWidgetKit

final class LabelsTests: XCTestCase {
    func testMissingFileFallsBackToKey() {
        let url = URL(fileURLWithPath: "/no/such/labels.json")
        let labels = Labels.load(url)
        XCTAssertEqual(labels.displayName(for: "trabalho"), "trabalho")
    }
    func testReadsLabel() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("labels.json")
        try #"{"trabalho":{"label":"Trabalho","order":0}}"#.data(using: .utf8)!.write(to: url)
        let labels = Labels.load(url)
        XCTAssertEqual(labels.displayName(for: "trabalho"), "Trabalho")
        XCTAssertEqual(labels.displayName(for: "pessoal"), "pessoal")
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `cd widget/macos/TokenlineWidgetKit && swift test`
Expected: `cannot find 'Labels'`.

- [ ] **Step 3: Implement labels in kit** — `Sources/TokenlineWidgetKit/Labels.swift`:

```swift
import Foundation

public struct Labels {
    public struct Entry: Codable, Equatable { public var label: String; public var order: Int? }
    private let map: [String: Entry]
    public init(map: [String: Entry] = [:]) { self.map = map }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("tokenline/labels.json")
    }

    public static func load(_ url: URL = defaultURL) -> Labels {
        guard let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return Labels() }
        return Labels(map: map)
    }

    public func displayName(for key: String) -> String { map[key]?.label ?? key }
    public func order(for key: String) -> Int { map[key]?.order ?? Int.max }
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `swift test`
Expected: all kit tests pass.

- [ ] **Step 5: Apply labels in the app** — in `WidgetModel.swift`, add `@Published var labels = Labels.load()`; reload it in `reload()`; in `AccountBlock` change `Text(s.account_key)` to `Text(model.labels.displayName(for: s.account_key))` (pass `labels` or the model into the block). Keep sort by 5h desc as primary (label order is a future refinement).

- [ ] **Step 6: Launch-at-login + Settings** — `Sources/SettingsView.swift`:

```swift
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    var body: some View {
        Form {
            Toggle("Iniciar no login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do { on ? try SMAppService.mainApp.register()
                            : try SMAppService.mainApp.unregister() }
                    catch { launchAtLogin = (SMAppService.mainApp.status == .enabled) }
                }
            Text("Contas e rótulos: edite ~/Library/Application Support/tokenline/labels.json")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(width: 360)
    }
}
```
In `TokenlineWidgetApp.swift`, add a `Settings { SettingsView() }` scene, and in `DropdownView` add `SettingsLink { Text("Ajustes…") }` (macOS 14+) or a button calling `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` for macOS 13.

- [ ] **Step 7: Rebuild and verify**

Run: `cd widget/macos/App && xcodegen generate && xcodebuild -project TokenlineWidget.xcodeproj -scheme TokenlineWidget build`
Then launch, create `~/Library/Application Support/tokenline/labels.json` with a label, confirm the dropdown shows the friendly name; toggle "Iniciar no login" and confirm via `SMAppService` status.

- [ ] **Step 8: Commit**

```bash
git add widget/macos
git commit -m "feat(widget): friendly labels, settings, launch-at-login"
```

---

## Task 8: Docs

**Files:**
- Create: `widget/README.md`
- Modify: `README.md` (link the widget), `AGENTS.md` (note the `widget/` tooling + opt-in env var)

- [ ] **Step 1: Write `widget/README.md`** — cover: enabling the writer (`export TOKENLINE_WIDGET=1` per account shell, with `CLAUDE_CONFIG_DIR` set), the store path/schema, the SwiftBar quick path (drop the plugin into SwiftBar's plugin dir), and the native build (`xcodegen generate && xcodebuild`).

- [ ] **Step 2: Link from root `README.md`** — add a "macOS multi-account widget" subsection pointing to `widget/README.md`, noting it's opt-in and macOS-only.

- [ ] **Step 3: Note in `AGENTS.md`** — under the npm-installer/tooling discussion, add that `widget/` holds the macOS reader tooling and that `TOKENLINE_WIDGET=1` is the only behavior toggle in the hot path (writes derived metrics only, never the raw payload).

- [ ] **Step 4: Commit**

```bash
git add widget/README.md README.md AGENTS.md
git commit -m "docs(widget): document opt-in writer, SwiftBar plugin, and native app"
```

---

## Self-Review notes

- **Spec coverage:** writer (T1), store/persistence + constraint reconciliation (T1/T7 docs), account key (T1), B-dense dropdown (T6), worst-5h bar (T5/T6), staleness (T5/T6), labels (T7), launch-at-login (T7), SwiftBar validation reader (T3), tokens-only spend (T1), tests (T2/T3/T4/T5/T7), CI (T2/T3). Covered.
- **Out of scope (per spec):** `$` cost, "today"/daily history, notifications, non-macOS app — intentionally excluded.
- **Type consistency:** `Snapshot`/`AccountView`/`Store`/`Labels` signatures are defined once (T4/T5/T7) and reused; `worstFiveHour`, `displayName(for:)`, `load(now:)` names match across tasks.
