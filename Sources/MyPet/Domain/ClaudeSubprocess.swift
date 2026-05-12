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
    /// - Takes first non-empty line
    /// - Truncates to 140 chars + "…"
    static func normalizeTip(_ raw: String) -> String {
        var s = stripANSI(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        // Markdown code fence: ```...``` (may be on its own lines)
        if s.hasPrefix("```") && s.hasSuffix("```") {
            let inner = s.dropFirst(3).dropLast(3)
            s = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // First line
        if let firstNewline = s.firstIndex(of: "\n") {
            s = String(s[..<firstNewline])
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Leading markers
        let markers = ["- ", "* ", "• "]
        for m in markers {
            if s.hasPrefix(m) {
                s = String(s.dropFirst(m.count))
                break
            }
        }
        // Numbered "1. ", "2. "
        if let dotIdx = s.firstIndex(of: "."),
           dotIdx < s.index(s.startIndex, offsetBy: 3, limitedBy: s.endIndex) ?? s.endIndex,
           s[..<dotIdx].allSatisfy(\.isNumber) {
            let after = s.index(after: dotIdx)
            if after < s.endIndex && s[after] == " " {
                s = String(s[s.index(after: after)...])
            }
        }
        // Truncate
        if s.count > 140 {
            let trimmed = String(s.prefix(139))
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

    func feed(prompt: String) async -> Result<String, ClaudeSubprocessError> {
        // Try to acquire the lock without waiting; if held, report .busy
        let acquired = await runLock.tryAcquire()
        guard acquired else { return .failure(.busy) }
        defer { Task { await runLock.release() } }

        do {
            let tip = try await Self.feedOnce(prompt: prompt)
            return .success(tip)
        } catch let err as ClaudeSubprocessError {
            return .failure(err)
        } catch {
            return .failure(.systemError)
        }
    }

    static func feedOnce(prompt: String) async throws -> String {
        guard let binary = await discoverBinary() else {
            throw ClaudeSubprocessError.binaryNotFound
        }
        let raw = try await runRaw(
            binary: binary,
            args: ["-p", prompt, "--output-format", "text"],
            timeout: 20
        )
        let tip = normalizeTip(raw)
        if tip.isEmpty {
            throw ClaudeSubprocessError.emptyOutput
        }
        return tip
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
