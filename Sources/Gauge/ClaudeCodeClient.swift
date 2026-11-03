import Foundation

struct ClaudeLocalUsage: Equatable {
    /// Tokens used in the current 5-hour session block (nil when no block is active).
    let sessionTokens: Int?
    let sessionResetsAt: Date?
    /// Tokens used in the last 7 days.
    let weeklyTokens: Int
}

/// Estimates Claude Code usage from its local transcript logs (`~/.claude/projects/**/*.jsonl`).
/// Reads files only on this Mac, never touches the network. Counts input + output + cache-creation
/// tokens (cache reads are excluded). Subscription limits are not public, so this is token usage, not a percentage.
///
/// Incremental: remembers how far each file was read, so refreshes only parse newly appended lines.
/// Not thread-safe; call from one queue at a time.
final class ClaudeCodeClient: @unchecked Sendable {
    private struct Record { var date: Date; var tokens: Int }

    private static let sessionLength: TimeInterval = 5 * 3600
    private static let weekLength: TimeInterval = 7 * 86400

    private var offsets: [String: UInt64] = [:]
    private var records: [String: Record] = [:]
    private let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoPlain = ISO8601DateFormatter()

    private var roots: [URL] {
        var dirs: [URL] = []
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            for part in custom.split(separator: ",") { dirs.append(URL(fileURLWithPath: String(part)).appendingPathComponent("projects")) }
        }
        let home = URL(fileURLWithPath: NSHomeDirectory())
        dirs.append(home.appendingPathComponent(".claude/projects"))
        dirs.append(home.appendingPathComponent(".config/claude/projects"))
        return dirs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Returns nil when no Claude Code logs exist on this Mac.
    func fetch(now: Date = Date()) -> ClaudeLocalUsage? {
        let roots = roots
        guard !roots.isEmpty else { return nil }
        let cutoff = now.addingTimeInterval(-Self.weekLength)
        for root in roots { scan(root, cutoff: cutoff) }
        records = records.filter { $0.value.date >= cutoff }

        let sorted = records.values.sorted { $0.date < $1.date }
        // Sessions: a block starts at the first message and lasts 5 hours; the next message after that starts a new one.
        var blockStart: Date?
        var blockTokens = 0
        for record in sorted {
            if let start = blockStart, record.date < start.addingTimeInterval(Self.sessionLength) {
                blockTokens += record.tokens
            } else {
                blockStart = record.date
                blockTokens = record.tokens
            }
        }
        var session: Int?
        var resets: Date?
        if let start = blockStart, start.addingTimeInterval(Self.sessionLength) > now {
            session = blockTokens
            resets = start.addingTimeInterval(Self.sessionLength)
        }
        return ClaudeLocalUsage(sessionTokens: session, sessionResetsAt: resets,
                                weeklyTokens: sorted.reduce(0) { $0 + $1.tokens })
    }

    private func scan(_ root: URL, cutoff: Date) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true, let modified = values?.contentModificationDate, modified >= cutoff else { continue }
            read(url, cutoff: cutoff)
        }
    }

    private func read(_ url: URL, cutoff: Date) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        var offset = offsets[url.path] ?? 0
        if size < offset { offset = 0 }   // file was rewritten
        guard size > offset else { return }
        try? handle.seek(toOffset: offset)

        var carry = Data()
        let newline = UInt8(ascii: "\n")
        while true {
            let chunk = (try? handle.read(upToCount: 8 << 20)) ?? Data()
            if chunk.isEmpty { break }
            carry.append(chunk)
            guard let lastNewline = carry.lastIndex(of: newline) else { continue }
            let complete = carry[carry.startIndex...lastNewline]
            offset += UInt64(complete.count)
            for line in complete.split(separator: newline, omittingEmptySubsequences: true) { parse(line, cutoff: cutoff) }
            carry = Data(carry[(lastNewline + 1)...])
        }
        offsets[url.path] = offset
    }

    private static let marker = Data("\"output_tokens\"".utf8)

    private func parse(_ line: Data, cutoff: Date) {
        guard line.range(of: Self.marker) != nil,   // cheap pre-filter before JSON parsing
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let stamp = object["timestamp"] as? String,
              let date = isoFractional.date(from: stamp) ?? isoPlain.date(from: stamp),
              date >= cutoff else { return }
        func value(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        let tokens = value("input_tokens") + value("output_tokens") + value("cache_creation_input_tokens")
        // A streamed message is logged several times with growing usage; keep the largest per message.
        let id = (message["id"] as? String) ?? (object["uuid"] as? String) ?? stamp
        if let existing = records[id], existing.tokens >= tokens { return }
        records[id] = Record(date: date, tokens: tokens)
    }
}

func compactTokens(_ value: Int) -> String {
    switch value {
    case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
    case 1_000...: return "\(Int((Double(value) / 1_000).rounded()))K"
    default: return "\(value)"
    }
}
