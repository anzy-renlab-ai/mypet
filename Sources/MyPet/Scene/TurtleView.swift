import SwiftUI

/// Cute desktop cat. Move the mouse near it → a token coin follows the cursor.
/// Double-click the cat to feed.
///
/// Renders Apple's professionally-drawn cat emojis on top of a soft fluff
/// halo. Per-state expression comes "for free" via emoji swap; surrounding
/// motion (bounce, sway, tilt) + particles + overlay are owned here.
///
/// Invariants preserved:
/// - Zero CPU when fully idle (TimelineView gated by `needsAnimation`)
/// - Single-tap to drag, double-tap to feed; no Timer captured in closures
struct TurtleView: View {
    let state: PetState
    let excited: Bool
    let onFeed: (() -> Void)?

    /// Last known cursor position inside the pet window's coordinate space.
    /// `nil` when cursor is outside the approach zone.
    @State private var cursorPos: CGPoint?

    init(state: PetState, excited: Bool = false, onFeed: (() -> Void)? = nil) {
        self.state = state
        self.excited = excited
        self.onFeed = onFeed
    }

    /// Approach-zone radius in points. Cursor inside this → spawn the
    /// following token coin.
    private let approachRadius: CGFloat = 80

    var body: some View {
        // Single TimelineView always running. .animation = 60fps; the cat
        // micro-motion is procedural so cost is just a few transforms per frame.
        TimelineView(.animation) { ctx in
            content(at: ctx.date)
        }
        .contentShape(Rectangle())
        .frame(width: 180, height: 180)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                // Only "near" the cat counts — quadratic distance check.
                let cx: CGFloat = 90, cy: CGFloat = 110
                let dx = location.x - cx, dy = location.y - cy
                cursorPos = (dx * dx + dy * dy) <= (approachRadius * approachRadius)
                    ? location : nil
            case .ended:
                cursorPos = nil
            }
        }
        .onTapGesture(count: 2) {
            onFeed?()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("小猫")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("双击喂它一口 token")
        .animation(.easeInOut(duration: 0.2), value: state)
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        let t = date.timeIntervalSinceReferenceDate
        let motion = bodyMotion(at: t)

        ZStack {
            if state == .eating || state == .excited {
                ParticleField(at: t, state: state).allowsHitTesting(false)
            }

            // Cat sits at a fixed point inside the approach zone (bottom-center-ish)
            VStack(spacing: 2) {
                if let above = overlayAbove(at: t) {
                    Text(above)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(overlayColor)
                        .opacity(overlayOpacity(at: t))
                } else {
                    Spacer().frame(height: 16)
                }
                Spacer(minLength: 0)
                // CuteCatFace handles per-state procedural motion internally.
                // Don't double-apply transforms here — that was producing a
                // visible compound jitter / ghost outline.
                CuteCatFace(state: state, t: t)
                    .frame(width: 96, height: 96)
                Spacer().frame(height: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Cursor-following token coin (only when cursor is in the zone)
            if let pos = cursorPos {
                FollowingToken(t: t)
                    .position(x: pos.x, y: pos.y)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.18), value: cursorPos == nil)
    }

    private func bodyMotion(at t: TimeInterval) -> (sway: CGFloat, bounce: CGFloat, scale: CGFloat, tilt: Double) {
        switch state {
        case .idle:
            return (CGFloat(sin(t * 0.6)) * 1.5, 0, 1.0 + sin(t * 0.9) * 0.02, 0)
        case .eating:
            // Quick rhythmic chomp bob
            return (0, CGFloat(abs(sin(t * 6.0))) * -4, 1.0 + abs(sin(t * 6.0)) * 0.04, sin(t * 4.0) * 4.0)
        case .excited:
            return (0, CGFloat(abs(sin(t * 4.5))) * -10, 1.0 + abs(sin(t * 4.5)) * 0.10, 0)
        case .purring:
            return (0, 0, 1.0 + sin(t * 1.4) * 0.05, 0)
        case .sleepy:
            return (0, 0, 1.0 + sin(t * 0.5) * 0.02, -6)
        case .hungry:
            return (CGFloat(sin(t * 0.8)) * 2.0, 0, 1.0, 0)
        }
    }

    private func overlayAbove(at t: TimeInterval) -> String? {
        switch state {
        case .sleepy:
            let phase = Int(t * 0.7) % 2
            return phase == 0 ? "z  Z  z" : "Z  z  Z"
        case .excited: return "✦  ✧  ✦"
        case .purring: return "♡    ♡"
        case .hungry: return "·  ·  ·"
        case .eating: return "⚡  ⚡"
        default: return nil
        }
    }

    private func overlayOpacity(at t: TimeInterval) -> Double {
        switch state {
        case .sleepy: return 0.5 + 0.4 * (sin(t * 2.0) + 1) / 2
        case .excited: return 0.7 + 0.3 * abs(sin(t * 4.0))
        default: return 1.0
        }
    }

    private var overlayColor: Color {
        switch state {
        case .sleepy: return .gray.opacity(0.8)
        case .excited: return Color(red: 1.00, green: 0.78, blue: 0.30)
        case .purring: return Color(red: 0.98, green: 0.55, blue: 0.65)
        case .hungry: return Color(red: 0.75, green: 0.55, blue: 0.40)
        case .eating: return Color(red: 1.00, green: 0.72, blue: 0.32)
        default: return Color.white.opacity(0.5)
        }
    }
}

// MARK: - The cat itself: PNG sprite, no halo, no emoji

/// Renders a state-specific cat PNG. Multi-variant packs cross-fade.
/// If a state has no bundled sprite, falls back to idle. If neither exists,
/// renders nothing (the slot is empty until user drops a PNG in).
struct CuteCatFace: View {
    let state: PetState
    let t: TimeInterval
    /// 0–1, kept on the signature for source compat (unused now that halo is gone).
    var hoverProgress: Double = 0

    /// Per-state frame pool + slow cross-fade between random picks.
    @State private var frames: [NSImage] = []
    @State private var currentIdx: Int = 0

    /// Seconds between cross-fade switches.
    private let dwellSeconds: Double = 5.0
    /// Fade duration (seconds).
    private let fadeSeconds: Double = 1.5

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            if !frames.isEmpty {
                let m = microMotion()
                Image(nsImage: frames[currentIdx % frames.count])
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: s, height: s)
                    .id(currentIdx)
                    .transition(.opacity.animation(.easeInOut(duration: fadeSeconds)))
                    .scaleEffect(x: m.sx, y: m.sy, anchor: .bottom)
                    .rotationEffect(.degrees(m.tilt), anchor: .bottom)
                    .offset(x: m.dx, y: m.dy)
            }
        }
        .task(id: state) {
            frames = Self.allSprites(for: state)
            currentIdx = 0
            guard frames.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(dwellSeconds * 1_000_000_000))
                if Task.isCancelled { break }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: fadeSeconds)) {
                        currentIdx = (currentIdx + 1) % frames.count
                    }
                }
            }
        }
    }

    /// Procedural micro-motion: breath + tilt + bob. Per-state tuning.
    /// Magnitudes tuned for visible-but-not-distracting motion.
    private func microMotion() -> (sx: CGFloat, sy: CGFloat, tilt: Double, dx: CGFloat, dy: CGFloat) {
        switch state {
        case .idle:
            // Visible breathing: ±3% scale + 1.5° gentle head tilt
            let breath = CGFloat(sin(t * 1.4)) * 0.030
            let sway = CGFloat(sin(t * 0.8)) * 2.0
            return (1.0 + breath, 1.0 - breath * 0.6, sin(t * 0.6) * 1.5, sway, 0)
        case .eating:
            // Pronounced chomp: scale + dip
            let chomp = CGFloat(abs(sin(t * 6.0)))
            return (1.0 - chomp * 0.10, 1.0 + chomp * 0.10, sin(t * 3.0) * 3.0, 0, -chomp * 4)
        case .excited:
            // Big jump
            let bounce = CGFloat(abs(sin(t * 4.5)))
            return (1.0 + bounce * 0.12, 1.0 + bounce * 0.14, 0, 0, -bounce * 14)
        case .purring:
            // Slow rhythmic purr scale
            let purr = CGFloat(sin(t * 3.0)) * 0.04
            return (1.0 + purr, 1.0 - purr * 0.5, sin(t * 1.2) * 0.5, 0, 0)
        case .sleepy:
            // Head tilted, slow breath
            let nap = CGFloat(sin(t * 0.8)) * 0.020
            return (1.0 + nap, 1.0 - nap, sin(t * 0.4) * 2.0 - 6, 0, 0)
        case .hungry:
            // Visible side-to-side sway
            let sway = CGFloat(sin(t * 1.2))
            return (1.0, 1.0, sin(t * 0.6) * 1.0, sway * 4.0, 0)
        }
    }

    /// All sprite variants for the state from the bundle. Cascade:
    /// `cat-<state>.png` + numbered variants → if none → `cat-idle.png` pack.
    /// Returns empty if not even idle exists.
    static func allSprites(for state: PetState) -> [NSImage] {
        let direct = loadVariants(slug: stateSlug(state))
        if !direct.isEmpty { return direct }
        // Fallback: use idle pack for any state that has no dedicated sprite yet
        return loadVariants(slug: "idle")
    }

    private static func loadVariants(slug: String) -> [NSImage] {
        let base = "cat-\(slug)"
        var images: [NSImage] = []
        if let url = Bundle.module.url(forResource: base, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            images.append(img)
        }
        for i in 2...9 {
            if let url = Bundle.module.url(forResource: "\(base)-\(i)", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                images.append(img)
            }
        }
        return images
    }

    /// Random first pick (kept as a convenience).
    static func pickSprite(for state: PetState) -> NSImage? {
        allSprites(for: state).randomElement()
    }

    private static func stateSlug(_ state: PetState) -> String {
        switch state {
        case .idle: return "idle"
        case .eating: return "eating"
        case .excited: return "excited"
        case .purring: return "purring"
        case .sleepy: return "sleepy"
        case .hungry: return "hungry"
        }
    }

    /// Tiny breathing scale-jitter for purring/idle.
    private var emojiScale: CGFloat {
        switch state {
        case .purring: return 1.0 + CGFloat(sin(t * 3.0)) * 0.04
        case .eating: return 1.0
        case .idle: return 1.0 + CGFloat(sin(t * 1.6)) * 0.02
        default: return 1.0
        }
    }
}

