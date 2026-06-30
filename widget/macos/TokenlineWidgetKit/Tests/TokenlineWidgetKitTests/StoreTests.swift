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
