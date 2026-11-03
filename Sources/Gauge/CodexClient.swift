import Foundation

struct UsageWindow: Identifiable, Equatable {
    let id: String
    let name: String
    let usedPercent: Double
    let resetsAt: Date?
    let durationMinutes: Int?

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
}

enum CodexClientError: LocalizedError {
    case notInstalled
    case timedOut
    case invalidResponse
    case server(String)
    var errorDescription: String? {
        switch self {
        case .notInstalled: return "Codex CLI not found. Install Codex CLI and sign in with ChatGPT."
        case .timedOut: return "Codex App Server did not respond in time."
        case .invalidResponse: return "Codex App Server returned an unexpected response."
        case .server(let message): return message
        }
    }
}

/// Uses the documented Codex App Server over local stdio. Never reads browser cookies or tokens.
struct CodexClient {
    func fetch() throws -> [UsageWindow] {
        let proc = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        proc.standardInput = input
        proc.standardOutput = output
        proc.standardError = errors
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["codex", "app-server"]
        var environment = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        environment["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.npm-global/bin", environment["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        proc.environment = environment
        let collector = ResponseCollector()
        var buffered = Data()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            buffered.append(data)
            while let newline = buffered.firstIndex(of: 10) {
                let line = Data(buffered[..<newline])
                buffered.removeSubrange(...newline)
                if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   let id = obj["id"] as? Int {
                    collector.add(id: id, response: obj)
                }
            }
        }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            input.fileHandleForWriting.closeFile()
            if proc.isRunning { proc.terminate() }
        }
        do { try proc.run() }
        catch { throw CodexClientError.notInstalled }
        func send(_ object: [String: Any]) throws {
            let payload = try JSONSerialization.data(withJSONObject: object)
            input.fileHandleForWriting.write(payload + Data([10]))
        }
        try send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "gauge", "title": "Gauge", "version": "0.1.0"],
            "capabilities": [:] as [String: String]
        ]])
        let initialized = try collector.wait(for: 1, timeout: 8)
        if let error = initialized["error"] as? [String: Any] {
            throw CodexClientError.server(error["message"] as? String ?? "Initialization failed")
        }
        try send(["method": "initialized", "params": [:] as [String: String]])
        try send(["id": 2, "method": "account/rateLimits/read", "params": [:] as [String: String]])
        let response = try collector.wait(for: 2, timeout: 12)
        if let error = response["error"] as? [String: Any] {
            throw CodexClientError.server(error["message"] as? String ?? "Usage read failed")
        }
        guard let result = response["result"] as? [String: Any] else {
            throw CodexClientError.invalidResponse
        }
        var buckets: [(String, [String: Any])] = []
        if let byId = result["rateLimitsByLimitId"] as? [String: [String: Any]], !byId.isEmpty {
            buckets = byId.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
        } else if let item = result["rateLimits"] as? [String: Any] {
            buckets = [(item["limitId"] as? String ?? "codex", item)]
        }
        var windows: [UsageWindow] = []
        for (key, bucket) in buckets {
            for (kind, label) in [("primary", "Primary"), ("secondary", "Secondary")] {
                guard let w = bucket[kind] as? [String: Any],
                      let used = w["usedPercent"] as? NSNumber else { continue }
                let timestamp = (w["resetsAt"] as? NSNumber)?.doubleValue
                let duration = (w["windowDurationMins"] as? NSNumber)?.intValue
                let friendlyName = bucket["limitName"] as? String ?? key
                windows.append(.init(
                    id: "\(key).\(kind)", name: "\(friendlyName) · \(label)",
                    usedPercent: min(100, max(0, used.doubleValue)),
                    resetsAt: timestamp.map(Date.init(timeIntervalSince1970:)),
                    durationMinutes: duration
                ))
            }
        }
        if windows.isEmpty { throw CodexClientError.server("No Codex subscription limits returned. Sign in to Codex with ChatGPT (not an API key).") }
        return windows
    }
}

private final class ResponseCollector {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var responses: [Int: [String: Any]] = [:]

    func add(id: Int, response: [String: Any]) {
        lock.lock(); responses[id] = response; lock.unlock()
        signal.signal()
    }
    func wait(for id: Int, timeout: TimeInterval) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            lock.lock()
            let value = responses.removeValue(forKey: id)
            lock.unlock()
            if let value { return value }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { throw CodexClientError.timedOut }
            if signal.wait(timeout: .now() + remaining) == .timedOut { throw CodexClientError.timedOut }
        }
    }
}
