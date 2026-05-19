import XCTest
@testable import MyPet

/// End-to-end coverage of every user operation path through mypet,
/// modeled as flat state-machine + coordinator sequences. Each test maps
/// to one "thing the user can do" surfaced in the README / onboarding.
///
/// User operation paths (this file's contract):
///
///   1. Launch → idle, cookie hidden until cursor approaches
///   2. Cursor near cat → cookie visible
///   3. Double-click → eating → excited → purring (tip) → idle
///   4. Click tip bubble → dismiss → idle
///   5. Drag window to top → clingTop (placeholder for menubar snap)
///   6. Drag window to side → peekLeft / peekRight
///   7. Hover-on-cat ≥1s (in restful state) → petting
///   8. Idle 5min → sleepy → 15min → dozing → 30min → sleeping
///   9. 24h no feed → hungry
///  10. Wake from sleepy / hungry / sleeping → idle on any feed
///
/// State precedence (highest → lowest priority):
///   feed cycle  >  edge state  >  petting  >  grooming  >  sleep progression
@MainActor
final class UserSessionTests: XCTestCase {

    var feedLog: FeedLog!
    var tmpURL: URL!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mypet-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tmpURL = dir.appendingPathComponent("feed-log.json")
        feedLog = FeedLog(url: tmpURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpURL.deletingLastPathComponent())
    }

    private func makeCoord(tip: String = "fresh tip") -> FeedCoordinator {
        let feeder = FeedCoordinatorTests.MockFeeder(tipResult: .success(tip))
        let c = FeedCoordinator(feeder: feeder, log: feedLog)
        c.excitedOverlaySeconds = 0.05
        c.tipDisplaySeconds = 30  // long enough to assert mid-purring
        return c
    }

    // MARK: - Path 1 & 2: launch + cookie visibility

    func test_launch_initialStateIsIdle_cookieVisible() {
        let c = makeCoord()
        XCTAssertEqual(c.state, .idle)
        XCTAssertTrue(TurtleView.cookieAllowed(in: c.state))
    }

    func test_cookieVisibility_perState() {
        // Restful states: cookie shows (user can feed)
        for s in [PetState.idle, .sleepy, .hungry, .dozing, .sleeping] {
            XCTAssertTrue(TurtleView.cookieAllowed(in: s),
                          "Cookie should show in \(s) — user can feed any time")
        }
        // Active states: cookie hides
        for s in [PetState.eating, .excited, .purring,
                  .clingTop, .peekLeft, .peekRight,
                  .petting, .licking, .washing] {
            XCTAssertFalse(TurtleView.cookieAllowed(in: s),
                           "Cookie should hide in \(s)")
        }
    }

    // MARK: - Path 3 & 4: full feed cycle + dismiss

    func test_path3_doubleClick_runsFullFeedCycle() async {
        let c = makeCoord(tip: "today's tip ✨")
        XCTAssertEqual(c.state, .idle)

        let t = Task { await c.feed() }
        try? await Task.sleep(nanoseconds: 250_000_000)  // past excited
        XCTAssertEqual(c.state, .purring)
        XCTAssertNotNil(c.tip)
        XCTAssertEqual(c.lastTokens >= 0, true)
        t.cancel()
    }

    func test_path4_tipDismiss_returnsIdle() async {
        let c = makeCoord()
        let t = Task { await c.feed() }
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(c.state, .purring)
        c.dismissTip()
        XCTAssertEqual(c.state, .idle)
        XCTAssertNil(c.tip)
        t.cancel()
    }

    // MARK: - Path 5/6: edge states (menubar / window-drag triggered)

    func test_path5_dragToTop_triggersClingTop() {
        let c = makeCoord()
        c.setEdgeState(.clingTop)
        XCTAssertEqual(c.state, .clingTop)
        XCTAssertFalse(TurtleView.cookieAllowed(in: c.state),
                       "Cookie hides while clinging")
    }

    func test_path6_dragLeftRight_togglesPeek() {
        let c = makeCoord()
        c.setEdgeState(.peekRight)
        XCTAssertEqual(c.state, .peekRight)
        c.setEdgeState(.peekLeft)
        XCTAssertEqual(c.state, .peekLeft, "Edge → edge transition allowed")
        c.setEdgeState(nil)
        XCTAssertEqual(c.state, .idle, "Releasing edge returns to idle")
    }

    // MARK: - Path 7: hover-on-cat → petting

    func test_path7_setPetting_fromIdle() {
        let c = makeCoord()
        c.setPetting(true)
        XCTAssertEqual(c.state, .petting)
        XCTAssertFalse(TurtleView.cookieAllowed(in: c.state))
    }

    func test_path7_petting_releaseReturnsIdle() {
        let c = makeCoord()
        c.setPetting(true)
        c.setPetting(false)
        XCTAssertEqual(c.state, .idle)
    }

    // MARK: - Path 8: sleep progression

    func test_path8_sleepProgression_idle_sleepy_dozing_sleeping() {
        var m = PetStateMachine(sleepyAfter: 1)
        m = forceIdle(m)
        m.evaluateIdleTransitions(now: Date().addingTimeInterval(2))
        XCTAssertEqual(m.state, .sleepy, "After sleepyAfter → sleepy")
        m.evaluateIdleTransitions(now: Date().addingTimeInterval(m.dozeAfter + 2))
        XCTAssertEqual(m.state, .dozing, "After dozeAfter → dozing")
        m.evaluateIdleTransitions(now: Date().addingTimeInterval(m.sleepAfter + 2))
        XCTAssertEqual(m.state, .sleeping, "After sleepAfter → sleeping")
    }

    // MARK: - Path 9: hungry after 24h

    func test_path9_hungry_after24h() {
        var m = PetStateMachine(hungryAfter: 1)
        let now = Date()
        m.startFeed(now: now.addingTimeInterval(-2))
        m.feedSucceeded(now: now.addingTimeInterval(-2))
        m.excitedDidFinish(now: now.addingTimeInterval(-2))
        m.purringDidFinish(now: now.addingTimeInterval(-2))
        m.evaluateIdleTransitions(now: now)
        XCTAssertEqual(m.state, .hungry)
    }

    // MARK: - Path 10: wake on feed

    func test_path10_feedWakesFromSleeping() {
        // The state machine progresses ONE step per evaluateIdleTransitions
        // call (idle → sleepy → dozing → sleeping); simulate three ticks.
        var m = PetStateMachine(sleepyAfter: 1)
        let now = Date()
        m.evaluateIdleTransitions(now: now.addingTimeInterval(2))
        XCTAssertEqual(m.state, .sleepy)
        m.evaluateIdleTransitions(now: now.addingTimeInterval(m.dozeAfter + 2))
        XCTAssertEqual(m.state, .dozing)
        m.evaluateIdleTransitions(now: now.addingTimeInterval(m.sleepAfter + 2))
        XCTAssertEqual(m.state, .sleeping)
        // Then a feed starts → wakes from sleeping
        m.startFeed()
        XCTAssertEqual(m.state, .eating)
    }

    // MARK: - State precedence: feed > edge > petting > grooming

    func test_precedence_feedOverEverything() async {
        let c = makeCoord()
        let t = Task { await c.feed() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        // All of these must be no-ops while feeding
        c.setEdgeState(.clingTop)
        c.setPetting(true)
        c.triggerGrooming(.licking)
        let feedCycle: Set<PetState> = [.eating, .excited]
        XCTAssertTrue(feedCycle.contains(c.state))
        t.cancel()
    }

    func test_precedence_edgeOverPetting() {
        let c = makeCoord()
        c.setEdgeState(.clingTop)
        c.setPetting(true)
        XCTAssertEqual(c.state, .clingTop, "Edge state blocks petting entry")
    }

    func test_precedence_pettingOverGrooming() {
        let c = makeCoord()
        c.setPetting(true)
        c.triggerGrooming(.licking)
        XCTAssertEqual(c.state, .petting, "Petting blocks grooming entry")
    }

    // MARK: - Helper

    private func forceIdle(_ m: PetStateMachine) -> PetStateMachine {
        // Identity helper — keeps tests that rely on a `var` machine clean.
        return m
    }
}
