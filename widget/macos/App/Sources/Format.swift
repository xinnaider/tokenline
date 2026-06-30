import SwiftUI
import TokenlineWidgetKit

enum Palette {
    static func color(forPct p: Double) -> Color {
        if p >= 86 { return .red }
        if p >= 50 { return .orange }
        return .green
    }
}

func fmtTokens(_ v: Int) -> String {
    if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1_000_000) }
    if v >= 1_000 { return String(format: "%.0fk", Double(v) / 1_000) }
    return "\(v)"
}
