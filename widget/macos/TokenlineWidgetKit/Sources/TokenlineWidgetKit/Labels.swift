import Foundation

public struct Labels {
    public struct Entry: Codable, Equatable {
        public var label: String
        public var order: Int?
        public init(label: String, order: Int? = nil) { self.label = label; self.order = order }
    }
    private let map: [String: Entry]
    public init(map: [String: Entry] = [:]) { self.map = map }

    /// The raw alias map, for an editor to read and round-trip.
    public var entries: [String: Entry] { map }

    /// Persist an alias map to labels.json (creating the dir if needed).
    public static func write(_ map: [String: Entry], to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(map).write(to: url)
    }

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

    /// Explicit label when set in labels.json; otherwise the account key
    /// prettified ("claude-pessoal" → "Claude Pessoal").
    public func displayName(for key: String) -> String {
        map[key]?.label ?? Labels.prettify(key)
    }

    public func order(for key: String) -> Int { map[key]?.order ?? Int.max }

    /// Splits on `-`, `_`, and spaces, then capitalizes each word's first letter.
    public static func prettify(_ key: String) -> String {
        key.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
