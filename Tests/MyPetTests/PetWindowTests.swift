import XCTest
import AppKit
@testable import MyPet

@MainActor
final class PetWindowTests: XCTestCase {

    func test_init_isBorderless() {
        let w = PetWindow()
        XCTAssertEqual(w.styleMask, .borderless)
    }

    func test_init_isNotOpaque() {
        let w = PetWindow()
        XCTAssertFalse(w.isOpaque, "Window must be non-opaque so transparent pixels pass clicks through")
    }

    func test_init_hasNoShadow() {
        let w = PetWindow()
        XCTAssertFalse(w.hasShadow, "Shadow looks unnatural on a free-floating sprite")
    }

    func test_init_backgroundIsClear() {
        let w = PetWindow()
        XCTAssertEqual(w.backgroundColor, NSColor.clear)
    }

    func test_init_levelIsStatusBar() {
        let w = PetWindow()
        XCTAssertEqual(w.level, .statusBar, "Cat lives above app windows but below menubar")
    }

    func test_init_collectionBehaviorIncludesCanJoinAllSpaces() {
        let w = PetWindow()
        XCTAssertTrue(w.collectionBehavior.contains(.canJoinAllSpaces))
    }

    func test_init_collectionBehaviorIncludesStationary() {
        let w = PetWindow()
        XCTAssertTrue(w.collectionBehavior.contains(.stationary))
    }

