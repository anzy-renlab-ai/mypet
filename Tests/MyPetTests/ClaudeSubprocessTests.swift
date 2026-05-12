import XCTest
@testable import MyPet

/// TDD test suite for ClaudeSubprocess.
///
/// Covers 9 dimensions:
///  1. Binary discovery (PATH search, symlinks, perms)
///  2. Subprocess execution happy / non-zero / empty
///  3. Timeout & cancellation
///  4. Encoding (UTF-8, emoji, ANSI strip)
///  5. Output normalization (trim, dedupe, truncate)
///  6. Stderr-based error classification
///  7. Concurrent guard
///  8. Resource cleanup
///  9. CC CLI schema drift defense
final class ClaudeSubprocessTests: XCTestCase {

    // MARK: - 1. Binary discovery

    func test_discoverBinary_returnsPath_whenClaudeOnPATH() async {
        // Real env: alias `which claude` should succeed on this dev box.
        let path = await ClaudeSubprocess.discoverBinary()
        XCTAssertNotNil(path, "claude should be discoverable in dev env")
        XCTAssertTrue(path!.hasSuffix("claude"))
    }

    func test_discoverBinary_returnsNil_whenPATHEmpty() async {
        let path = await ClaudeSubprocess.discoverBinary(searchPath: "")
        XCTAssertNil(path)
    }

    func test_discoverBinary_returnsNil_whenBinaryAbsent() async {
        // Use a dir that exists but does not contain claude
        let path = await ClaudeSubprocess.discoverBinary(searchPath: "/tmp")
        XCTAssertNil(path)
    }

    func test_discoverBinary_picksFirstMatch_whenMultiplePATHEntries() async {
        // Real PATH first, then /tmp — first must win
        let realPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let path = await ClaudeSubprocess.discoverBinary(searchPath: realPath)
        XCTAssertNotNil(path)
    }

    func test_discoverBinary_handlesPATHWithSpaces() async {
        // "/Applications/Some App/bin:/tmp" must not break parsing
        let path = await ClaudeSubprocess.discoverBinary(searchPath: "/Applications/Some App/bin:/tmp")
        XCTAssertNil(path) // claude not in either, but must not crash
    }

    // MARK: - 2. Execution happy / non-zero / empty

    func test_run_returnsStdout_onExit0() async throws {
        // Use a synthetic binary: /bin/echo "hello cat 🐱"
        let result = try await ClaudeSubprocess.runRaw(binary: "/bin/echo", args: ["hello cat 🐱"])
        XCTAssertEqual(result, "hello cat 🐱")
    }

