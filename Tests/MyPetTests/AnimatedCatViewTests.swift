import XCTest
import AppKit
@testable import MyPet

@MainActor
final class AnimatedCatViewTests: XCTestCase {

    /// loadImage must always return SOMETHING for a known state — even if
    /// the state-specific APNG isn't shipped yet, it falls back to cat-idle.
    func test_loadImage_idleAlwaysLoads() {
        let v = AnimatedCatView(resourceName: "cat-idle")
        XCTAssertNotNil(v.loadImage(), "cat-idle must always be loadable")
    }

    /// Unknown state name → fallback to cat-idle (don't return nil and
    /// leave the user staring at a blank window).
    func test_loadImage_unknownResource_fallsBackToIdle() {
        let v = AnimatedCatView(resourceName: "cat-totally-not-a-state")
        XCTAssertNotNil(v.loadImage(),
                        "Unknown resource must fall back to cat-idle, not return nil")
    }

    /// Returned image preserves aspect ratio of the source (constrained to
    /// a 96pt bounding box). Sleeping APNG is wider than tall — should not
    /// be force-squashed to square.
    func test_loadImage_preservesAspectRatio_inA96Box() {
        let v = AnimatedCatView(resourceName: "cat-idle")
        guard let img = v.loadImage() else { return XCTFail("idle must load") }
        let larger = max(img.size.width, img.size.height)
        XCTAssertEqual(larger, 96, accuracy: 0.5,
                       "Larger dimension should be exactly 96 after normalization")
        let smaller = min(img.size.width, img.size.height)
        XCTAssertLessThanOrEqual(smaller, 96)
        XCTAssertGreaterThan(smaller, 0)
    }
}
