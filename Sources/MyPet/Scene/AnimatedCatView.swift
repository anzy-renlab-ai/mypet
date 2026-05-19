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
        v.imageFrameStyle = .none
        v.translatesAutoresizingMaskIntoConstraints = true
        v.autoresizingMask = [.width, .height]
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

    /// Try APNG first, fall back to PNG, and finally fall back to cat-idle
    /// if neither exists. Ensures the cat is NEVER invisible — a missing
    /// state-specific asset (e.g. during a pipeline regeneration) just
    /// shows the idle pose instead of a blank window.
    private func loadImage() -> NSImage? {
        let candidates: [URL?] = [
            Bundle.module.url(forResource: resourceName, withExtension: "apng"),
            Bundle.module.url(forResource: resourceName, withExtension: "png"),
            Bundle.module.url(forResource: "cat-idle", withExtension: "apng"),
            Bundle.module.url(forResource: "cat-idle", withExtension: "png"),
        ]
        guard let u = candidates.compactMap({ $0 }).first,
              let img = NSImage(contentsOf: u)
        else { return nil }
        // Constrain to a 96pt bounding box while preserving aspect ratio.
        // A flat 96×96 squashes non-square APNGs (e.g. cat-sleeping is a
        // horizontal curled-ball, ~1.5:1 — forcing square stretched it).
        let original = img.size
        let scale = 96 / max(original.width, original.height)
        img.size = NSSize(
            width: original.width * scale,
            height: original.height * scale
        )
        return img
    }
}
