import XCTest
@testable import TokenlineWidgetKit

final class StoreTests: XCTestCase {
    private func write(_ dir: URL, account: String, session: String,
                       p5: Double, activeAt: Int, updated: Int) throws {
        let j = """
        {"schema":1,"account_key":"\(account)","session_id":"\(session)","model":"Opus 4.8",
         "context":{"used_pct":10,"size":200000,"tokens_used":1},
         "cache":{"state":"HOT","ttl_label":"5m"},
         "econ":{"read":1,"write":1,"new":1,"output":1,"eq":1},"saving_pct":50,
         "rate":{"five_hour":{"pct":\(p5),"resets_at":"x"},"seven_day":{"pct":1,"resets_at":"y"}},
         "spend":{"session_tokens":1},"updated_at":\(updated),"active_at":\(activeAt)}
        """
        try j.data(using: .utf8)!.write(to: dir.appendingPathComponent("\(account)__\(session).json"))
    }

    func testGroupsSessionsByAccount() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1000)

        // Account 'a': two live sessions. s1 is more recently active and reads 30%;
        // s2 is an older-active session with a stale-cached 77%.
        try write(dir, account: "a", session: "s1", p5: 30, activeAt: 1000, updated: 1000)
        try write(dir, account: "a", session: "s2", p5: 77, activeAt: 950, updated: 1000)
        // Account 'b': one live session, the most-constrained.
        try write(dir, account: "b", session: "s1", p5: 95, activeAt: 1000, updated: 1000)
        // Account 'c': one session, stale (no live -> last-known shown).
        try write(dir, account: "c", session: "s1", p5: 99, activeAt: 900, updated: 900)
        // Corrupt file must be ignored.
        try "{not json".data(using: .utf8)!.write(to: dir.appendingPathComponent("bad.json"))

        let store = Store(dir: dir)
        let groups = store.load(now: now)

        XCTAssertEqual(groups.map(\.key), ["c", "b", "a"])          // sorted by 5h desc

        let a = groups.first { $0.key == "a" }!
        XCTAssertEqual(a.sessions.count, 2)
        XCTAssertEqual(a.liveCount, 2)
        XCTAssertFalse(a.isStale)
        XCTAssertEqual(a.fiveHour.pct, 30, accuracy: 0.01)          // active session's reading wins
        XCTAssertEqual(a.sessions.first!.snapshot.session_id, "s1") // most-active first
        XCTAssertTrue(a.sessions.first!.isActive)
        XCTAssertFalse(a.sessions.last!.isActive)

        let c = groups.first { $0.key == "c" }!
        XCTAssertTrue(c.isStale)
        XCTAssertEqual(c.liveCount, 0)

        XCTAssertEqual(store.worstFiveHour(groups), 95)             // stale 'c' excluded
    }
}
