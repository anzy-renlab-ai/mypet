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

    func test_init_isMovableByWindowBackgroundFalse() {
        // v0.1 locks cat to bottom-right; v0.2 enables drag
        let w = PetWindow()
        XCTAssertFalse(w.isMovableByWindowBackground)
    }

    func test_init_contentSize_is140x120pt() {
        // Compact cat-sized window
        let w = PetWindow()
        XCTAssertEqual(w.frame.size, NSSize(width: 140, height: 120))
    }

    func test_placeBottomRight_respects24ptMargin() {
        let w = PetWindow()
        w.placeBottomRight()
        guard let screen = NSScreen.main else {
            return XCTFail("No main screen for test")
        }
        let visible = screen.visibleFrame
        let expectedX = visible.maxX - 140 - 24
        let expectedY = visible.minY + 24
        XCTAssertEqual(w.frame.origin.x, expectedX, accuracy: 0.5)
        XCTAssertEqual(w.frame.origin.y, expectedY, accuracy: 0.5)
    }
}
