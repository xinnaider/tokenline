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

extension String {
    /// Uppercases only the first character, preserving the rest
    /// ("trabalho" → "Trabalho", "Cliente X" → "Cliente X").
    var capitalizedFirst: String {
        guard let f = first else { return self }
        return f.uppercased() + dropFirst()
    }
}

func fmtTokens(_ v: Int) -> String {
    if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1_000_000) }
    if v >= 1_000 { return String(format: "%.0fk", Double(v) / 1_000) }
    return "\(v)"
}
