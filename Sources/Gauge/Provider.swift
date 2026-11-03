import AppKit

/// Everything the UI needs to draw one AI service. Adding a service means producing one of these
/// in `AppModel.cards`; the card, the notch badge and the menu bar pick it up automatically.
struct ProviderCard {
    let id: String
    let glyph: String
    let name: String
    let tint: NSColor
    /// Short text for the menu bar and the notch badge.
    let barText: String
    /// Right-hand status on the card row.
    let cardText: String
    /// 0...1 of what is left; nil draws an empty bar.
    let progress: Double?
    /// Rows for the hover breakdown (name, value).
    let lines: [(name: String, value: String)]
}

enum Palette {
    static let background = NSColor.black
    static let muted = NSColor(calibratedWhite: 0.66, alpha: 1)
    static let orange = NSColor(calibratedRed: 0.92, green: 0.64, blue: 0.45, alpha: 1)
    static let blue = NSColor(calibratedRed: 0.59, green: 0.74, blue: 0.98, alpha: 1)
    static let green = NSColor(calibratedRed: 0.55, green: 0.82, blue: 0.58, alpha: 1)
}

enum Layout {
    static let cardWidth: CGFloat = 300
    /// Heading + footer + insets, plus one 54 pt block per provider.
    static func cardSize(rows: Int) -> NSSize {
        NSSize(width: cardWidth, height: 72 + 54 * CGFloat(max(1, rows)))
    }
}
