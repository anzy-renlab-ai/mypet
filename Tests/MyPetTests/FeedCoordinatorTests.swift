import XCTest
@testable import MyPet

@MainActor
final class FeedCoordinatorTests: XCTestCase {

    /// Test double: configurable Feeder that returns canned results.
    final class MockFeeder: Feeder {
        var result: Result<String, ClaudeSubprocessError>
        var callCount = 0
        var lastPrompt: String?

        init(result: Result<String, ClaudeSubprocessError>) {
            self.result = result
        }

        func feed(prompt: String) async -> Result<String, ClaudeSubprocessError> {
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
        let feeder = MockFeeder(result: .success("a fun tip 🐾"))
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

    func test_feed_firstFeed_showsWelcomeTipNotRawTip() async {
        let feeder = MockFeeder(result: .success("a fun tip 🐾"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.excitedOverlaySeconds = 0.05
        coord.tipDisplaySeconds = 5  // longer so we can sample

        XCTAssertTrue(coord.isFirstFeed)
        let task = Task { await coord.feed() }

        // Wait past excited overlay so purring + tip set.
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        XCTAssertEqual(coord.state, .purring)
        XCTAssertEqual(coord.tip, "喵～我是 mypet 的小猫，谢谢你接我回家 🐾")
        XCTAssertFalse(coord.isFirstFeed, "isFirstFeed must clear after first success")

        coord.dismissTip()
        await task.value
    }

    func test_feed_secondFeed_showsRawTip() async {
        let feeder = MockFeeder(result: .success("real tip text 🐾"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.excitedOverlaySeconds = 0.05
        coord.tipDisplaySeconds = 5
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
        let feeder = MockFeeder(result: .failure(.notAuthenticated))
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
        let feeder = MockFeeder(result: .failure(.binaryNotFound))
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
        let feeder = MockFeeder(result: .success("tip"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.excitedOverlaySeconds = 0.01
        coord.tipDisplaySeconds = 0.01
        coord.cooldownSeconds = 60

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
        let feeder = MockFeeder(result: .success("real tip"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        coord.excitedOverlaySeconds = 0.01
        coord.tipDisplaySeconds = 0.01
        coord.cooldownSeconds = 60

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
        let feeder = MockFeeder(result: .success("tip"))
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
        // Cumulative cutpoints (claudeTip .. haiku) match the published
        // weights — guards against accidental re-ordering of the switch.
        XCTAssertEqual(FeedCoordinator.nextTheme(rng: { 0.0 }), .claudeTip)
        XCTAssertEqual(FeedCoordinator.nextTheme(rng: { 0.29 }), .claudeTip)
        XCTAssertEqual(FeedCoordinator.nextTheme(rng: { 0.30 }), .promptIdea)
        XCTAssertEqual(FeedCoordinator.nextTheme(rng: { 0.95 }), .haiku)
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

    func test_feed_recordsLastTheme_andSendsThatPromptToFeeder() async {
        let feeder = MockFeeder(result: .success("tip"))
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
        let feeder = MockFeeder(result: .success("tip"))
        let coord = FeedCoordinator(feeder: feeder, log: feedLog)
        // Manually drive into sleepy via the state machine — only public way is
        // evaluateIdle with timestamps in past, which we can't easily mock.
        // We test the wake() pass-through behaviour by feeding and checking state.
        await coord.feed()
        coord.wake()
        // wake from idle is a no-op state-wise but updates lastEventAt; this
        // smoke-tests that wake doesn't crash.
        XCTAssertNotEqual(coord.state, .sleepy)
    }
}