// MARK: - Following token coin

/// A coin that lazily trails the cursor when it's near the cat. Gentle bob
/// + faint glow makes it feel alive. `t` drives the wobble so we don't own
/// a separate clock.
private struct FollowingToken: View {
    let t: TimeInterval
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [
                    Color(red: 1.00, green: 0.80, blue: 0.30).opacity(0.5),
                    Color(red: 1.00, green: 0.80, blue: 0.30).opacity(0)
                ], center: .center, startRadius: 4, endRadius: 18))
                .frame(width: 36, height: 36)
                .blur(radius: 1.5)
            Text("🪙")
                .font(.system(size: 18))
                .scaleEffect(1.0 + CGFloat(sin(t * 3.0)) * 0.05)
                .offset(y: CGFloat(sin(t * 2.4)) * 1.5)
        }
    }
}

// MARK: - Particles (chomp / sparkle)

private struct ParticleField: View {
    let at: TimeInterval
    let state: PetState

    var body: some View {
        Canvas { ctx, size in
            for p in particleSpec() {
                let cycle = (at * p.speed + p.phase).truncatingRemainder(dividingBy: 1.0)
                let alpha = 1.0 - cycle
                // Particles drift upward from above the cat (not across the face)
                let baseY = size.height * 0.25
                let yOffset = -CGFloat(cycle) * size.height * 0.35
                ctx.draw(
                    Text(p.glyph).font(.system(size: 14, weight: .bold))
                        .foregroundColor(color.opacity(alpha)),
                    at: CGPoint(x: size.width * CGFloat(p.x),
                                y: baseY + yOffset)
                )
            }
        }
    }

