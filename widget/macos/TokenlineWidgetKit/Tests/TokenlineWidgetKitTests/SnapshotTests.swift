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
        XCTAssertEqual(s.id, "s1")                    // identity is the session
        XCTAssertEqual(s.activity, s.updated_at)      // no active_at -> falls back
        XCTAssertEqual(s.rate.five_hour.pct, 78, accuracy: 0.01)
        XCTAssertEqual(s.econ.read, 18000)
        XCTAssertEqual(s.spend.session_tokens, 1240000)
    }
}
