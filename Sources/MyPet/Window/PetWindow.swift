import AppKit
import SwiftUI

final class PetWindow: NSWindow {

    /// Tests + no-arg construction.
    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 140, height: 120),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
    }

    /// Production: takes a SwiftUI root view as the cat container.
    convenience init(rootView: AnyView) {
        self.init()
        let host = NSHostingView(rootView: rootView)
        host.frame = NSRect(x: 0, y: 0, width: 140, height: 120)
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
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
    }

    func placeBottomRight() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 24
        let size = frame.size
        let origin = NSPoint(
            x: visible.maxX - size.width - margin,
            y: visible.minY + margin
        )
        setFrameOrigin(origin)
    }
}