    private var color: Color {
        state == .excited
            ? Color(red: 1.00, green: 0.78, blue: 0.30)
            : Color(red: 1.0, green: 0.62, blue: 0.40)
    }

    private struct Particle { let x: Double; let phase: Double; let speed: Double; let glyph: String }

    private func particleSpec() -> [Particle] {
        switch state {
        case .eating:
            return [
                .init(x: 0.25, phase: 0.0, speed: 0.7, glyph: "🐟"),
                .init(x: 0.55, phase: 0.4, speed: 0.7, glyph: "✨"),
                .init(x: 0.80, phase: 0.7, speed: 0.7, glyph: "🐟"),
            ]
        case .excited:
            return [
                .init(x: 0.20, phase: 0.0, speed: 1.0, glyph: "✦"),
                .init(x: 0.40, phase: 0.25, speed: 1.0, glyph: "✧"),
                .init(x: 0.60, phase: 0.50, speed: 1.0, glyph: "★"),
                .init(x: 0.80, phase: 0.75, speed: 1.0, glyph: "✦"),
            ]
        default: return []
        }
    }
}

enum ASCIISize { case small, medium, large }

func asciiFont(_ size: ASCIISize) -> Font {
    switch size {
    case .small: return .system(size: 14, weight: .semibold, design: .monospaced)
    case .medium: return .system(size: 18, weight: .semibold, design: .monospaced)
    case .large: return .system(size: 22, weight: .bold, design: .monospaced)
    }
}
