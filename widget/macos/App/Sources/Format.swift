import SwiftUI

/// Usage severity drives a focused splash of color — the bullet, the bar fill,
/// and the 5h value. Everything else stays neutral so it reads calm, not loud.
enum Usage {
    static func color(_ p: Double) -> Color {
        if p >= 86 { return Color(red: 1.00, green: 0.27, blue: 0.23) } // red
        if p >= 50 { return Color(red: 1.00, green: 0.58, blue: 0.00) } // amber
        return Color(red: 0.20, green: 0.78, blue: 0.35)                // green
    }

    static let track = Color.primary.opacity(0.10)
}

func fmtTokens(_ v: Int) -> String {
    // One decimal, but drop a trailing ".0" so round values stay clean
    // (124000 → "124k", 448800 → "448.8k", 1_000_000 → "1M").
    func unit(_ d: Double, _ suffix: String) -> String {
        let s = String(format: "%.1f", d)
        return (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + suffix
    }
    if v >= 1_000_000 { return unit(Double(v) / 1_000_000, "M") }
    if v >= 1_000 { return unit(Double(v) / 1_000, "k") }
    return "\(v)"
}
