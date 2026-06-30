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
