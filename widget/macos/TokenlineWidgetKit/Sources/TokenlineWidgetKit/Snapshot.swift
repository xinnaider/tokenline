import Foundation

public struct Snapshot: Codable, Identifiable, Equatable {
    public struct Context: Codable, Equatable {
        public var used_pct: Double; public var size: Int; public var tokens_used: Int
    }
    public struct Cache: Codable, Equatable {
        public var state: String; public var ttl_label: String
    }
    public struct Econ: Codable, Equatable {
        public var read: Int; public var write: Int; public var new: Int
        public var output: Int; public var eq: Int
    }
    public struct Window: Codable, Equatable {
        public var pct: Double; public var resets_at: String
    }
    public struct Rate: Codable, Equatable {
        public var five_hour: Window; public var seven_day: Window
    }
    public struct Spend: Codable, Equatable { public var session_tokens: Int }

    public var schema: Int
    public var account_key: String
    public var session_id: String
    public var model: String
    public var context: Context
    public var cache: Cache
    public var econ: Econ
    public var saving_pct: Double
    public var rate: Rate
    public var spend: Spend
    public var updated_at: Int
    /// Last-turn timestamp; absent on snapshots written before this field existed.
    public var active_at: Int?

    public var id: String { session_id }

    /// Recency of this session's last turn (falls back to the write time).
    public var activity: Int { active_at ?? updated_at }
}
