import AppKit
import TokenlineWidgetKit

extension Usage {
    /// AppKit twin of `color(_:)` for drawing into the menu bar image.
    static func nsColor(_ p: Double) -> NSColor {
        if p >= 86 { return NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1) } // red
        if p >= 50 { return NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1) } // amber
        return NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)                // green
    }
}

/// Renders one colored vertical bar per account (height = 5h load) as a
/// NON-template NSImage, so the menu bar shows real color instead of being
/// tinted monochrome. Stale accounts draw in the neutral track color.
func menuBarBars(_ groups: [AccountGroup], height: CGFloat = 13) -> NSImage? {
    guard !groups.isEmpty else { return nil }
    let barW: CGFloat = 3, gap: CGFloat = 2
    let n = CGFloat(groups.count)
    let size = NSSize(width: n * barW + max(0, n - 1) * gap, height: height)

    let image = NSImage(size: size, flipped: false) { rect in
        for (i, v) in groups.enumerated() {
            let p = max(0, min(100, v.fiveHour.pct))
            let x = CGFloat(i) * (barW + gap)

            // Faint full-height track so the unused headroom is visible.
            NSColor.tertiaryLabelColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: barW, height: rect.height),
                         xRadius: 1.2, yRadius: 1.2).fill()

            // Colored fill up to the 5h percentage.
            let h = max(2, rect.height * CGFloat(p) / 100)
            (v.isStale ? NSColor.quaternaryLabelColor : Usage.nsColor(p)).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: barW, height: h),
                         xRadius: 1.2, yRadius: 1.2).fill()
        }
        return true
    }
    image.isTemplate = false
    return image
}
