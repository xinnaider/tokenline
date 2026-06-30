import Foundation

/// One live session within an account (per-session snapshot + whether it's the
/// most-recently-active one).
public struct SessionInfo: Identifiable, Equatable {
    public let snapshot: Snapshot
    public let isActive: Bool
    public var id: String { snapshot.session_id }
    public init(snapshot: Snapshot, isActive: Bool) {
        self.snapshot = snapshot; self.isActive = isActive
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
    /// A session whose snapshot hasn't been rewritten within this window is
    /// treated as gone (its window closed); a live statusline rewrites ~1/sec.
    public static let sessionTimeout: TimeInterval = 30
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
        func isLive(_ s: Snapshot) -> Bool {
            nowEpoch - Double(s.updated_at) <= Store.sessionTimeout
        }

        var groups: [AccountGroup] = []
        for (key, snaps) in byAccount {
            let live = snaps.filter(isLive)
            let stale = live.isEmpty
            // Show live sessions; if none are live, fall back to last-known.
            let chosen = (stale ? snaps : live)
                .sorted { $0.activity > $1.activity }   // most-recently-active first
            guard let active = chosen.first else { continue }
            let sessions = chosen.map { SessionInfo(snapshot: $0, isActive: $0.id == active.id) }
            groups.append(AccountGroup(
                key: key,
                fiveHour: active.rate.five_hour,   // freshest account-wide reading
                sevenDay: active.rate.seven_day,
                sessions: sessions,
                liveCount: live.count,
                isStale: stale))
        }
        return groups.sorted { $0.fiveHour.pct > $1.fiveHour.pct }
    }

    /// Highest 5h pct across non-stale accounts; nil if none fresh.
    public func worstFiveHour(_ groups: [AccountGroup]) -> Double? {
        groups.filter { !$0.isStale }.map { $0.fiveHour.pct }.max()
    }
}
