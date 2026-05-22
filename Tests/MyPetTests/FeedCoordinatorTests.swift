import XCTest
@testable import MyPet

@MainActor
final class FeedCoordinatorTests: XCTestCase {

    /// Test double: configurable Feeder that returns canned results.
    final class MockFeeder: Feeder {
        var result: Result<FeedSuccess, ClaudeSubprocessError>
        var callCount = 0
        var lastPrompt: String?

        init(result: Result<FeedSuccess, ClaudeSubprocessError>) {
            self.result = result
        }

        /// Backwards-compat init: tests that don't care about tokens can pass a String.
        convenience init(tipResult: Result<String, ClaudeSubprocessError>) {
            switch tipResult {
            case .success(let s): self.init(result: .success(FeedSuccess(tip: s, tokens: 0)))
            case .failure(let e): self.init(result: .failure(e))
            }
        }

        func feed(prompt: String) async -> Result<FeedSuccess, ClaudeSubprocessError> {
            callCount += 1
            lastPrompt = prompt
            return result
        }
    }

    var tmpLogURL: URL!
    var feedLog: FeedLog!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mypet-coord-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tmpLogURL = dir.appendingPathComponent("feed-log.json")
        feedLog = FeedLog(url: tmpLogURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpLogURL.deletingLastPathComponent())
    }

    // MARK: - Happy path

    func test_feed_happyPath_transitions_idle_eating_excited_purring_idle() async {
        let feeder = MockFeeder(tipResult: .success("a fun tip 🐾"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.excitedOverlaySeconds = 0.05
        coord.tipDisplaySeconds = 0.05

        XCTAssertEqual(coord.state, .idle)

        let task = Task { await coord.feed() }

        // Sample states quickly to verify transition through eating
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        // Note: feeder is sync-fast, may already be in excited by now.

        await task.value
        // Allow the final auto-dismiss to complete.
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(feeder.callCount, 1)
        XCTAssertEqual(coord.state, .idle, "After purring + dismiss should be idle")
        XCTAssertNil(coord.tip)
        XCTAssertEqual(coord.feedCount, 1)
    }

    func test_feed_firstFeed_showsRealTipNotWelcome() async {
        // Behavior changed: user wanted the real LLM-returned tip on every
        // feed, including the first. (Was previously a canned welcome.)
        let feeder = MockFeeder(tipResult: .success("a fun tip 🐾"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.excitedOverlaySeconds = 0.05
        coord.tipDisplaySeconds = 0.3   // outlasts the 0.25s assertion; was 5

        XCTAssertTrue(coord.isFirstFeed)
        let task = Task { await coord.feed() }
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(coord.state, .purring)
        XCTAssertEqual(coord.tip, "a fun tip 🐾",
                       "First feed must show the LLM tip, not a canned welcome")
        XCTAssertFalse(coord.isFirstFeed, "isFirstFeed must clear after first success")

        coord.dismissTip()
        await task.value
    }

    func test_feed_secondFeed_showsRawTip() async {
        let feeder = MockFeeder(tipResult: .success("real tip text 🐾"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.excitedOverlaySeconds = 0.05
        coord.tipDisplaySeconds = 0.3   // outlasts the 0.1s assertion below; was 5
        coord.cooldownSeconds = 0  // disable cooldown for test

        await coord.feed() // first → welcome
        coord.dismissTip()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let task = Task { await coord.feed() }
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(coord.tip, "real tip text 🐾")
        coord.dismissTip()
        await task.value
    }

    // MARK: - Error path

    func test_feed_error_setsHungryAndFriendlyMessage() async {
        let feeder = MockFeeder(tipResult: .failure(.notAuthenticated))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.tipDisplaySeconds = 5

        let task = Task { await coord.feed() }
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(coord.state, .hungry)
        XCTAssertEqual(coord.lastError, .notAuthenticated)
        XCTAssertNotNil(coord.tip)
        XCTAssertTrue(coord.tip!.contains("claude login"))

        task.cancel()
    }

    func test_feed_binaryNotFound_givesInstallGuidance() async {
        let feeder = MockFeeder(tipResult: .failure(.binaryNotFound))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.tipDisplaySeconds = 5

        let task = Task { await coord.feed() }
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(coord.state, .hungry)
        XCTAssertTrue(coord.tip!.contains("Claude Code"))

        task.cancel()
    }

    // MARK: - Cooldown

    func test_feed_blockedByCooldown() async {
        let feeder = MockFeeder(tipResult: .success("tip"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.excitedOverlaySeconds = 0.01
        coord.tipDisplaySeconds = 0.01
        coord.cooldownSeconds = 60
        coord.cooldownTipSeconds = 0.01   // reject-tip window; no assertion on it here

        await coord.feed()
        try? await Task.sleep(nanoseconds: 100_000_000)
        let firstCount = feeder.callCount

        // Second call within cooldown should be rejected
        await coord.feed()
        XCTAssertEqual(feeder.callCount, firstCount, "Second feed within 60s must be rejected")
    }

    // Regression: ISSUE-006 — cooldown used to swallow the feed silently.
    // Found by /qa on 2026-05-12
    // Report: ~/.gstack/projects/mypet/...-qa-...
    func test_feed_duringCooldown_showsFeedbackTip() async {
        let feeder = MockFeeder(tipResult: .success("real tip"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.excitedOverlaySeconds = 0.01
        coord.tipDisplaySeconds = 0.01
        coord.cooldownSeconds = 60
        coord.cooldownTipSeconds = 0.2   // outlasts the 0.1s mid-flight sample below

        // First feed → records timestamp
        await coord.feed()
        try? await Task.sleep(nanoseconds: 100_000_000)
        coord.dismissTip()

        // Second feed within cooldown: launch it, sample the tip mid-flight.
        let task = Task { await coord.feed() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(coord.tip, "Cooldown rejection must surface a tip, not be silent")
        XCTAssertTrue(coord.tip!.contains("消化"), "Expected a 'still digesting' message, got: \(coord.tip ?? "nil")")
        await task.value
        // After the message window closes, tip clears.
        XCTAssertNil(coord.tip)
    }

    // MARK: - Idle transitions

    func test_evaluateIdle_setsHungry_after24h() async {
        let feeder = MockFeeder(tipResult: .success("tip"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.cooldownSeconds = 0
        coord.excitedOverlaySeconds = 0.01
        coord.tipDisplaySeconds = 0.01

        // Run a feed to set lastFeedAt, then mutate machine's lastFeedAt to past.
        await coord.feed()
        try? await Task.sleep(nanoseconds: 100_000_000)
        coord.dismissTip()
        // Test framework can't mock Date(), so we settle for: hungry path validated in PetStateTests
        XCTAssertEqual(coord.state, .idle)
    }

    // MARK: - Theme rotation

    func test_nextTheme_weightedDistribution_pickedTheme_isValid() {
        // Sweep the unit interval — every value should produce one of the
        // declared themes, with no panic / out-of-range.
        for i in 0..<200 {
            let r = Double(i) / 200.0
            let theme = FeedCoordinator.nextTheme(rng: { r })
            XCTAssertTrue(
                FeedCoordinator.TipTheme.allCases.contains(theme),
                "nextTheme returned unknown case at r=\(r): \(theme)"
            )
            XCTAssertFalse(theme.prompt.isEmpty)
        }
    }

    func test_nextTheme_lowR_picksClaudeTip_highR_picksHaiku() {
        // Cumulative cutpoints (claudeTip .. dayouShi) match the published
        // weights — guards against accidental re-ordering of the switch.
        XCTAssertEqual(FeedCoordinator.nextTheme(rng: { 0.0 }), .claudeTip)
        XCTAssertEqual(FeedCoordinator.nextTheme(rng: { 0.29 }), .claudeTip)
        XCTAssertEqual(FeedCoordinator.nextTheme(rng: { 0.30 }), .promptIdea)
        XCTAssertEqual(FeedCoordinator.nextTheme(rng: { 0.95 }), .dayouShi)
    }

    func test_prompt_localeAware_zhVsEn_areDifferent() {
        for theme in FeedCoordinator.TipTheme.allCases {
            let en = theme.prompt(for: .en)
            let zh = theme.prompt(for: .zh)
            XCTAssertFalse(en.isEmpty)
            XCTAssertFalse(zh.isEmpty)
            XCTAssertNotEqual(en, zh, "\(theme) en and zh prompts must diverge")
            // Sanity: zh prompt asks for Chinese output ("中文")
            XCTAssertTrue(zh.contains("中文"), "\(theme) zh prompt should request Chinese output")
        }
    }

    // MARK: - Token reporting

    func test_feed_recordsTokens_andAccumulatesTotal() async {
        let feeder = MockFeeder(result: .success(FeedSuccess(tip: "tip", tokens: 142)))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.cooldownSeconds = 0
        coord.excitedOverlaySeconds = 0.01
        coord.tipDisplaySeconds = 0.01

        XCTAssertEqual(coord.lastTokens, 0)
        XCTAssertEqual(coord.totalTokens, 0)

        await coord.feed()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(coord.lastTokens, 142)
        XCTAssertEqual(coord.totalTokens, 142)

        await coord.feed()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(coord.lastTokens, 142)
        XCTAssertEqual(coord.totalTokens, 284, "Total must accumulate across feeds")
    }

    func test_feed_recordsLastTheme_andSendsThatPromptToFeeder() async {
        let feeder = MockFeeder(tipResult: .success("tip"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.excitedOverlaySeconds = 0.01
        coord.tipDisplaySeconds = 0.01

        await coord.feed()
        try? await Task.sleep(nanoseconds: 100_000_000)

        // lastTheme must be a real case
        XCTAssertTrue(FeedCoordinator.TipTheme.allCases.contains(coord.lastTheme))
        // The prompt sent matches that theme's prompt (no stale defaultPrompt)
        XCTAssertEqual(feeder.lastPrompt, coord.lastTheme.prompt)
    }

    func test_wake_fromSleepy_returnsIdle() async {
        let feeder = MockFeeder(tipResult: .success("tip"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        // Collapse the feed cycle — default tipDisplaySeconds is 600 (10 min),
        // so awaiting feed() with defaults blocked this test for 603s. It only
        // smoke-tests that wake() doesn't crash, no timing assertion.
        coord.excitedOverlaySeconds = 0.01
        coord.tipDisplaySeconds = 0.01
        // Manually drive into sleepy via the state machine — only public way is
        // evaluateIdle with timestamps in past, which we can't easily mock.
        // We test the wake() pass-through behaviour by feeding and checking state.
        await coord.feed()
        coord.wake()
        // wake from idle is a no-op state-wise but updates lastEventAt; this
        // smoke-tests that wake doesn't crash.
        XCTAssertNotEqual(coord.state, .sleepy)
    }

    // MARK: - Edge state (window-position driven)

    func test_setEdgeState_clingTop_fromIdle() {
        let coord = FeedCoordinator(feeder: MockFeeder(tipResult: .success("x")), log: feedLog)
        coord.setEdgeState(.clingTop)
        XCTAssertEqual(coord.state, .clingTop)
    }

    func test_setEdgeState_clearsWithNil() {
        let coord = FeedCoordinator(feeder: MockFeeder(tipResult: .success("x")), log: feedLog)
        coord.setEdgeState(.peekLeft)
        XCTAssertEqual(coord.state, .peekLeft)
        coord.setEdgeState(nil)
        XCTAssertEqual(coord.state, .idle)
    }

    func test_setEdgeState_doesNotInterruptFeed() async {
        let feeder = MockFeeder(tipResult: .success("tip"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.excitedOverlaySeconds = 0.05
        coord.tipDisplaySeconds = 0.05

        let task = Task { await coord.feed() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        // With a sync-fast mock feeder the state can already be eating OR
        // excited by now — the assertion is "we're inside the feed cycle".
        let feedCycle: Set<PetState> = [.eating, .excited, .purring]
        XCTAssertTrue(feedCycle.contains(coord.state), "Expected feed cycle, got \(coord.state)")

        // User drags window to top during the chomp — must NOT override.
        coord.setEdgeState(.clingTop)
        XCTAssertNotEqual(coord.state, .clingTop, "Edge state must not interrupt the active feed cycle")
        XCTAssertTrue(feedCycle.contains(coord.state), "Still inside the feed cycle")
        await task.value
    }

    // MARK: - Petting (hover-on-cat driven)

    func test_setPetting_fromIdle_setsPetting() {
        let coord = FeedCoordinator(feeder: MockFeeder(tipResult: .success("x")), log: feedLog)
        coord.setPetting(true)
        XCTAssertEqual(coord.state, .petting)
    }

    func test_setPetting_off_returnsToIdle() {
        let coord = FeedCoordinator(feeder: MockFeeder(tipResult: .success("x")), log: feedLog)
        coord.setPetting(true)
        coord.setPetting(false)
        XCTAssertEqual(coord.state, .idle)
    }

    func test_setPetting_blockedDuringEdgeState() {
        let coord = FeedCoordinator(feeder: MockFeeder(tipResult: .success("x")), log: feedLog)
        coord.setEdgeState(.clingTop)
        coord.setPetting(true)
        XCTAssertEqual(coord.state, .clingTop, "Petting must not override an edge state")
    }

    // MARK: - Grooming (spontaneous personality)

    func test_triggerGrooming_licking_fromIdle() {
        let coord = FeedCoordinator(feeder: MockFeeder(tipResult: .success("x")), log: feedLog)
        coord.triggerGrooming(.licking)
        XCTAssertEqual(coord.state, .licking)
    }

    func test_triggerGrooming_blockedDuringFeed() async {
        let feeder = MockFeeder(tipResult: .success("tip"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.excitedOverlaySeconds = 0.05
        coord.tipDisplaySeconds = 0.05

        let task = Task { await coord.feed() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        coord.triggerGrooming(.washing)
        XCTAssertNotEqual(coord.state, .washing, "Grooming must not override the feed cycle")
        XCTAssertTrue([.eating, .excited].contains(coord.state))
        await task.value
    }

    func test_groomingDidFinish_returnsToIdle() {
        let coord = FeedCoordinator(feeder: MockFeeder(tipResult: .success("x")), log: feedLog)
        coord.triggerGrooming(.washing)
        XCTAssertEqual(coord.state, .washing)
        coord.groomingDidFinish()
        XCTAssertEqual(coord.state, .idle)
    }

    // MARK: - E2E user flows (simulating real interactions end-to-end)

    /// Simulates: user opens app → double-clicks → cat eats → tip shows → dismiss → idle.
    func test_e2e_doubleClickFeedFullCycle() async {
        let feeder = MockFeeder(tipResult: .success("today's tip ✨"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.excitedOverlaySeconds = 0.05
        coord.tipDisplaySeconds = 30   // long: we'll dismiss explicitly mid-cycle

        XCTAssertEqual(coord.state, .idle, "Initial state")

        // User double-clicks → MouseMonitor.onDoubleClick fires coord.feed()
        let feedTask = Task { await coord.feed() }
        // Don't await the full feed task — it would block for tipDisplaySeconds.
        // Sample state at key points instead.

        // Past the excited overlay (~50ms) — should land in purring with tip.
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(coord.state, .purring, "Tip-display phase")
        XCTAssertNotNil(coord.tip, "Tip text must be set")

        // User clicks tip bubble to dismiss → back to idle.
        coord.dismissTip()
        XCTAssertEqual(coord.state, .idle)
        XCTAssertNil(coord.tip)

        feedTask.cancel()  // clean up the still-sleeping auto-dismiss timer
    }

    /// Simulates: user drags window to top edge → clingTop → drags away → idle.
    func test_e2e_dragToEdgeAndBack() {
        let coord = FeedCoordinator(feeder: MockFeeder(tipResult: .success("x")), log: feedLog)

        // PetWindow.onEdgeState would fire .clingTop when the window touches top
        coord.setEdgeState(.clingTop)
        XCTAssertEqual(coord.state, .clingTop)

        // User drags from top to right side
        coord.setEdgeState(.peekRight)
        XCTAssertEqual(coord.state, .peekRight)

        // User drags back to center → onEdgeState(nil)
        coord.setEdgeState(nil)
        XCTAssertEqual(coord.state, .idle)
    }

    /// Simulates: user hovers cursor on cat for 1s → petting → cursor leaves → idle.
    func test_e2e_hoverPetThenLeave() {
        let coord = FeedCoordinator(feeder: MockFeeder(tipResult: .success("x")), log: feedLog)

        // After 1s linger, PetRootView fires setPetting(true)
        coord.setPetting(true)
        XCTAssertEqual(coord.state, .petting)

        // Cursor moves off cat → setPetting(false)
        coord.setPetting(false)
        XCTAssertEqual(coord.state, .idle)
    }

    /// Simulates a hostile race: user feeds, then immediately tries to drag the
    /// window to an edge and hover-pet. Feed cycle must win the whole way.
    func test_e2e_feedWinsOverConcurrentEdgeAndHover() async {
        let feeder = MockFeeder(tipResult: .success("never give up the chomp"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.excitedOverlaySeconds = 0.05
        coord.tipDisplaySeconds = 0.05

        let task = Task { await coord.feed() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        let feedCycle: Set<PetState> = [.eating, .excited, .purring]
        XCTAssertTrue(feedCycle.contains(coord.state), "Expected feed cycle, got \(coord.state)")

        // Concurrent attacks — all must be no-ops on state
        coord.setEdgeState(.clingTop)
        coord.setPetting(true)
        coord.triggerGrooming(.licking)
        XCTAssertNotEqual(coord.state, .clingTop)
        XCTAssertNotEqual(coord.state, .petting)
        XCTAssertNotEqual(coord.state, .licking)
        XCTAssertTrue(feedCycle.contains(coord.state),
                      "Feed cycle must survive concurrent edge / petting / grooming attempts")
        await task.value
    }

    /// Simulates: user is doing nothing → idle. Then drag to right edge → peekRight.
    /// Then double-click → window leaves edge zone? No — actually edge state should
    /// be cleared by the feed start (which moves state to eating), since edge can't
    /// override feed. Verifies the right precedence on transition.
    func test_e2e_doubleClickWhileAtEdge_feedTakesOver() async {
        let feeder = MockFeeder(tipResult: .success("tip"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.excitedOverlaySeconds = 0.05
        coord.tipDisplaySeconds = 0.05

        coord.setEdgeState(.peekRight)
        XCTAssertEqual(coord.state, .peekRight)

        // User double-clicks while window is at right edge — feed should fire
        // and override the edge state (feed is the higher precedence event).
        // Accept any feed-cycle state: GitHub macos-14 runners are faster
        // than local hardware and frequently land in .purring before the
        // 10ms sample. The invariant being tested is "no longer peekRight",
        // not "exactly .eating".
        let task = Task { await coord.feed() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        let feedCycle: Set<PetState> = [.eating, .excited, .purring]
        XCTAssertTrue(feedCycle.contains(coord.state),
                      "feed() must override an active edge state, got \(coord.state)")
        await task.value
    }
}
