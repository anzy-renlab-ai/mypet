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

    func test_init_doesNotSetIgnoresMouseEvents() {
        // Critical: relying on macOS default per-pixel hit testing
        // for borderless transparent windows. See D13 / pet-therapy reference.
        let w = PetWindow()
        XCTAssertFalse(w.ignoresMouseEvents, "Must not block clicks on opaque pixels")
    }

    func test_init_isReleasedWhenClosedFalse() {
        // We want to keep the window object alive across show/hide cycles
        let w = PetWindow()
        XCTAssertFalse(w.isReleasedWhenClosed)
    }

    func test_init_isCompactSizeAtRest() {
        let w = PetWindow()
        XCTAssertEqual(w.frame.size, PetWindow.compactSize)
        XCTAssertEqual(PetWindow.compactSize, NSSize(width: 100, height: 100))
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

    func test_isMovableByWindowBackground_isTrue() {
        // Desktop pet should be draggable.
        let w = PetWindow()
        XCTAssertTrue(w.isMovableByWindowBackground)
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

    func test_placeBottomRight_respects24ptMargin() {
        let w = PetWindow()
        w.placeBottomRight()
        guard let screen = NSScreen.main else {
            return XCTFail("No main screen for test")
        }
        let visible = screen.visibleFrame
        let expectedX = visible.maxX - PetWindow.compactSize.width - 24
        let expectedY = visible.minY + 24
        XCTAssertEqual(w.frame.origin.x, expectedX, accuracy: 0.5)
        XCTAssertEqual(w.frame.origin.y, expectedY, accuracy: 0.5)
    }
}
