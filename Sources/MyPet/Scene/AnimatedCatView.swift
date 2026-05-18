import SwiftUI
import AppKit

/// Plays an APNG (Animated PNG) asset bundled via Bundle.module.
///
/// Why NSViewRepresentable: SwiftUI's `Image(nsImage:)` only renders the
/// first frame of an APNG. NSImageView with `animates = true` decodes the
/// full frame sequence and plays it at the encoded frame durations.
///
/// Pattern borrowed in concept from clawd-on-desk (which uses HTML <img>
/// in Electron for the same effect). Clean-room Swift implementation.
struct AnimatedCatView: NSViewRepresentable {
    /// Resource name without extension (e.g. "cat-idle"). Falls back to
    /// .png if .apng not found, so a still PNG still renders during the
    /// migration period before real APNGs ship.
    let resourceName: String

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.imageAlignment = .alignCenter
        v.animates = true
        v.image = loadImage()
        return v
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        // Reload when resourceName changes (state transition).
        if context.coordinator.lastName != resourceName {
            context.coordinator.lastName = resourceName
            nsView.image = loadImage()
            nsView.animates = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(lastName: resourceName)
    }

    final class Coordinator {
        var lastName: String
        init(lastName: String) { self.lastName = lastName }
    }

    /// Try APNG first, fall back to PNG so we ship something during
    /// the asset migration period.
    private func loadImage() -> NSImage? {
        if let url = Bundle.module.url(forResource: resourceName, withExtension: "apng"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let url = Bundle.module.url(forResource: resourceName, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return nil
    }
}