    func test_init_collectionBehaviorIncludesFullScreenAuxiliary() {
        let w = PetWindow()
        XCTAssertTrue(w.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    func test_init_setsIgnoresMouseEventsTrue() {
        // Click-through window — single clicks pass through to whatever app
        // is behind mypet so the cat never blocks the user's work. Feed is
        // triggered by `MouseMonitor` watching a global double-click.
        let w = PetWindow()
        XCTAssertTrue(w.ignoresMouseEvents, "Window must be click-through")
    }

    func test_init_isReleasedWhenClosedFalse() {
        // We want to keep the window object alive across show/hide cycles
        let w = PetWindow()
        XCTAssertFalse(w.isReleasedWhenClosed)
    }

    func test_init_isCompactSizeAtRest() {
        let w = PetWindow()
        XCTAssertEqual(w.frame.size, PetWindow.compactSize)
        XCTAssertEqual(PetWindow.compactSize, NSSize(width: 180, height: 180),
            "Compact size must be wide enough to host the cat + cursor approach zone")
    }

    func test_setExpanded_growsToFitTipBubble() {
        let w = PetWindow()
        w.placeBottomRight()
        let beforeMaxX = w.frame.maxX
        let beforeMinY = w.frame.minY
        w.setExpanded(true, animate: false)
        XCTAssertEqual(w.frame.size, PetWindow.expandedSize)
        // Bottom-right corner stays put so the turtle doesn't jump.
        XCTAssertEqual(w.frame.maxX, beforeMaxX, accuracy: 0.5)
        XCTAssertEqual(w.frame.minY, beforeMinY, accuracy: 0.5)
    }

    func test_setExpanded_false_shrinksBack() {
        let w = PetWindow()
        w.setExpanded(true, animate: false)
        w.setExpanded(false, animate: false)
        XCTAssertEqual(w.frame.size, PetWindow.compactSize)
    }

    func test_ignoresMouseEvents_isTrue() {
        // Click-through window — single clicks pass to the app behind, only
        // a global double-click detector fires feed (see MouseMonitor).
        let w = PetWindow()
        XCTAssertTrue(w.ignoresMouseEvents)
    }

    // MARK: - Snap to edge

    func test_snap_pullsRightEdgeIntoMargin_whenCloseToRight() {
        let w = PetWindow()
        guard let screen = NSScreen.main else { return XCTFail("No main screen") }
        let visible = screen.visibleFrame
        // Place 10pt away from right edge → within 60pt threshold
        let startX = visible.maxX - w.frame.size.width - 10
        w.setFrameOrigin(NSPoint(x: startX, y: visible.minY + 200))
        w.snapToNearestEdgeIfClose()
        let expectedX = visible.maxX - w.frame.size.width - w.snapMargin
        XCTAssertEqual(w.frame.origin.x, expectedX, accuracy: 0.5,
            "Window 10pt from right edge must snap to snapMargin from right")
    }

    func test_snap_isNoOp_whenFarFromAllEdges() {
        let w = PetWindow()
        guard let screen = NSScreen.main else { return XCTFail("No main screen") }
        let visible = screen.visibleFrame
        // Place dead-center
        let cx = visible.minX + (visible.width - w.frame.size.width) / 2
        let cy = visible.minY + (visible.height - w.frame.size.height) / 2
        w.setFrameOrigin(NSPoint(x: cx, y: cy))
        let before = w.frame
        w.snapToNearestEdgeIfClose()
        XCTAssertEqual(w.frame, before,
            "Far from any edge → must not move")
    }

    func test_snap_picksClosestEdge_whenTwoCandidates() {
        let w = PetWindow()
        guard let screen = NSScreen.main else { return XCTFail("No main screen") }
        let visible = screen.visibleFrame
        // 5pt from bottom, 30pt from left — bottom is closer → bottom wins
        w.setFrameOrigin(NSPoint(x: visible.minX + 30, y: visible.minY + 5))
        w.snapToNearestEdgeIfClose()
        XCTAssertEqual(w.frame.origin.y, visible.minY + w.snapMargin, accuracy: 0.5,
            "Closer edge (bottom) should win the snap")
    }

    func test_placeBottomRight_flushWithDockTop() {
        let w = PetWindow()
        w.placeBottomRight()
        guard let s = NSScreen.main else { return XCTFail("No main screen") }
        let visible = s.visibleFrame
        // 16pt right inset, 0 bottom inset (cat "standing on" the dock area).
        let expectedX = visible.maxX - PetWindow.compactSize.width - 16
        let expectedY = visible.minY + 32
        XCTAssertEqual(w.frame.origin.x, expectedX, accuracy: 0.5)
        XCTAssertEqual(w.frame.origin.y, expectedY, accuracy: 0.5)
    }

    // MARK: - Edge-state detection

    /// Captures every `onEdgeState` callback so a test can assert ordering.
    private func setUpEdgeRecorder(_ w: PetWindow) -> () -> [PetState?] {
        var log: [PetState?] = []
        w.onEdgeState = { log.append($0) }
        return { log }
    }

    func test_evaluateEdgeState_nearTop_firesClingTop() {
        let w = PetWindow()
        guard let screen = NSScreen.main else { return XCTFail("No main screen") }
        let visible = screen.visibleFrame
        let recorder = setUpEdgeRecorder(w)

        // Position so frame.maxY is right at the visible top → distTop = 0.
        w.setFrame(NSRect(x: 100, y: visible.maxY - w.frame.height,
                          width: w.frame.width, height: w.frame.height),
                   display: false)
        w.evaluateEdgeState()

        XCTAssertEqual(recorder().last, .clingTop)
    }

    func test_evaluateEdgeState_nearLeft_firesPeekLeft() {
        let w = PetWindow()
        guard let screen = NSScreen.main else { return XCTFail("No main screen") }
        let visible = screen.visibleFrame
        let recorder = setUpEdgeRecorder(w)

        w.setFrame(NSRect(x: visible.minX, y: 200,
                          width: w.frame.width, height: w.frame.height),
                   display: false)
        w.evaluateEdgeState()

        XCTAssertEqual(recorder().last, .peekLeft)
    }

    func test_evaluateEdgeState_nearRight_firesPeekRight() {
        let w = PetWindow()
        guard let screen = NSScreen.main else { return XCTFail("No main screen") }
        let visible = screen.visibleFrame
        let recorder = setUpEdgeRecorder(w)

        w.setFrame(NSRect(x: visible.maxX - w.frame.width, y: 200,
                          width: w.frame.width, height: w.frame.height),
                   display: false)
        w.evaluateEdgeState()

        XCTAssertEqual(recorder().last, .peekRight)
    }

    func test_evaluateEdgeState_centerOfScreen_firesNil() {
        let w = PetWindow()
        guard let screen = NSScreen.main else { return XCTFail("No main screen") }
        let visible = screen.visibleFrame
        let recorder = setUpEdgeRecorder(w)

        // First push to an edge so lastEdgeState is non-nil...
        w.setFrame(NSRect(x: visible.minX, y: 200,
                          width: w.frame.width, height: w.frame.height),
                   display: false)
        w.evaluateEdgeState()
        // ...then move to center → onEdgeState(nil).
        w.setFrame(NSRect(x: visible.midX, y: visible.midY,
                          width: w.frame.width, height: w.frame.height),
                   display: false)
        w.evaluateEdgeState()

        XCTAssertEqual(recorder().last, nil as PetState?,
                       "Center of screen should produce a nil edge-state callback")
    }

    func test_evaluateEdgeState_debouncesIdenticalCalls() {
        let w = PetWindow()
        guard let screen = NSScreen.main else { return XCTFail("No main screen") }
        let visible = screen.visibleFrame
        let recorder = setUpEdgeRecorder(w)

        w.setFrame(NSRect(x: 100, y: visible.maxY - w.frame.height,
                          width: w.frame.width, height: w.frame.height),
                   display: false)
        w.evaluateEdgeState()
        w.evaluateEdgeState()
        w.evaluateEdgeState()

        XCTAssertEqual(recorder().count, 1, "Repeated calls in the same zone must debounce to a single emission")
    }

    // MARK: - Multi-monitor target screen

    /// Must mirror PetWindow.preferredDisplayKey (private). Kept in sync by
    /// test_preferredDisplayKey_matches below would be ideal, but the key is
    /// private; this literal is the contract.
    private static let preferredDisplayKey = "mypet.preferredDisplayID"

    override func tearDown() {
        // Never leak a test preference into the real app's defaults.
        UserDefaults.standard.removeObject(forKey: Self.preferredDisplayKey)
        super.tearDown()
    }

    func test_displayID_isNonNilForMainScreen() {
        guard let main = NSScreen.main else { return XCTFail("No main screen") }
        XCTAssertNotNil(main.displayID, "Every attached screen reports a CGDirectDisplayID")
    }

    func test_targetScreen_defaultsToMain_whenNoPreference() {
        UserDefaults.standard.removeObject(forKey: Self.preferredDisplayKey)
        let w = PetWindow()
        XCTAssertEqual(w.targetScreen?.displayID, NSScreen.main?.displayID,
            "With no stored preference the cat lives on the primary display")
    }

    func test_setPreferredScreen_persistsChoice() {
        guard let main = NSScreen.main else { return XCTFail("No main screen") }
        let w = PetWindow()
        w.setPreferredScreen(main)
        XCTAssertEqual(UserDefaults.standard.object(forKey: Self.preferredDisplayKey) as? UInt32,
                       main.displayID,
            "setPreferredScreen must persist the chosen display's ID")
        XCTAssertEqual(w.targetScreen?.displayID, main.displayID)
    }

    func test_targetScreen_fallsBackToMain_whenStoredDisplayUnplugged() {
        // Simulate the external monitor being gone: store a display ID that
        // matches no attached screen. The cat must NOT strand off-screen — it
        // falls back to the primary display.
        UserDefaults.standard.set(UInt32(0xDEAD_BEEF), forKey: Self.preferredDisplayKey)
        let w = PetWindow()
        XCTAssertNotNil(w.targetScreen, "Unknown stored display must not yield a nil target")
        XCTAssertEqual(w.targetScreen?.displayID, NSScreen.main?.displayID,
            "A stored display that is no longer attached falls back to the primary screen")
    }

    func test_placeBottomRight_usesTargetScreen_afterMove() {
        guard let main = NSScreen.main else { return XCTFail("No main screen") }
        let w = PetWindow()
        w.setPreferredScreen(main)   // resolves to main on a single-display CI
        w.placeBottomRight()
        let visible = main.visibleFrame
        XCTAssertEqual(w.frame.origin.x, visible.maxX - PetWindow.compactSize.width - 16, accuracy: 0.5)
        XCTAssertEqual(w.frame.origin.y, visible.minY + 32, accuracy: 0.5)
    }
}
