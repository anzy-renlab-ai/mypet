import Foundation
import OSLog

private let log = Logger(subsystem: "ai.mypet", category: "ClaudeSubprocess")

enum ClaudeSubprocessError: Error, Equatable {
    case binaryNotFound
    case nonZeroExit(code: Int32, stderr: String)
    case emptyOutput
    case timeout
    case cancelled
    case notAuthenticated
    case rateLimited
    case systemError
    case busy
}

/// Single feed result — tip text + the tokens it cost.
/// Tokens = input + output (cache tokens excluded so the count tracks "fresh"
/// consumption a user would intuit).
struct FeedSuccess: Equatable {
    let tip: String
    let tokens: Int

    static let zero = FeedSuccess(tip: "", tokens: 0)
}

/// Coordinates calls to the local `claude` CLI for the "feed" action.
///
/// - Static helpers (`discoverBinary`, `runRaw`, `normalizeTip`, `classifyStderr`)
///   are pure / stateless and used by tests + production paths.
/// - The `shared` actor instance enforces a single in-flight feed
///   (concurrent guard) and is the entry point from `FeedCoordinator`.
final class ClaudeSubprocess {

    // MARK: - Public singleton

    static let shared = ClaudeSubprocess()

    private let runLock = AsyncSemaphore(value: 1)
    private var running = false

    // MARK: - Binary discovery

