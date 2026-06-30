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
