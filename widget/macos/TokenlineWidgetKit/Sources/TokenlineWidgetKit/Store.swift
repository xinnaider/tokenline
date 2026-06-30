import Foundation

/// Traffic-light state of a session, by how recently it took a turn.
public enum SessionState: Equatable { case active, idle }

/// One live session within an account (per-session snapshot, its traffic-light
/// state, and whether it's the account's most-recently-active session).
public struct SessionInfo: Identifiable, Equatable {
    public let snapshot: Snapshot
    public let state: SessionState
    public let isActive: Bool
    public var id: String { snapshot.session_id }
    public init(snapshot: Snapshot, state: SessionState, isActive: Bool) {
        self.snapshot = snapshot; self.state = state; self.isActive = isActive
    }
}

/// All sessions of one account, plus the account-wide rate limits (taken from
/// the most-recently-active session, whose reading is freshest).
public struct AccountGroup: Identifiable, Equatable {
    public let key: String
    public let fiveHour: Snapshot.Window
    public let sevenDay: Snapshot.Window
    public let sessions: [SessionInfo]   // active session first
    public let liveCount: Int
    public let isStale: Bool             // no live session right now
    public var id: String { key }

    public init(key: String, fiveHour: Snapshot.Window, sevenDay: Snapshot.Window,
                sessions: [SessionInfo], liveCount: Int, isStale: Bool) {
        self.key = key; self.fiveHour = fiveHour; self.sevenDay = sevenDay
        self.sessions = sessions; self.liveCount = liveCount; self.isStale = isStale
    }
}

public final class Store {
    /// A session is shown only if its window is still ticking (rewrote its file
    /// within `windowOpen`) AND it had a turn within `recentlyUsed`. An open but
    /// long-idle window (e.g. untouched for an hour) is hidden.
    public static let windowOpen: TimeInterval = 20
    public static let recentlyUsed: TimeInterval = 900   // 15 min
    public static let activeWithin: TimeInterval = 60    // green ≤ 1 min, amber beyond
    public let dir: URL
    public init(dir: URL) { self.dir = dir }

    public static var defaultDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("tokenline/widget", isDirectory: true)
    }

    /// Loads every per-session snapshot, tolerating missing/corrupt files, and
    /// groups them by account. Accounts sorted by 5h pct desc (most-constrained
    /// first); within an account the most-recently-active session is first.
    public func load(now: Date = Date()) -> [AccountGroup] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        let dec = JSONDecoder()
        var byAccount: [String: [Snapshot]] = [:]
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let snap = try? dec.decode(Snapshot.self, from: data) else { continue }
            byAccount[snap.account_key, default: []].append(snap)
        }

        let nowEpoch = now.timeIntervalSince1970
        func isShown(_ s: Snapshot) -> Bool {
            nowEpoch - Double(s.updated_at) <= Store.windowOpen
                && nowEpoch - Double(s.activity) <= Store.recentlyUsed
        }

        var groups: [AccountGroup] = []
        for (key, snaps) in byAccount {
            let shown = snaps.filter(isShown).sorted { $0.activity > $1.activity }
            if let active = shown.first {
                let sessions = shown.map { snap -> SessionInfo in
                    let st: SessionState =
                        nowEpoch - Double(snap.activity) <= Store.activeWithin ? .active : .idle
                    return SessionInfo(snapshot: snap, state: st, isActive: snap.id == active.id)
                }
                groups.append(AccountGroup(
                    key: key,
                    fiveHour: active.rate.five_hour,   // freshest account-wide reading
                    sevenDay: active.rate.seven_day,
                    sessions: sessions,
                    liveCount: shown.count,
                    isStale: false))
            } else if let last = snaps.max(by: { $0.updated_at < $1.updated_at }) {
                // No session is active right now: show the account greyed, with
                // its last-known limits and no session rows.
                groups.append(AccountGroup(
                    key: key,
                    fiveHour: last.rate.five_hour,
                    sevenDay: last.rate.seven_day,
                    sessions: [],
                    liveCount: 0,
                    isStale: true))
            }
        }
        return groups.sorted { $0.fiveHour.pct > $1.fiveHour.pct }
    }

    /// Highest 5h pct across non-stale accounts; nil if none fresh.
    public func worstFiveHour(_ groups: [AccountGroup]) -> Double? {
        groups.filter { !$0.isStale }.map { $0.fiveHour.pct }.max()
    }
}
