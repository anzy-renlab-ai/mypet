import XCTest
import AppKit
@testable import MyPet

/// Smoke tests for `MouseMonitor`. The global NSEvent monitor itself is
/// system-driven and can't easily be exercised from a unit test — these
/// just guard the basic plumbing (instantiation, defaults, callback wiring).
@MainActor
final class MouseMonitorTests: XCTestCase {

    func test_init_doesNotCrash() {
        let w = PetWindow()
        let monitor = MouseMonitor(window: w)
        XCTAssertNotNil(monitor)
    }

    func test_initial_cursorPos_isNil() {
        let w = PetWindow()
        let monitor = MouseMonitor(window: w)
        XCTAssertNil(monitor.cursorPos)
    }

    func test_onDoubleClick_callbackIsSettable() {
        let w = PetWindow()
        let monitor = MouseMonitor(window: w)
        // Default callback is a no-op closure — make sure assigning works
        // and we don't trip a Sendable / capture issue.
        var called = false
        monitor.onDoubleClick = { called = true }
        // Manually fire the callback to confirm wiring.
        monitor.onDoubleClick()
        XCTAssertTrue(called)
    }

    func test_deinit_removesEventMonitors() {
        // Indirectly: instantiate + drop the monitor; if NSEvent.removeMonitor
        // is not called, the global monitors will leak — but we can't directly
        // observe that. This test just ensures deinit runs without crashing.
        weak var weakMonitor: MouseMonitor?
        autoreleasepool {
            let w = PetWindow()
            let m = MouseMonitor(window: w)
            weakMonitor = m
            _ = m  // silence unused warning, will deinit at scope end
        }
        XCTAssertNil(weakMonitor, "MouseMonitor should be deallocated; event monitors are leaking if not")
    }
}
