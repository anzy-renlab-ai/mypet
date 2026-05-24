import XCTest
@testable import MyPet

final class PetStateTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let m = PetStateMachine()
        XCTAssertEqual(m.state, .idle)
        XCTAssertFalse(m.excited)
    }

    // MARK: - Happy path: feed → eating → excited → purring → idle

    func test_startFeed_setsEating() {
        var m = PetStateMachine()
        m.startFeed()
        XCTAssertEqual(m.state, .eating)
    }

    func test_feedSucceeded_setsExcitedOverlay() {
        var m = PetStateMachine()
        m.startFeed()
        m.feedSucceeded()
        XCTAssertEqual(m.state, .excited)
        XCTAssertTrue(m.excited)
    }

    func test_excitedDidFinish_transitionsToPurring() {
        var m = PetStateMachine()
        m.startFeed()
        m.feedSucceeded()
        m.excitedDidFinish()
        XCTAssertEqual(m.state, .purring)
        XCTAssertFalse(m.excited)
    }

    func test_purringDidFinish_returnsToIdle() {
        var m = PetStateMachine()
        m.startFeed()
        m.feedSucceeded()
        m.excitedDidFinish()
        m.purringDidFinish()
        XCTAssertEqual(m.state, .idle)
    }

    // MARK: - Error path

    func test_feedFailed_setsHungry() {
        var m = PetStateMachine()
        m.startFeed()
        m.feedFailed()
        XCTAssertEqual(m.state, .hungry)
    }

    // MARK: - Idle transitions

    func test_evaluateIdleTransitions_setsSleepy_after2HoursNoEvents() {
        var m = PetStateMachine(sleepyAfter: 2 * 3600, hungryAfter: 24 * 3600)
        let now = Date()
        // Successful feed 1 hour ago, then idle for 3 hours
        m.startFeed(now: now.addingTimeInterval(-3 * 3600))
        m.feedSucceeded(now: now.addingTimeInterval(-3 * 3600))
        m.excitedDidFinish(now: now.addingTimeInterval(-3 * 3600))
        m.purringDidFinish(now: now.addingTimeInterval(-3 * 3600))
        m.evaluateIdleTransitions(now: now)
        XCTAssertEqual(m.state, .sleepy)
    }

    func test_evaluateIdleTransitions_setsHungry_after24h() {
        var m = PetStateMachine()
        let now = Date()
        // Fed >24h ago
        m.startFeed(now: now.addingTimeInterval(-25 * 3600))
        m.feedSucceeded(now: now.addingTimeInterval(-25 * 3600))
        m.excitedDidFinish(now: now.addingTimeInterval(-25 * 3600))
        m.purringDidFinish(now: now.addingTimeInterval(-25 * 3600))
        m.evaluateIdleTransitions(now: now)
        XCTAssertEqual(m.state, .hungry)
    }

    func test_evaluateIdleTransitions_hungryWinsOverSleepy() {
        var m = PetStateMachine(sleepyAfter: 2 * 3600, hungryAfter: 24 * 3600)
        let now = Date()
        m.startFeed(now: now.addingTimeInterval(-25 * 3600))
        m.feedSucceeded(now: now.addingTimeInterval(-25 * 3600))
        m.excitedDidFinish(now: now.addingTimeInterval(-25 * 3600))
        m.purringDidFinish(now: now.addingTimeInterval(-25 * 3600))
        m.evaluateIdleTransitions(now: now)
        XCTAssertEqual(m.state, .hungry, "Hungry trumps sleepy when both apply")
    }

    func test_evaluateIdleTransitions_neverFed_doesNotGoHungry() {
        var m = PetStateMachine()
        // Distant past = never fed; sleepyAfter trips first
        m.evaluateIdleTransitions(now: Date())
        XCTAssertNotEqual(m.state, .hungry, "Hungry requires a prior feed event")
    }

    func test_evaluateIdleTransitions_doesNotTransitionFromNonIdle() {
        var m = PetStateMachine()
        m.startFeed()
        m.evaluateIdleTransitions(now: Date().addingTimeInterval(100_000))
        XCTAssertEqual(m.state, .eating, "eating should not be overridden by idle timer")
    }

    // MARK: - Wake

    func test_wake_fromSleepy_returnsIdle() {
        var m = PetStateMachine()
        m.startFeed()
        m.feedSucceeded()
        m.excitedDidFinish()
        m.purringDidFinish()
        // 90s: past sleepyAfter (60s) but before dozeAfter (150s) and
        // hungryAfter (30min) — isolates the sleepy state.
        m.evaluateIdleTransitions(now: Date().addingTimeInterval(90))
        XCTAssertEqual(m.state, .sleepy)
        m.wake()
        XCTAssertEqual(m.state, .idle)
    }

    func test_wake_fromHungry_returnsIdle() {
        var m = PetStateMachine()
        m.startFeed()
        m.feedSucceeded()
        m.excitedDidFinish()
        m.purringDidFinish()
        m.evaluateIdleTransitions(now: Date().addingTimeInterval(25 * 3600))
        XCTAssertEqual(m.state, .hungry)
        m.wake()
        XCTAssertEqual(m.state, .idle)
    }

    func test_wake_fromEating_doesNotInterrupt() {
        var m = PetStateMachine()
        m.startFeed()
        m.wake()
        XCTAssertEqual(m.state, .eating, "Wake should not interrupt active feed")
    }

    // MARK: - Edge states

    func test_enterEdge_fromIdle_setsClingTop() {
        var m = PetStateMachine()
        XCTAssertTrue(m.enterEdge(.clingTop))
        XCTAssertEqual(m.state, .clingTop)
    }

    func test_enterEdge_doesNotOverrideFeedCycle() {
        var m = PetStateMachine()
        m.startFeed()
        XCTAssertFalse(m.enterEdge(.peekRight), "Edge state must not interrupt eating")
        XCTAssertEqual(m.state, .eating)
    }

    func test_leaveEdge_returnsToIdle() {
        var m = PetStateMachine()
        m.enterEdge(.peekLeft)
        XCTAssertEqual(m.state, .peekLeft)
        m.leaveEdge()
        XCTAssertEqual(m.state, .idle)
    }

    func test_enterEdge_rejectsNonEdgeStates() {
        var m = PetStateMachine()
        XCTAssertFalse(m.enterEdge(.eating))
        XCTAssertEqual(m.state, .idle, "Non-edge states must not be allowed via enterEdge")
    }

    // MARK: - Petting

    func test_enterPetting_fromIdle_setsPetting() {
        var m = PetStateMachine()
        XCTAssertTrue(m.enterPetting())
        XCTAssertEqual(m.state, .petting)
    }

    func test_enterPetting_blockedDuringFeedCycle() {
        var m = PetStateMachine()
        m.startFeed()
        XCTAssertFalse(m.enterPetting())
        XCTAssertEqual(m.state, .eating)
    }

    func test_leavePetting_returnsToIdle() {
        var m = PetStateMachine()
        m.enterPetting()
        m.leavePetting()
        XCTAssertEqual(m.state, .idle)
    }

    // MARK: - Grooming

    func test_enterGrooming_licking_fromIdle() {
        var m = PetStateMachine()
        XCTAssertTrue(m.enterGrooming(.licking))
        XCTAssertEqual(m.state, .licking)
    }

    func test_enterGrooming_blockedFromSleepy() {
        var m = PetStateMachine(sleepyAfter: 1, hungryAfter: 24 * 3600)
        m.evaluateIdleTransitions(now: Date().addingTimeInterval(10))
        XCTAssertEqual(m.state, .sleepy)
        XCTAssertFalse(m.enterGrooming(.washing), "Grooming only from idle, not sleepy")
        XCTAssertEqual(m.state, .sleepy)
    }

    func test_enterGrooming_rejectsNonGroomingStates() {
        var m = PetStateMachine()
        XCTAssertFalse(m.enterGrooming(.idle))
        XCTAssertFalse(m.enterGrooming(.eating))
        XCTAssertEqual(m.state, .idle)
    }

    func test_groomingDidFinish_returnsToIdle() {
        var m = PetStateMachine()
        m.enterGrooming(.washing)
        m.groomingDidFinish()
        XCTAssertEqual(m.state, .idle)
    }
}
