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
