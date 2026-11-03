import Foundation

struct ProjectAmount: Equatable {
    let name: String
    let amount: Double
}

struct CopilotUsage: Equatable {
    /// Premium requests (user prompts weighted by model multiplier) since the start of the month, UTC.
    let requests: Double
    let projects: [ProjectAmount]
}

/// Counts GitHub Copilot CLI premium requests from its local session logs
/// (`~/.copilot/session-state/*/events.jsonl`). A request is a user-initiated model call, weighted by its `cost`.
/// Agent follow-up calls are not counted, matching how Copilot bills prompts. This is an estimate; GitHub's own
/// billing page is authoritative. Incremental and local-only, like the other log readers.
/// Not thread-safe; call from one queue at a time.
final class CopilotLogClient: @unchecked Sendable {
    private struct Record { var date: Date; var weight: Double; var project: String }
    private struct FileState { var offset: UInt64 = 0; var project = "Unknown" }

    private static let usageMarker = Data("\"session.usage_record\"".utf8)
    private static let startMarker = Data("\"session.start\"".utf8)

    private var files: [String: FileState] = [:]
    private var records: [Record] = []
    private let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoPlain = ISO8601DateFormatter()

    private var root: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".copilot/session-state") }

    /// Returns nil when Copilot CLI has never been used on this Mac.
    func fetch(now: Date = Date()) -> CopilotUsage? {
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        scan(cutoff: monthStart)
        records.removeAll { $0.date < monthStart }
        let grouped = Dictionary(grouping: records, by: \.project)
        let projects = grouped.map { ProjectAmount(name: $0.key, amount: $0.value.reduce(0) { $0 + $1.weight }) }
            .sorted { $0.amount > $1.amount }
        return CopilotUsage(requests: records.reduce(0) { $0 + $1.weight }, projects: projects)
    }

    private func scan(cutoff: Date) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in walker where url.lastPathComponent == "events.jsonl" {
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
        if state.project == "Unknown", line.range(of: Self.startMarker) != nil {
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               let data = object["data"] as? [String: Any], let context = data["context"] as? [String: Any],
               let cwd = context["cwd"] as? String {
                let name = URL(fileURLWithPath: cwd).lastPathComponent
                state.project = name.isEmpty ? "/" : name
            }
            return
        }
        guard line.range(of: Self.usageMarker) != nil,   // cheap pre-filter before JSON parsing
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "session.usage_record",
              let data = object["data"] as? [String: Any], let usage = data["usage"] as? [String: Any],
              usage["initiator"] as? String == "user",
              let stamp = object["timestamp"] as? String,
              let date = isoFractional.date(from: stamp) ?? isoPlain.date(from: stamp), date >= cutoff else { return }
        let weight = (usage["cost"] as? NSNumber)?.doubleValue ?? 1
        records.append(Record(date: date, weight: weight, project: state.project))
    }
}

func formatRequests(_ value: Double) -> String {
    value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
}
