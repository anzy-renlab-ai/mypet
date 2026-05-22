import AppKit
import SwiftUI

final class PetWindow: NSWindow, NSWindowDelegate {

    /// Compact size — cat at center plus a comfortable "approach zone" that
    /// catches the cursor + renders the following token cookie.
    static let compactSize = NSSize(width: 180, height: 180)
    /// Expanded size — room for a tip bubble above the cat.
    static let expandedSize = NSSize(width: 400, height: 360)

    /// Tests + no-arg construction.
    convenience init() {
        self.init(
            contentRect: NSRect(origin: .zero, size: PetWindow.compactSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
    }

    /// Production: takes a SwiftUI root view as the turtle container.
    convenience init(rootView: AnyView) {
        self.init()
        let host = NSHostingView(rootView: rootView)
        host.autoresizingMask = [.width, .height]
        host.frame = NSRect(origin: .zero, size: PetWindow.compactSize)
        contentView = host
    }

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        configure()
    }

    private func configure() {
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        // Click-through window. Single clicks pass straight to the app behind
        // so the cat never blocks the user's work. Double-click → feed is
        // detected by `MouseMonitor` via a global event monitor. To reposition
        // the cat, use the menubar 🐾 → Move submenu (no drag-to-move).
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        delegate = self
    }

    // MARK: - Snap-to-edge after drag

    /// Snap if the dragged window lands within this many points of a screen edge.
    var snapThreshold: CGFloat = 60
    /// Margin from the edge after snapping — keeps the cat from sitting flush.
    var snapMargin: CGFloat = 24
    /// Within this many points of a screen edge → fire `onEdgeState` with the
    /// matching state (clingTop / peekLeft / peekRight). Beyond it → nil.
    var edgeStateThreshold: CGFloat = 32

    /// Callback fired when the window enters or leaves an edge-state zone.
    /// `nil` means the window is no longer near any edge.
    /// Wired in AppDelegate to `coordinator.setEdgeState(_:)`.
    var onEdgeState: ((PetState?) -> Void)?

    /// Timer that fires once the user stops moving the window. windowDidMove
    /// keeps resetting it during a drag; on rest, we snap to the nearest edge.
    private var snapDebounce: Timer?
    /// Last published edge state — debounces redundant callbacks.
    private var lastEdgeState: PetState??

    deinit {
        snapDebounce?.invalidate()
        snapDebounce = nil
    }

    func windowDidMove(_ notification: Notification) {
        // Intentionally empty. Edge-state detection used to live here, but
        // every internal `setFrame` (e.g. tip-bubble expansion) was firing
        // it spuriously — when the window grew to 400 wide its right edge
        // landed inside the 32pt edgeStateThreshold, which then snapped the
        // cat into `peekRight` mid-feed. The user could not have moved the
        // window themselves (ignoresMouseEvents=true), so edge transitions
        // are now driven exclusively from menubar `snap(to:)` calls.
    }

    /// Inspect distance to each screen edge and notify a state transition
    /// when within `edgeStateThreshold`. Top edge → clingTop; left/right →
    /// peekLeft/peekRight. Bottom edge is ignored (cat lives there anyway).
    /// Visible for tests.
    func evaluateEdgeState() {
        guard let screen = self.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let distLeft  = frame.minX - visible.minX
        let distRight = visible.maxX - frame.maxX
        let distTop   = visible.maxY - frame.maxY

        let edge: PetState?
        if distTop < edgeStateThreshold {
            edge = .clingTop
        } else if distLeft < edgeStateThreshold {
            edge = .peekLeft
        } else if distRight < edgeStateThreshold {
            edge = .peekRight
        } else {
            edge = nil
        }

        // Debounce — only fire on actual change.
        if lastEdgeState == nil || lastEdgeState! != edge {
            lastEdgeState = edge
            onEdgeState?(edge)
        }
    }

    /// If the cat sits within `snapThreshold` of any screen edge, snap to that
    /// edge (with `snapMargin` inset) using an animated frame change.
    func snapToNearestEdgeIfClose() {
        guard let screen = self.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var f = frame

        let distLeft = f.minX - visible.minX
        let distRight = visible.maxX - f.maxX
        let distBottom = f.minY - visible.minY
        let distTop = visible.maxY - f.maxY

        // Find the smallest edge distance below the threshold.
        let candidates: [(CGFloat, () -> Void)] = [
            (distLeft,   { f.origin.x = visible.minX + self.snapMargin }),
            (distRight,  { f.origin.x = visible.maxX - f.size.width - self.snapMargin }),
            (distBottom, { f.origin.y = visible.minY + self.snapMargin }),
            (distTop,    { f.origin.y = visible.maxY - f.size.height - self.snapMargin }),
        ]
        guard let winner = candidates.filter({ $0.0 < snapThreshold })
            .min(by: { $0.0 < $1.0 }) else { return }
        winner.1()
        if f == frame { return }
        setFrame(f, display: true, animate: true)
    }

    enum Edge { case top, right, bottom, left }

    /// Explicitly park the cat against one screen edge (menubar action).
    /// Snaps to an edge of the primary display (`NSScreen.main`), matching
    /// `placeBottomRight()`'s documented user preference that the cat lives on
    /// the primary screen regardless of cursor location. Animated.
    ///
    /// Behavior per edge:
    ///   .top    — window's top touches screen top; cat hangs down
    ///             (paired with the upside-down cat-clingTop.apng).
    ///   .left   — HALF the window is pushed offscreen left so the cat
    ///             peeks from the left edge.
    ///   .right  — mirror of .left.
    ///   .bottom — back to the home bottom-right corner with margin.
    func snap(to edge: Edge) {
        guard let s = NSScreen.main ?? self.screen else { return }
        let visible = s.visibleFrame
        var f = frame

        switch edge {
        case .top:
            // Top edge flush with screen top; cat sprite (clingTop pose)
            // is drawn pointing down inside the window.
            f.origin.x = visible.maxX - f.size.width - snapMargin
            f.origin.y = visible.maxY - f.size.height
        case .left:
            // Half the window pushed past the visible-left edge → only the
            // right half is on-screen → cat appears to peek out from the left.
            f.origin.x = visible.minX - f.size.width / 2
            f.origin.y = visible.minY + (visible.height - f.size.height) / 2
        case .right:
            f.origin.x = visible.maxX - f.size.width / 2
            f.origin.y = visible.minY + (visible.height - f.size.height) / 2
        case .bottom:
            f.origin.x = visible.maxX - f.size.width - 16
            f.origin.y = visible.minY + 32
        }
        setFrame(f, display: true, animate: true)
        orderFrontRegardless()
    }

    /// Re-anchor the bottom-right corner after a resize.
    /// Always uses the main screen (NSScreen.main) — user preference: cat
    /// stays on the primary display, never the secondary, regardless of
    /// where the cursor is. The vertical anchor sits the window flush with
    /// the dock area so the cat appears to *stand on* the screen edge
    /// rather than float above it. Forces the window front so it stays
    /// visible even though `ignoresMouseEvents = true` prevents it becoming
    /// key.
    func placeBottomRight() {
        guard let s = NSScreen.main ?? self.screen else { return }
        let visible = s.visibleFrame
        let rightMargin: CGFloat = 16
        let bottomMargin: CGFloat = 32   // raises the cat enough that the paws clear the dock area
        let size = frame.size
        setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - rightMargin,
            y: visible.minY + bottomMargin
        ))
        orderFrontRegardless()
    }

    /// Grow/shrink to fit a tip bubble, keeping the turtle in place.
    /// We anchor by the bottom-right corner of the current frame so the turtle
    /// (drawn at the bottom of the content) doesn't jump.
    func setExpanded(_ expanded: Bool, animate: Bool = true) {
        let newSize = expanded ? PetWindow.expandedSize : PetWindow.compactSize
        if frame.size == newSize { return }
        let oldFrame = frame
        // keep bottom-right fixed
        let newOrigin = NSPoint(
            x: oldFrame.maxX - newSize.width,
            y: oldFrame.minY
        )
        let newFrame = NSRect(origin: newOrigin, size: newSize)
        setFrame(newFrame, display: true, animate: animate)
    }
}
