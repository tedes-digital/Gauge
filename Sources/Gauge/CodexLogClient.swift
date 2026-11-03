import Foundation

/// Per-project Codex token usage from local session logs (`~/.codex/sessions/**/*.jsonl`).
/// Counts uncached input + output tokens. The server-side rate limits stay the source of truth for the
/// percentage; this only answers "where did it go". Incremental and local-only, like `ClaudeCodeClient`.
/// Not thread-safe; call from one queue at a time.
final class CodexLogClient: @unchecked Sendable {
    private struct Record { var date: Date; var tokens: Int; var project: String }
    private struct FileState { var offset: UInt64 = 0; var project = "Unknown"; var lastTotal = 0 }

    private static let keep: TimeInterval = 7 * 86400
    private static let tokenMarker = Data("\"token_count\"".utf8)
    private static let metaMarker = Data("\"session_meta\"".utf8)

    private var files: [String: FileState] = [:]
    private var records: [Record] = []
    private let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoPlain = ISO8601DateFormatter()

    private var root: URL {
        let base = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
        return base.appendingPathComponent("sessions")
    }

    /// Tokens per project since `since`, largest first. Empty when there are no Codex logs.
    func projects(since: Date, now: Date = Date()) -> [ProjectUsage] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let cutoff = now.addingTimeInterval(-Self.keep)
        scan(cutoff: cutoff)
        records.removeAll { $0.date < cutoff }
        let grouped = Dictionary(grouping: records.filter { $0.date >= since }, by: \.project)
        return grouped.map { ProjectUsage(name: $0.key, tokens: $0.value.reduce(0) { $0 + $1.tokens }) }
            .filter { $0.tokens > 0 }
            .sorted { $0.tokens > $1.tokens }
    }

    private func scan(cutoff: Date) {
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
        var state = files[url.path] ?? FileState()
        if size < state.offset { state = FileState() }   // file was rewritten
        guard size > state.offset else { return }
        try? handle.seek(toOffset: state.offset)

        var carry = Data()
        let newline = UInt8(ascii: "\n")
        while true {
            let chunk = (try? handle.read(upToCount: 8 << 20)) ?? Data()
            if chunk.isEmpty { break }
            carry.append(chunk)
            guard let lastNewline = carry.lastIndex(of: newline) else { continue }
            let complete = carry[carry.startIndex...lastNewline]
            state.offset += UInt64(complete.count)
            for line in complete.split(separator: newline, omittingEmptySubsequences: true) { parse(line, state: &state, cutoff: cutoff) }
            carry = Data(carry[(lastNewline + 1)...])
        }
        files[url.path] = state
    }

    private func parse(_ line: Data, state: inout FileState, cutoff: Date) {
        if state.project == "Unknown", line.range(of: Self.metaMarker) != nil {
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               let payload = object["payload"] as? [String: Any], let cwd = payload["cwd"] as? String {
                state.project = Self.projectName(cwd)
            }
            return
        }
        guard line.range(of: Self.tokenMarker) != nil,   // cheap pre-filter before JSON parsing
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any], payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let total = info["total_token_usage"] as? [String: Any] else { return }
        func value(_ key: String) -> Int { (total[key] as? NSNumber)?.intValue ?? 0 }
        // Cumulative per session: record only the growth, which also ignores repeated events.
        let cumulative = max(0, value("input_tokens") - value("cached_input_tokens")) + value("output_tokens")
        let delta = cumulative - state.lastTotal
        guard delta > 0 else { return }
        state.lastTotal = cumulative
        guard let stamp = object["timestamp"] as? String,
              let date = isoFractional.date(from: stamp) ?? isoPlain.date(from: stamp), date >= cutoff else { return }
        records.append(Record(date: date, tokens: delta, project: state.project))
    }

    private static func projectName(_ cwd: String) -> String {
        // ChatGPT projects live in opaque hash folders; group them under one readable name.
        if cwd.contains("/.chatgpt-projects/") { return "ChatGPT projects" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "/" : name
    }
}
