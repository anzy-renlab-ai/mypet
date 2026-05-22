import XCTest
@testable import MyPet

/// One test per documented user operation path in the README.
///
/// Path IDs match the user-facing documentation table:
///   A — launch / activation
///   B — mouse hover (no click)
///   C — click / double-click
///   D — feed cycle
///   F — sleep progression
///   G — mood (hungry)
///   J — personality moments (grooming)
///   H — spatial edge states
///   I — menubar
///   K — onboarding
///   Z — invariants + cookie display rules
///
/// Paths that require UI hosting or system events (A1-A4 window placement
/// on physical screens; C1-C2 system click-through; K1-K3 onboarding UI;
/// I7 cmd-Q) are NOT covered here — they're called out at the bottom of
/// each section as `// UI-only:` notes for manual verification.
@MainActor
final class UserPathTests: XCTestCase {

    var feedLog: FeedLog!
    var tmpURL: URL!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mypet-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tmpURL = dir.appendingPathComponent("feed-log.json")
        feedLog = FeedLog(url: tmpURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpURL.deletingLastPathComponent())
    }

    private func makeCoord(
        tip: String = "claude-returned tip",
        cooldown: TimeInterval = 0
    ) -> FeedCoordinator {
        let feeder = FeedCoordinatorTests.MockFeeder(tipResult: .success(tip))
        let c = FeedCoordinator(feeder: feeder, log: feedLog)
        c.excitedOverlaySeconds = 0.05
        // 0.5s, not 30: tests sample the tip mid-window with ≤0.4s sleeps, so
        // 0.5s keeps the tip alive for every assertion while a fully-awaited
        // feed() returns in ~0.55s instead of ~30s (was the D7 long pole).
        c.tipDisplaySeconds = 0.5
        // 0.5s reject-tip window: outlasts the ≤0.4s mid-window samples in the
        // cooldown tests while collapsing the production 2.5s wait.
        c.cooldownTipSeconds = 0.5
        c.cooldownSeconds = cooldown
        return c
    }

    // MARK: - A. Launch / activation
    // A1-A4 cover window-placement against physical NSScreens and are UI-only.
    // The pure machine is just idle on init — covered by Z1.

    // MARK: - B. Mouse hover (no click)

    /// B3: cursor lingers on cat ≥1s → petting state.
    /// (The 1s dwell timer is in PetRootView's .task; here we just check
    /// the underlying setPetting(true) transition.)
    func test_B3_hoverEnter_setsPetting() {
        let c = makeCoord()
        c.setPetting(true)
        XCTAssertEqual(c.state, .petting)
    }

    /// B4: while petting, calling setPetting(true) again is idempotent.
    func test_B4_petting_idempotent() {
        let c = makeCoord()
        c.setPetting(true)
        c.setPetting(true)
        XCTAssertEqual(c.state, .petting)
    }

    /// B5: cursor leaves cat body → exit petting → idle.
    func test_B5_hoverLeave_exitsPetting() {
        let c = makeCoord()
        c.setPetting(true)
        c.setPetting(false)
        XCTAssertEqual(c.state, .idle)
    }

    /// B6: cookie hidden when cursor outside approach zone.
    /// (Pure rule — cookieAllowed(in: .idle) = true, but the cursor must
    /// also be in-zone for it to actually render.)
    func test_B6_cookieRule_inIdle() {
        XCTAssertTrue(TurtleView.cookieAllowed(in: .idle))
    }

    /// B7: cookie stays visible across all hover-driven states.
    func test_B7_cookieStaysVisible_acrossHoverStates() {
        for s in [PetState.idle, .petting, .sleepy, .hungry, .dozing, .sleeping,
                  .clingTop, .peekLeft, .peekRight, .licking, .washing] {
            XCTAssertTrue(TurtleView.cookieAllowed(in: s),
                          "Cookie must keep following cursor in \(s)")
        }
    }

    // MARK: - C. Click / double-click
    // C1, C2 (single-click pass-through) are OS-level — verified by manual test
    // that `ignoresMouseEvents = true` on PetWindow.
    // Already covered: PetWindowTests.test_init_setsIgnoresMouseEventsTrue.

    /// C3: double-click triggers feed → state goes through eating.
    func test_C3_doubleClick_entersFeedCycle() async {
        let c = makeCoord()
        let t = Task { await c.feed() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue([.eating, .excited].contains(c.state),
                      "Mid-cycle should be eating/excited, got \(c.state)")
        t.cancel()
    }

    /// C4: single click while tip is showing → dismiss.
    func test_C4_singleClick_dismissesTip() async {
        let c = makeCoord()
        let t = Task { await c.feed() }
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(c.state, .purring)
        XCTAssertNotNil(c.tip)
        c.dismissTip()                                    // simulates click in window
        XCTAssertEqual(c.state, .idle)
        XCTAssertNil(c.tip)
        t.cancel()
    }

    /// C5: concurrent double-click while eating → second feed is a no-op.
    func test_C5_concurrentDoubleClick_secondIsNoop() async {
        let feeder = FeedCoordinatorTests.MockFeeder(tipResult: .success("tip"))
        let c = FeedCoordinator(feeder: feeder, log: feedLog)
        c.excitedOverlaySeconds = 0.05
        c.tipDisplaySeconds = 0.05
        c.cooldownTipSeconds = 0.05   // t2 may race into the cooldown path; don't wait 2.5s

        let t1 = Task { await c.feed() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        let t2 = Task { await c.feed() }  // should bail because state == .eating
        _ = await t1.value
        _ = await t2.value
        XCTAssertEqual(feeder.callCount, 1,
                       "Second feed during eating must not call the feeder again")
    }

    // MARK: - D. Feed cycle

    /// D1: feed starts → cookie hides immediately.
    func test_D1_feedStarts_cookieHidesImmediately() async {
        let c = makeCoord()
        XCTAssertTrue(TurtleView.cookieAllowed(in: c.state))
        let t = Task { await c.feed() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertFalse(TurtleView.cookieAllowed(in: c.state),
                       "Cookie must be hidden during feed cycle")
        t.cancel()
    }

    /// D2: feeder is called exactly once per feed invocation.
    func test_D2_feederCalledOncePerFeed() async {
        let feeder = FeedCoordinatorTests.MockFeeder(tipResult: .success("tip"))
        let c = FeedCoordinator(feeder: feeder, log: feedLog)
        c.excitedOverlaySeconds = 0.05
        c.tipDisplaySeconds = 0.05
        await c.feed()
        XCTAssertEqual(feeder.callCount, 1)
    }

    /// D3 + D4: feed success transitions through excited → purring with the
    /// REAL LLM tip text (no welcome-message override).
    func test_D3_D4_feedSuccess_purringWithRealTip() async {
        let c = makeCoord(tip: "fresh tip from claude ✨")
        let t = Task { await c.feed() }
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(c.state, .purring)
        XCTAssertEqual(c.tip, "fresh tip from claude ✨",
                       "Tip must be the real claude response, not a canned welcome")
        t.cancel()
    }

    /// D5: tip auto-dismisses after tipDisplaySeconds.
    func test_D5_tipAutoDismiss() async {
        let c = makeCoord()
        c.tipDisplaySeconds = 0.1
        await c.feed()
        // Allow auto-dismiss to fire
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNil(c.tip, "Tip should auto-clear after tipDisplaySeconds")
        XCTAssertEqual(c.state, .idle)
    }

    /// D6: user explicit dismiss clears tip + state.
    func test_D6_explicitDismiss() async {
        let c = makeCoord()
        let t = Task { await c.feed() }
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNotNil(c.tip)
        c.dismissTip()
        XCTAssertNil(c.tip)
        XCTAssertEqual(c.state, .idle)
        t.cancel()
    }

    /// D7: cooldown surfaces a "digesting" tip rather than silently rejecting.
    /// The cooldown branch sleeps ~2.5s before clearing the tip; sample
    /// mid-window rather than awaiting the full feed Task.
    func test_D7_cooldown_surfacesTip() async {
        let c = makeCoord(cooldown: 60)
        await c.feed()
        c.dismissTip()
        let t = Task { await c.feed() }
        try? await Task.sleep(nanoseconds: 400_000_000)   // 0.4s into 2.5s window
        XCTAssertTrue(c.tip?.contains("消化") ?? false,
                      "Cooldown must show 消化 tip, got: \(String(describing: c.tip))")
        await t.value
    }

    /// D8: feed error → hungry state with friendly text. handleFailure
    /// awaits tipDisplaySeconds before clearing — sample mid-window.
    func test_D8_feedError_setsHungry() async {
        let feeder = FeedCoordinatorTests.MockFeeder(result: .failure(.notAuthenticated))
        let c = FeedCoordinator(feeder: feeder, log: feedLog)
        c.excitedOverlaySeconds = 0.05
        c.tipDisplaySeconds = 0.5   // outlasts the 0.3s assertion below; was 5
        let t = Task { await c.feed() }
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(c.state, .hungry)
        XCTAssertNotNil(c.tip, "Error must produce a user-facing tip")
        await t.value
    }

    // MARK: - F. Sleep progression (passive decay)

    /// F1: 5min idle → sleepy.
    func test_F1_idle_to_sleepy() {
        var m = PetStateMachine(sleepyAfter: 1)
        m.evaluateIdleTransitions(now: Date().addingTimeInterval(2))
        XCTAssertEqual(m.state, .sleepy)
    }

    /// F2: 15min idle → dozing (from sleepy).
    func test_F2_sleepy_to_dozing() {
        var m = PetStateMachine(sleepyAfter: 1)
        let now = Date()
        m.evaluateIdleTransitions(now: now.addingTimeInterval(2))
        XCTAssertEqual(m.state, .sleepy)
        m.evaluateIdleTransitions(now: now.addingTimeInterval(m.dozeAfter + 2))
        XCTAssertEqual(m.state, .dozing)
    }

    /// F3: 30min idle → sleeping (from dozing).
    func test_F3_dozing_to_sleeping() {
        var m = PetStateMachine(sleepyAfter: 1)
        let now = Date()
        m.evaluateIdleTransitions(now: now.addingTimeInterval(2))
        m.evaluateIdleTransitions(now: now.addingTimeInterval(m.dozeAfter + 2))
        m.evaluateIdleTransitions(now: now.addingTimeInterval(m.sleepAfter + 2))
        XCTAssertEqual(m.state, .sleeping)
    }

    /// F4: any interaction (here: startFeed) wakes from sleep.
    func test_F4_anyInteraction_wakes() {
        var m = PetStateMachine(sleepyAfter: 1)
        let now = Date()
        m.evaluateIdleTransitions(now: now.addingTimeInterval(2))
        m.evaluateIdleTransitions(now: now.addingTimeInterval(m.dozeAfter + 2))
        m.evaluateIdleTransitions(now: now.addingTimeInterval(m.sleepAfter + 2))
        XCTAssertEqual(m.state, .sleeping)
        m.startFeed()
        XCTAssertEqual(m.state, .eating, "feed must override deep sleep")
    }

    // MARK: - G. Mood

    /// G1: 24h since last successful feed → hungry.
    func test_G1_24h_noFeed_hungry() {
        var m = PetStateMachine(hungryAfter: 1)
        let now = Date()
        // Simulate a feed long ago (>hungryAfter), then check
        m.startFeed(now: now.addingTimeInterval(-10))
        m.feedSucceeded(now: now.addingTimeInterval(-10))
        m.excitedDidFinish(now: now.addingTimeInterval(-10))
        m.purringDidFinish(now: now.addingTimeInterval(-10))
        m.evaluateIdleTransitions(now: now)
        XCTAssertEqual(m.state, .hungry)
    }

    // MARK: - J. Personality moments

    /// J1: grooming triggered from idle → enters licking.
    func test_J1_grooming_licking_fromIdle() {
        let c = makeCoord()
        c.triggerGrooming(.licking)
        XCTAssertEqual(c.state, .licking)
    }

    /// J1b: grooming washing.
    func test_J1b_grooming_washing_fromIdle() {
        let c = makeCoord()
        c.triggerGrooming(.washing)
        XCTAssertEqual(c.state, .washing)
    }

    /// J2: grooming finishes → returns to idle.
    func test_J2_grooming_finish_returnsIdle() {
        let c = makeCoord()
        c.triggerGrooming(.licking)
        c.groomingDidFinish()
        XCTAssertEqual(c.state, .idle)
    }

    /// Grooming is blocked from any non-idle state (non-intrusive rule).
    func test_J_grooming_blockedOutsideIdle() {
        let c = makeCoord()
        c.setEdgeState(.clingTop)
        c.triggerGrooming(.licking)
        XCTAssertEqual(c.state, .clingTop, "Grooming must not interrupt edge state")
    }

    // MARK: - H. Spatial edge states (menubar-triggered)

    func test_H1_clingTop() {
        let c = makeCoord()
        c.setEdgeState(.clingTop)
        XCTAssertEqual(c.state, .clingTop)
    }

    func test_H2_peekLeft() {
        let c = makeCoord()
        c.setEdgeState(.peekLeft)
        XCTAssertEqual(c.state, .peekLeft)
    }

    func test_H3_peekRight() {
        let c = makeCoord()
        c.setEdgeState(.peekRight)
        XCTAssertEqual(c.state, .peekRight)
    }

    func test_H4_releaseEdge_returnsIdle() {
        let c = makeCoord()
        c.setEdgeState(.peekLeft)
        c.setEdgeState(nil)
        XCTAssertEqual(c.state, .idle)
    }

    /// Edge → edge transitions allowed (user drags from top to side).
    func test_H_edgeToEdge_transitionsAllowed() {
        let c = makeCoord()
        c.setEdgeState(.clingTop)
        c.setEdgeState(.peekRight)
        XCTAssertEqual(c.state, .peekRight)
    }

    // MARK: - I. Menubar
    // The menubar items wire to callbacks (onShowOnboarding / onQuit / onBringHere
    // / onSnapTo). The wiring is constructor-injected, so the unit test is just
    // "the callback I pass gets stored + invocable" — too trivial to test in
    // isolation. The integration is covered by manual click-through.
    //
    // We DO test what each callback's *destination* does:

    /// I3: "Bring cat to this screen" → calls petWindow.placeBottomRight()
    /// which always re-anchors to the main screen's bottom-right corner,
    /// flush with the dock area so the cat "stands on" the screen edge.
    func test_I3_bringHere_movesToBottomRight() {
        let w = PetWindow()
        w.setFrameOrigin(.zero)
        w.placeBottomRight()
        guard let screen = NSScreen.main else { return XCTFail("no main screen") }
        let visible = screen.visibleFrame
        XCTAssertEqual(w.frame.maxX, visible.maxX - 16, accuracy: 0.5)
        XCTAssertEqual(w.frame.minY, visible.minY + 32, accuracy: 0.5)
    }

    /// I4 top: window's top edge flush with the visible-top (cling pose).
    func test_I4_snapTop() {
        let w = PetWindow()
        guard let screen = NSScreen.main else { return XCTFail("no screen") }
        let visible = screen.visibleFrame
        w.snap(to: .top)
        XCTAssertEqual(w.frame.maxY, visible.maxY, accuracy: 0.5,
                       "snap(.top) should put the window's top flush with screen top")
    }

    /// I4 left: half the window is pushed past the visible-left edge.
    func test_I4_snapLeft_pushesHalfOffscreen() {
        let w = PetWindow()
        guard let screen = NSScreen.main else { return XCTFail("no screen") }
        let visible = screen.visibleFrame
        w.snap(to: .left)
        let expectedX = visible.minX - w.frame.size.width / 2
        XCTAssertEqual(w.frame.minX, expectedX, accuracy: 0.5,
                       "snap(.left) should push half the window past the left edge for the peek effect")
    }

    /// I4 right: half the window is pushed past the visible-right edge.
    func test_I4_snapRight_pushesHalfOffscreen() {
        let w = PetWindow()
        guard let screen = NSScreen.main else { return XCTFail("no screen") }
        let visible = screen.visibleFrame
        w.snap(to: .right)
        let expectedX = visible.maxX - w.frame.size.width / 2
        XCTAssertEqual(w.frame.minX, expectedX, accuracy: 0.5,
                       "snap(.right) should push half the window past the right edge for the peek effect")
    }

    // MARK: - Z. Invariants

    /// Z1: fresh state machine = idle.
    func test_Z1_initialState_isIdle() {
        XCTAssertEqual(PetStateMachine().state, .idle)
    }

    /// Z2: feed cycle is sacrosanct.
    func test_Z2_feedCycle_uninterruptible() async {
        let c = makeCoord()
        let t = Task { await c.feed() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        c.setEdgeState(.clingTop)
        c.setPetting(true)
        c.triggerGrooming(.licking)
        XCTAssertFalse([.clingTop, .petting, .licking].contains(c.state),
                       "None of edge/petting/grooming should override the feed cycle")
        t.cancel()
    }

    /// Z3: edge state can co-exist with sleep but blocks petting/grooming entry.
    func test_Z3_edgeBlocksPetting() {
        let c = makeCoord()
        c.setEdgeState(.peekLeft)
        c.setPetting(true)
        XCTAssertEqual(c.state, .peekLeft)
    }

    func test_Z3_edgeBlocksGrooming() {
        let c = makeCoord()
        c.setEdgeState(.clingTop)
        c.triggerGrooming(.licking)
        XCTAssertEqual(c.state, .clingTop)
    }

    /// Z4: every PetState case has a CatTheme mapping (covered fully by
    /// CatThemeTests, smoke-check here too).
    func test_Z4_themeCoverage() {
        let theme = CatTheme.default
        for s in [PetState.idle, .eating, .excited, .purring,
                  .hungry, .sleepy, .dozing, .sleeping,
                  .clingTop, .peekLeft, .peekRight,
                  .petting, .licking, .washing] {
            XCTAssertNotNil(theme.states[s.rawValue], "missing mapping: \(s)")
        }
    }

    /// Z5: AnimatedCatView never returns nil — always falls back to cat-idle.
    func test_Z5_animatedCatView_alwaysReturnsImage() {
        XCTAssertNotNil(AnimatedCatView(resourceName: "cat-idle").loadImage())
        XCTAssertNotNil(AnimatedCatView(resourceName: "does-not-exist").loadImage(),
                        "Unknown resource must fall back to cat-idle")
    }

    /// Z6: cookie display per state.
    func test_Z6_cookieRules() {
        // Hide cookie during feed cycle:
        XCTAssertFalse(TurtleView.cookieAllowed(in: .eating))
        XCTAssertFalse(TurtleView.cookieAllowed(in: .excited))
        XCTAssertFalse(TurtleView.cookieAllowed(in: .purring))
        // Show in every other state:
        for s in [PetState.idle, .sleepy, .hungry, .dozing, .sleeping,
                  .clingTop, .peekLeft, .peekRight,
                  .petting, .licking, .washing] {
            XCTAssertTrue(TurtleView.cookieAllowed(in: s))
        }
    }

    /// Z7: idle-CPU invariant (#1). The 60fps TimelineView must run ONLY when
    /// the cursor-following cookie is showing — i.e. cursor in zone AND state
    /// allows the cookie. Idle with no cursor near = no animation = static
    /// frame. Regressing this re-burns 60fps when the pet is ignored.
    func test_Z7_needsAnimation_gating() {
        // Cursor far away → never animate, regardless of state.
        for s in [PetState.idle, .sleepy, .hungry, .dozing, .sleeping,
                  .clingTop, .peekLeft, .peekRight, .petting, .licking,
                  .washing, .eating, .excited, .purring] {
            XCTAssertFalse(TurtleView.needsAnimation(state: s, cursorInZone: false),
                           "\(s): no cursor in zone must not animate")
        }
        // Cursor near + cookie-allowed state → animate.
        for s in [PetState.idle, .sleepy, .hungry, .dozing, .sleeping,
                  .clingTop, .peekLeft, .peekRight,
                  .petting, .licking, .washing] {
            XCTAssertTrue(TurtleView.needsAnimation(state: s, cursorInZone: true),
                          "\(s): cursor near + cookie allowed must animate")
        }
        // Cursor near but mid-feed cycle (cookie hidden) → still no animation.
        for s in [PetState.eating, .excited, .purring] {
            XCTAssertFalse(TurtleView.needsAnimation(state: s, cursorInZone: true),
                           "\(s): feed cycle hides cookie, no animation needed")
        }
    }
}
