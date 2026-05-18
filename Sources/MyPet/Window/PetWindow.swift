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

    /// Timer that fires once the user stops moving the window. windowDidMove
    /// keeps resetting it during a drag; on rest, we snap to the nearest edge.
    private var snapDebounce: Timer?

    deinit {
        snapDebounce?.invalidate()
        snapDebounce = nil
    }

    func windowDidMove(_ notification: Notification) {
        snapDebounce?.invalidate()
        snapDebounce = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.snapToNearestEdgeIfClose() }
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
    /// Animated, respects `snapMargin`.
    func snap(to edge: Edge) {
        guard let screen = self.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var f = frame
        switch edge {
        case .top:    f.origin.y = visible.maxY - f.size.height - snapMargin
        case .bottom: f.origin.y = visible.minY + snapMargin
        case .left:   f.origin.x = visible.minX + snapMargin
        case .right:  f.origin.x = visible.maxX - f.size.width - snapMargin
        }
        setFrame(f, display: true, animate: true)
    }

    /// Re-anchor the bottom-right corner after a resize.
    func placeBottomRight() {
        guard let screen = NSScreen.main ?? screen else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 24
        let size = frame.size
        setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - margin,
            y: visible.minY + margin
        ))
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
