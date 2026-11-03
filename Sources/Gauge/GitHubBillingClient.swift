import Foundation

struct BillingResult: Equatable {
    /// Premium requests used this month across every Copilot surface, as GitHub reports them.
    let requests: Double?
    /// Human-readable problem, shown in Settings when `requests` is nil.
    let note: String?
}

/// Optional, exact Copilot usage from GitHub's billing API, via the user's own `gh` CLI.
/// Gauge never sees or stores a token: `gh` holds the login and Gauge only reads the JSON it prints.
/// Needs `gh auth refresh -h github.com -s user`. Throttled, because billing data updates slowly.
/// Not thread-safe; call from one queue at a time.
final class GitHubBillingClient: @unchecked Sendable {
    private var lastAttempt: Date?
    private var last = BillingResult(requests: nil, note: nil)
    private var login: String?
    private static let minInterval: TimeInterval = 15 * 60

    func fetch(force: Bool = false, now: Date = Date()) -> BillingResult {
        if !force, let lastAttempt, now.timeIntervalSince(lastAttempt) < Self.minInterval, last.requests != nil { return last }
        lastAttempt = now
        last = query(now: now)
        return last
    }

    private func query(now: Date) -> BillingResult {
        guard let gh = Self.findGH() else {
            return BillingResult(requests: nil, note: "GitHub CLI (gh) not found. Install it with `brew install gh`, then run `gh auth login`.")
        }
        if login == nil {
            let user = run(gh, ["api", "user", "--jq", ".login"])
            guard user.status == 0, !user.out.isEmpty else {
                return BillingResult(requests: nil, note: "Not signed in to GitHub. Run `gh auth login`.")
            }
            login = user.out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month], from: now)
        let path = "/users/\(login!)/settings/billing/premium_request/usage?year=\(parts.year!)&month=\(parts.month!)"
        let result = run(gh, ["api", path])
        guard result.status == 0 else {
            let text = result.err + result.out
            if text.contains("\"user\" scope") || text.contains("scope") {
                return BillingResult(requests: nil, note: "GitHub needs the `user` permission. Run `gh auth refresh -h github.com -s user`.")
            }
            if text.contains("404") || text.contains("403") {
                return BillingResult(requests: nil, note: "GitHub billing is not available for this account (managed by an organization or enterprise).")
            }
            return BillingResult(requests: nil, note: "Could not read GitHub billing.")
        }
        guard let data = result.out.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["usageItems"] as? [[String: Any]] else {
            return BillingResult(requests: nil, note: "Unexpected GitHub billing response.")
        }
        let copilot = items.filter { (($0["product"] as? String) ?? "").lowercased().contains("copilot") }
        let total = copilot.reduce(0.0) { $0 + (($1["grossQuantity"] as? NSNumber)?.doubleValue ?? 0) }
        return BillingResult(requests: total, note: nil)
    }

    private static func findGH() -> String? {
        let home = NSHomeDirectory()
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "\(home)/.local/bin/gh", "/usr/bin/gh"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func run(_ executable: String, _ arguments: [String]) -> (status: Int32, out: String, err: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["NO_COLOR"] = "1"
        process.environment = environment
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, "", "\(error)") }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: killer)
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        return (process.terminationStatus, String(decoding: outData, as: UTF8.self), String(decoding: errData, as: UTF8.self))
    }
}
