import XCTest
@testable import TokenlineWidgetKit

final class LabelsTests: XCTestCase {
    func testMissingFilePrettifiesKey() {
        let url = URL(fileURLWithPath: "/no/such/labels.json")
        let labels = Labels.load(url)
        XCTAssertEqual(labels.displayName(for: "claude-pessoal"), "Claude Pessoal")
        XCTAssertEqual(labels.displayName(for: "trabalho"), "Trabalho")
    }
    func testExplicitLabelWinsOverPrettify() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("labels.json")
        try #"{"claude-pessoal":{"label":"Conta X","order":0}}"#.data(using: .utf8)!.write(to: url)
        let labels = Labels.load(url)
        XCTAssertEqual(labels.displayName(for: "claude-pessoal"), "Conta X")   // explicit preserved
        XCTAssertEqual(labels.displayName(for: "claude-nepen"), "Claude Nepen") // fallback prettified
    }
    func testPrettify() {
        XCTAssertEqual(Labels.prettify("claude-pessoal"), "Claude Pessoal")
        XCTAssertEqual(Labels.prettify("claude_nepen"), "Claude Nepen")
        XCTAssertEqual(Labels.prettify("claude"), "Claude")
        XCTAssertEqual(Labels.prettify(""), "")
    }
    func testWriteRoundTrips() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("labels.json")
        try Labels.write(["claude-pessoal": Labels.Entry(label: "Conta X", order: 0)], to: url)
        let labels = Labels.load(url)
        XCTAssertEqual(labels.displayName(for: "claude-pessoal"), "Conta X")
        XCTAssertEqual(labels.entries["claude-pessoal"]?.label, "Conta X")
    }
}