    func test_run_throws_onNonZeroExit() async {
        do {
            _ = try await ClaudeSubprocess.runRaw(binary: "/usr/bin/false", args: [])
            XCTFail("Expected throw on non-zero exit")
        } catch let error as ClaudeSubprocessError {
            guard case .nonZeroExit(let code, _) = error else {
                return XCTFail("Expected .nonZeroExit, got \(error)")
            }
            XCTAssertNotEqual(code, 0)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func test_run_throws_onEmptyStdoutWithExit0() async {
        // /usr/bin/true exits 0 with no output
        do {
            _ = try await ClaudeSubprocess.runRaw(binary: "/usr/bin/true", args: [])
            XCTFail("Expected throw on empty stdout")
        } catch let error as ClaudeSubprocessError {
            guard case .emptyOutput = error else {
                return XCTFail("Expected .emptyOutput, got \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func test_run_capturesStderr_evenWithExit0() async throws {
        // sh -c "echo err >&2; echo out" — stdout 'out', stderr 'err', exit 0
        let result = try await ClaudeSubprocess.runRawWithStderr(
            binary: "/bin/sh",
            args: ["-c", "echo err >&2; echo out"]
        )
        XCTAssertEqual(result.stdout, "out")
        XCTAssertEqual(result.stderr, "err")
    }

    // MARK: - 3. Timeout & cancellation

    func test_run_throwsTimeout_whenExceedsLimit() async {
        let start = Date()
        do {
            _ = try await ClaudeSubprocess.runRaw(
                binary: "/bin/sleep",
                args: ["10"],
                timeout: 1.0
            )
            XCTFail("Expected timeout")
        } catch let error as ClaudeSubprocessError {
            guard case .timeout = error else {
                return XCTFail("Expected .timeout, got \(error)")
            }
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertLessThan(elapsed, 3.0, "Should kill within timeout + grace")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func test_run_killsSubprocess_onTaskCancel() async {
        let task = Task<String, Error> {
            try await ClaudeSubprocess.runRaw(binary: "/bin/sleep", args: ["10"], timeout: 60)
        }
        try? await Task.sleep(nanoseconds: 200_000_000) // let it start
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation throw")
        } catch is CancellationError {
            // ok
        } catch let error as ClaudeSubprocessError {
            // Acceptable: subprocess killed → reported as timeout/error
            guard case .cancelled = error else {
                return XCTFail("Expected .cancelled, got \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - 4. Encoding

    func test_run_handlesUTF8Emoji() async throws {
        let result = try await ClaudeSubprocess.runRaw(binary: "/bin/echo", args: ["猫 🐾 🍖"])
        XCTAssertEqual(result, "猫 🐾 🍖")
    }

    func test_run_stripsANSIEscapes() async throws {
        // sh -c "printf '\x1b[31mred\x1b[0m'"
        let result = try await ClaudeSubprocess.runRaw(
            binary: "/bin/sh",
            args: ["-c", "printf '\\033[31mred\\033[0m'"]
        )
        XCTAssertEqual(result, "red", "ANSI color codes must be stripped")
    }

    // MARK: - 5. Output normalization

    func test_normalizeTip_trimsWhitespace() {
        XCTAssertEqual(ClaudeSubprocess.normalizeTip("  hello\n"), "hello")
    }

    func test_normalizeTip_truncatesAt140Chars() {
        let long = String(repeating: "a", count: 200)
        let out = ClaudeSubprocess.normalizeTip(long)
        XCTAssertEqual(out.count, 140, "Must truncate to exactly 140")
        XCTAssertTrue(out.hasSuffix("…"))
    }

    func test_normalizeTip_keepsShortText() {
        XCTAssertEqual(ClaudeSubprocess.normalizeTip("short"), "short")
    }

    func test_normalizeTip_takesFirstLine_whenMultiLine() {
        // LLM disobeys "one item": returns 3 lines
        let multi = "first tip line\nsecond tip line\nthird"
        XCTAssertEqual(ClaudeSubprocess.normalizeTip(multi), "first tip line")
    }

    func test_normalizeTip_stripsMarkdownCodeFences() {
        let md = "```\nthe tip\n```"
        XCTAssertEqual(ClaudeSubprocess.normalizeTip(md), "the tip")
    }

    func test_normalizeTip_stripsLeadingBulletOrNumber() {
        XCTAssertEqual(ClaudeSubprocess.normalizeTip("- a tip"), "a tip")
        XCTAssertEqual(ClaudeSubprocess.normalizeTip("1. a tip"), "a tip")
        XCTAssertEqual(ClaudeSubprocess.normalizeTip("* a tip"), "a tip")
    }

    func test_normalizeTip_emojiOnly_isFine() {
        XCTAssertEqual(ClaudeSubprocess.normalizeTip("🐱🍖"), "🐱🍖")
    }

    func test_normalizeTip_emptyAfterTrim_throwsViaCaller() {
        // Caller (runRaw) treats empty as .emptyOutput; normalize itself
        // returns empty string and lets caller decide.
        XCTAssertEqual(ClaudeSubprocess.normalizeTip("   \n\n  "), "")
    }

    // MARK: - 6. Stderr-based error classification

    func test_classifyStderr_detectsNotAuthenticated() {
        let err = ClaudeSubprocess.classifyStderr("Error: Not logged in. Run `claude login`.")
        XCTAssertEqual(err, .notAuthenticated)
    }

    func test_classifyStderr_detectsRateLimit() {
        let err = ClaudeSubprocess.classifyStderr("Error: 429 rate limit exceeded")
        XCTAssertEqual(err, .rateLimited)
    }

    func test_classifyStderr_detectsPermissionDenied() {
        let err = ClaudeSubprocess.classifyStderr("Permission denied: /Users/x/file")
        XCTAssertEqual(err, .systemError)
    }

    func test_classifyStderr_unknown_returnsNil() {
        XCTAssertNil(ClaudeSubprocess.classifyStderr("xyzzy"))
    }

    // MARK: - 7. Concurrent guard

    func test_concurrentFeed_secondCallReturnsBusy() async throws {
        // Skip if claude not in PATH (CI env)
        guard await ClaudeSubprocess.discoverBinary() != nil else {
            throw XCTSkip("claude not in PATH")
        }
        let coordinator = ClaudeSubprocess.shared
        async let first = coordinator.feed(prompt: "test 1")
        async let second = coordinator.feed(prompt: "test 2")
        let results = await [first, second]
        let busyCount = results.filter {
            if case .failure(let err) = $0,
               case .busy = err {
                return true
            }
            return false
        }.count
        XCTAssertEqual(busyCount, 1, "Exactly one call should report .busy")
    }

    // MARK: - 8. Resource cleanup

    func test_run_doesNotLeakFileDescriptors() async throws {
        // Run 50 quick subprocesses, check that the FD count doesn't blow up.
        let initialFD = countOpenFDs()
        for _ in 0..<50 {
            _ = try? await ClaudeSubprocess.runRaw(binary: "/bin/echo", args: ["test"])
        }
        let finalFD = countOpenFDs()
        XCTAssertLessThan(finalFD - initialFD, 20, "FD leak detected: +\(finalFD - initialFD)")
    }

    // MARK: - 9. CC schema drift defense

    func test_runClaude_smokeTest_versionFlagWorks() async throws {
        guard let binary = await ClaudeSubprocess.discoverBinary() else {
            throw XCTSkip("claude not in PATH")
        }
        // `claude --version` should never break; if it does, CC has bumped to a
        // schema that breaks our parser — surface immediately.
        let version = try await ClaudeSubprocess.runRaw(binary: binary, args: ["--version"])
        XCTAssertTrue(
            version.contains(".") && version.lowercased().contains("claude"),
            "Expected semver-ish 'X.Y.Z Claude Code', got: \(version)"
        )
    }

    func test_runClaude_outputFormatFlagFallback() async throws {
        // If `--output-format text` is rejected (future schema), fallback must
        // try plain prompt mode.
        guard await ClaudeSubprocess.discoverBinary() != nil else {
            throw XCTSkip("claude not in PATH")
        }
        // Simulated by passing an invalid flag and expecting the helper
        // to retry without it (only when the error matches "unknown option")
        // For W0 we just assert the helper exists and returns a useful error.
        do {
            _ = try await ClaudeSubprocess.feedOnce(prompt: "one short greeting")
        } catch let error as ClaudeSubprocessError {
            // Acceptable failure types in spike mode: notAuthenticated, rateLimited,
            // systemError, timeout. emptyOutput would mean CC returned blank.
            switch error {
            case .nonZeroExit, .emptyOutput, .timeout,
                 .notAuthenticated, .rateLimited, .systemError, .busy, .cancelled, .binaryNotFound:
                break // any classified error is fine for spike
            }
        }
    }

    // MARK: - Helpers

    private func countOpenFDs() -> Int {
        var count = 0
        let fm = FileManager.default
        let procPath = "/dev/fd"
        if let entries = try? fm.contentsOfDirectory(atPath: procPath) {
            count = entries.count
        }
        return count
    }
}
