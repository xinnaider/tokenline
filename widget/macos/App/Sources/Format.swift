import SwiftUI

/// Severity scale shared by the menu bar glyph and the dropdown.
enum Usage {
    static func color(_ p: Double) -> Color {
        if p >= 86 { return Color(red: 1.00, green: 0.27, blue: 0.23) } // red
        if p >= 50 { return Color(red: 1.00, green: 0.62, blue: 0.04) } // amber
        return Color(red: 0.18, green: 0.80, blue: 0.34)                // green
    }

    /// SF Symbol whose fill tracks severity — gives the menu bar item a shape,
    /// not just a number, so it survives a crowded bar / the notch.
    static func gauge(_ p: Double) -> String {
        if p >= 86 { return "gauge.high" }
        if p >= 50 { return "gauge.medium" }
        return "gauge.low"
    }
}

func fmtTokens(_ v: Int) -> String {
    if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1_000_000) }
    if v >= 1_000 { return String(format: "%.0fk", Double(v) / 1_000) }
    return "\(v)"
}
