import Foundation

/// Public Anthropic API list prices, USD per million tokens (cached from Anthropic's docs, 2026-10-06).
/// Used only to turn local Claude Code logs into an "API-equivalent" dollar figure. Subscription plans
/// (Pro, Max, Team) are not billed per token, so this is what the usage would cost at API prices, not a bill.
enum ClaudePricing {
    struct Price {
        let input: Double
        let output: Double
        let cacheRead: Double
    }

    /// Longest matching prefix wins, so dated IDs like `claude-haiku-4-5-20251001` resolve correctly.
    private static let table: [(prefix: String, price: Price)] = [
        ("claude-fable-5", Price(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-mythos-5", Price(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-opus-5-5", Price(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-8", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-7", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-6", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-5", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4", Price(input: 15, output: 75, cacheRead: 1.50)),     // Opus 4 / 4.1
        ("claude-sonnet-5", Price(input: 2, output: 10, cacheRead: 0.20)),    // Sonnet 5 / 5.5
        ("claude-sonnet-4", Price(input: 3, output: 15, cacheRead: 0.30)),    // Sonnet 4 / 4.5 / 4.6
        ("claude-3-7-sonnet", Price(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-haiku-5", Price(input: 0.10, output: 0.50, cacheRead: 0.01)),  // prompts up to 100K tokens
        ("claude-haiku-4-5", Price(input: 1, output: 5, cacheRead: 0.10)),
        ("claude-3-5-haiku", Price(input: 0.80, output: 4, cacheRead: 0.08))
    ].sorted { $0.prefix.count > $1.prefix.count }

    /// Unknown or future models fall back to the closest family so the estimate is never silently zero.
    private static func price(for model: String) -> Price {
        let id = model.lowercased()
        if let match = table.first(where: { id.hasPrefix($0.prefix) }) { return match.price }
        if id.contains("opus") { return Price(input: 5, output: 25, cacheRead: 0.50) }
        if id.contains("haiku") { return Price(input: 1, output: 5, cacheRead: 0.10) }
        return Price(input: 3, output: 15, cacheRead: 0.30)   // sonnet-class default
    }

    /// Cache writes cost 1.25x input for the 5-minute TTL and 2x for the 1-hour TTL.
    static func cost(model: String, input: Int, output: Int, cacheRead: Int, cacheWrite5m: Int, cacheWrite1h: Int) -> Double {
        let p = price(for: model)
        let million = 1_000_000.0
        return (Double(input) * p.input
                + Double(output) * p.output
                + Double(cacheRead) * p.cacheRead
                + Double(cacheWrite5m) * p.input * 1.25
                + Double(cacheWrite1h) * p.input * 2) / million
    }
}

/// "$1.84", "$52", "$1.2K": compact money for tight spots.
func money(_ value: Double) -> String {
    switch value {
    case 1000...: return String(format: "$%.1fK", value / 1000)
    case 100...: return String(format: "$%.0f", value)
    case 10...: return String(format: "$%.1f", value)
    default: return String(format: "$%.2f", value)
    }
}