    /// Searches PATH for the `claude` executable.
    /// Returns full path on success, nil if not found.
    static func discoverBinary(searchPath: String? = nil) async -> String? {
        let path = searchPath ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        guard !path.isEmpty else { return nil }
        let entries = path.split(separator: ":").map(String.init)
        for dir in entries {
            let candidate = (dir as NSString).appendingPathComponent("claude")
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Raw subprocess runner (used by tests + feed())

    static func runRaw(
        binary: String,
        args: [String],
        timeout: TimeInterval = 20
    ) async throws -> String {
        let result = try await runRawWithStderr(binary: binary, args: args, timeout: timeout)
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ClaudeSubprocessError.emptyOutput
        }
        return stripANSI(trimmed)
    }

    static func runRawWithStderr(
        binary: String,
        args: [String],
        timeout: TimeInterval = 20
    ) async throws -> (stdout: String, stderr: String) {

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        do {
            try proc.run()
        } catch {
            log.error("Process launch failed: \(error.localizedDescription)")
            throw ClaudeSubprocessError.systemError
        }

        // Read concurrently with wait to avoid pipe buffer deadlocks.
        let stdoutTask = Task<Data, Never> {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let stderrTask = Task<Data, Never> {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }

        // Track termination reason via shared flag (avoids race in task group).
        final class TerminationFlags: @unchecked Sendable {
            private let lock = NSLock()
            private var _timeout = false
            private var _cancelled = false
            func markTimeout() { lock.lock(); _timeout = true; lock.unlock() }
            func markCancelled() { lock.lock(); _cancelled = true; lock.unlock() }
            var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return _timeout }
            var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
        }
        let flags = TerminationFlags()

        // Background timeout watcher.
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if !Task.isCancelled && proc.isRunning {
                flags.markTimeout()
                proc.terminate()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if proc.isRunning {
                    kill(proc.processIdentifier, SIGKILL)
                }
            }
        }

        // Wait for exit, honoring Task cancellation.
        let exitCode: Int32 = await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
                proc.terminationHandler = { p in
                    cont.resume(returning: p.terminationStatus)
                }
            }
        } onCancel: {
            flags.markCancelled()
            if proc.isRunning {
                proc.terminate()
                // SIGKILL grace handled by terminationHandler completion path
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if proc.isRunning {
                        kill(proc.processIdentifier, SIGKILL)
                    }
                }
            }
        }

        timeoutTask.cancel()

        let stdoutBytes = await stdoutTask.value
        let stderrBytes = await stderrTask.value

        // Best-effort close to release FDs.
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()

        let stdoutStr = (String(data: stdoutBytes, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stderrStr = (String(data: stderrBytes, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if flags.timedOut {
            throw ClaudeSubprocessError.timeout
        }
        if flags.cancelled {
            throw ClaudeSubprocessError.cancelled
        }
        if exitCode != 0 {
            if let classified = classifyStderr(stderrStr) {
                throw classified
            }
            throw ClaudeSubprocessError.nonZeroExit(code: exitCode, stderr: stderrStr)
        }
        return (stdout: stdoutStr, stderr: stderrStr)
    }

    // MARK: - Output normalization (sync, pure)

    /// Normalizes raw LLM tip output:
    /// - Strips ANSI
    /// - Strips markdown code fences
    /// - Strips leading list markers (-, *, 1.)
    /// - Trims whitespace
    /// - **Keeps newlines** (multi-line haiku / 打油诗 / list)
    /// - Collapses runs of blank lines
    /// - Truncates to 220 chars + "…"
    static func normalizeTip(_ raw: String) -> String {
        var s = stripANSI(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        // Markdown code fence: ```...```
        if s.hasPrefix("```") && s.hasSuffix("```") {
            let inner = s.dropFirst(3).dropLast(3)
            s = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Process per line: strip list markers, drop empty, keep order
        var lines: [String] = []
        for raw in s.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            for m in ["- ", "* ", "• "] where line.hasPrefix(m) {
                line = String(line.dropFirst(m.count))
                break
            }
            if let dotIdx = line.firstIndex(of: "."),
               dotIdx < line.index(line.startIndex, offsetBy: 3, limitedBy: line.endIndex) ?? line.endIndex,
               line[..<dotIdx].allSatisfy(\.isNumber) {
                let after = line.index(after: dotIdx)
                if after < line.endIndex && line[after] == " " {
                    line = String(line[line.index(after: after)...])
                }
            }
            lines.append(line)
        }
        s = lines.joined(separator: "\n")
        // Truncate (generous limit so haiku / 打油诗 / multi-line tips survive)
        if s.count > 220 {
            let trimmed = String(s.prefix(219))
            s = trimmed + "…"
        }
        return s
    }

    // MARK: - Stderr classification

    static func classifyStderr(_ stderr: String) -> ClaudeSubprocessError? {
        let lower = stderr.lowercased()
        if lower.contains("not logged in") || lower.contains("login") && lower.contains("error") {
            return .notAuthenticated
        }
        if lower.contains("rate limit") || lower.contains("429") {
            return .rateLimited
        }
        if lower.contains("permission denied") {
            return .systemError
        }
        return nil
    }

    // MARK: - Feed (concurrent-guarded)

    func feed(prompt: String) async -> Result<FeedSuccess, ClaudeSubprocessError> {
        // Try to acquire the lock without waiting; if held, report .busy
        let acquired = await runLock.tryAcquire()
        guard acquired else { return .failure(.busy) }

        // Release synchronously before returning. `defer` can't hold `await`,
        // so the previous `defer { Task { await release() } }` deferred the
        // release to a later tick — leaving a window where feed() had returned
        // but the lock was still held, so an immediately-following feed() got
        // a spurious `.busy`. Releasing inline closes that window.
        let outcome: Result<FeedSuccess, ClaudeSubprocessError>
        do {
            outcome = .success(try await Self.feedOnce(prompt: prompt))
        } catch let err as ClaudeSubprocessError {
            outcome = .failure(err)
        } catch {
            outcome = .failure(.systemError)
        }
        await runLock.release()
        return outcome
    }

    /// Calls `claude -p <prompt> --output-format json` and parses the result
    /// envelope so we can report token usage alongside the tip text.
    ///
    /// Lean flags keep the cost down: a feed only needs one line of text, but
    /// by default `claude` loads every configured MCP server's tool schemas +
    /// all built-in tool definitions into the prompt — measured at ~20k input
    /// tokens per feed on a machine with several MCP servers. `--strict-mcp-config`
    /// (with no `--mcp-config`) loads zero MCP servers and `--tools ""` disables
    /// the built-in tools, cutting input to ~6k (~69% less) while still returning
    /// a tip. We deliberately do NOT use `--bare`: it forces ANTHROPIC_API_KEY
    /// and never reads OAuth/keychain, which would break auth for most users.
    static func feedOnce(prompt: String) async throws -> FeedSuccess {
        guard let binary = await discoverBinary() else {
            throw ClaudeSubprocessError.binaryNotFound
        }
        let raw = try await runRaw(
            binary: binary,
            args: ["-p", prompt, "--output-format", "json",
                   "--strict-mcp-config", "--tools", ""],
            timeout: 90
        )
        let parsed = try parseFeedJSON(raw)
        if parsed.tip.isEmpty {
            throw ClaudeSubprocessError.emptyOutput
        }
        return parsed
    }

    /// Parses the JSON envelope `claude --output-format json` returns into
    /// `(tip, tokens)`. Token count = input + output (cache excluded).
    /// Falls back to treating the raw string as plain text if JSON parse fails.
    static func parseFeedJSON(_ raw: String) throws -> FeedSuccess {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw ClaudeSubprocessError.emptyOutput
        }
        // Decoder: tolerate missing fields, ignore everything except what we need.
        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
        }
        struct Envelope: Decodable {
            let result: String?
            let is_error: Bool?
            let usage: Usage?
        }
        if let env = try? JSONDecoder().decode(Envelope.self, from: data) {
            if env.is_error == true { throw ClaudeSubprocessError.systemError }
            let tip = normalizeTip(env.result ?? "")
            let tokens = (env.usage?.input_tokens ?? 0) + (env.usage?.output_tokens ?? 0)
            return FeedSuccess(tip: tip, tokens: tokens)
        }
        // Fallback: treat raw as text (defensive — earlier CLI versions used text).
        return FeedSuccess(tip: normalizeTip(trimmed), tokens: 0)
    }

    static func smokeTest() async {
        guard let binary = await discoverBinary() else {
            log.warning("claude not in PATH — onboarding will guide install")
            return
        }
        do {
            let v = try await runRaw(binary: binary, args: ["--version"], timeout: 5)
            log.info("claude version: \(v)")
        } catch {
            log.error("smoke test failed: \(String(describing: error))")
        }
    }

    // MARK: - ANSI strip

    private static let ansiRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: "\u{1B}\\[[0-9;?]*[A-Za-z]",
            options: []
        )
    }()

    static func stripANSI(_ s: String) -> String {
        let range = NSRange(location: 0, length: (s as NSString).length)
        return ansiRegex.stringByReplacingMatches(
            in: s,
            options: [],
            range: range,
            withTemplate: ""
        )
    }
}

// MARK: - Async semaphore (tryAcquire support)

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = value
    }

    func acquire() async {
        if value > 0 {
            value -= 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    func tryAcquire() -> Bool {
        if value > 0 {
            value -= 1
            return true
        }
        return false
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            value += 1
        }
    }
}
