import AppKit
import SwiftUI

final class PetWindow: NSWindow {

    /// Compact size — just the turtle. Used at rest.
    static let compactSize = NSSize(width: 100, height: 100)
    /// Expanded size — room for a tip bubble above the turtle.
    static let expandedSize = NSSize(width: 340, height: 220)

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
        // Draggable: click-drag moves the turtle. Plain hover (no click) still
        // triggers the feed timer (handled in TurtleView); a DragGesture there
        // cancels the timer when an actual drag starts.
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
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
