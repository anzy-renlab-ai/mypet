import AppKit
import Combine

/// Watches global mouse events so the pet window can be **click-through**
/// (`ignoresMouseEvents = true`) yet still:
///
///   • detect double-clicks landing on the cat → trigger a feed
///   • track cursor position relative to the window → drive the cookie follower
///
/// `NSEvent.addGlobalMonitorForEvents` fires for events going to OTHER
/// applications (including ones passing through our click-through window),
/// without consuming them — exactly what we want.
///
/// Side note: single clicks pass straight through to the app behind, which
/// is the desired behavior. Double-clicks also pass through *and* fire feed
/// here — a minor side effect we accept in exchange for not requiring
/// Accessibility permission (CGEventTap suppression would).
@MainActor
final class MouseMonitor: ObservableObject {

    /// Cursor position in the window's content coordinate system (origin
    /// bottom-left, y-up — matching AppKit). `nil` when cursor is outside
    /// the window frame.
    @Published private(set) var cursorPos: CGPoint?

    /// Fired on a double-click landing inside the window frame.
    var onDoubleClick: () -> Void = {}

    /// Fired on a *single* click landing inside the window frame, with the
    /// click position in window content coordinates. AppDelegate uses this
    /// to dismiss the tip bubble — SwiftUI's onTapGesture can't fire with
    /// `ignoresMouseEvents=true`, so we route the dismiss through here.
    var onSingleClick: (CGPoint) -> Void = { _ in }

    private weak var window: NSWindow?
    private var tokens: [Any] = []

    init(window: NSWindow) {
        self.window = window
        install()
    }

    deinit {
        for t in tokens { NSEvent.removeMonitor(t) }
    }

    private func install() {
        let movedToken = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved],
            handler: { [weak self] event in
                Task { @MainActor [weak self] in self?.handleMouseMoved(event) }
            }
        )
        if let t = movedToken { tokens.append(t) }

        let downToken = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown],
            handler: { [weak self] event in
                Task { @MainActor [weak self] in self?.handleMouseDown(event) }
            }
        )
        if let t = downToken { tokens.append(t) }
    }

    private func handleMouseMoved(_ event: NSEvent) {
        let screen = NSEvent.mouseLocation
        guard let win = window else {
            if cursorPos != nil { cursorPos = nil }
            return
        }
        if win.frame.contains(screen) {
            // AppKit windows already use a y-up coordinate system, so
            // a simple offset converts screen → content coords.
            cursorPos = CGPoint(x: screen.x - win.frame.minX,
                                y: screen.y - win.frame.minY)
        } else if cursorPos != nil {
            cursorPos = nil
        }
    }

    private func handleMouseDown(_ event: NSEvent) {
        let screen = NSEvent.mouseLocation
        guard let win = window, win.frame.contains(screen) else { return }
        let local = CGPoint(x: screen.x - win.frame.minX,
                            y: screen.y - win.frame.minY)
        if event.clickCount == 2 {
            onDoubleClick()
        } else if event.clickCount == 1 {
            onSingleClick(local)
        }
    }
}
