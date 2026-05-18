import SwiftUI

/// Cute desktop cat. Move the mouse near it → a token cookie follows the cursor.
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
    /// Cursor position in the window's content coords, supplied by the
    /// app-level `MouseMonitor` (since the window is click-through and can't
    /// receive hover events itself). `nil` when cursor is outside the window.
    let cursorPos: CGPoint?

    init(state: PetState, excited: Bool = false, cursorPos: CGPoint? = nil) {
        self.state = state
        self.excited = excited
        self.cursorPos = cursorPos
    }

    /// Approach-zone radius in points. Cursor inside this → cookie shows.
    private let approachRadius: CGFloat = 80

    /// True when the externally-provided cursor is near enough to the cat
    /// to merit drawing the following cookie.
    private var cursorInZone: Bool {
        guard let p = cursorPos else { return false }
        let cx: CGFloat = 90, cy: CGFloat = 110
        let dx = p.x - cx, dy = p.y - cy
        return dx * dx + dy * dy <= approachRadius * approachRadius
    }

    var body: some View {
        // Single TimelineView always running. .animation = 60fps; the cat
        // micro-motion is procedural so cost is just a few transforms per frame.
        TimelineView(.animation) { ctx in
            content(at: ctx.date)
        }
        .contentShape(Rectangle())
        .frame(width: 180, height: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("小猫")
        .accessibilityHint("双击喂它一口 token")
        .animation(.easeInOut(duration: 0.2), value: state)
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        let t = date.timeIntervalSinceReferenceDate

        ZStack {
            // Only particle effect remaining outside the cat — sprite-baked
            // overlays (zZz, ♡, ✨) already exist inside each frame's drawing.
            if state == .eating || state == .excited {
                ParticleField(at: t, state: state).allowsHitTesting(false)
            }

            VStack(spacing: 2) {
                Spacer(minLength: 0)
                CuteCatFace(state: state, t: t)
                    .frame(width: 96, height: 96)
                Spacer().frame(height: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Cursor-following token cookie. Only shows during "resting"
            // states where feeding is a meaningful next action. Hidden during
            // the active feed cycle (eating → excited → purring) because the
            // cookie was just "eaten" — having it still floating around would
            // contradict the chomp animation.
            if let pos = cursorPos, cursorInZone, cookieAllowed {
                FollowingToken(t: t)
                    .position(x: pos.x, y: pos.y)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.18), value: cookieVisibilityKey)
    }

    /// Whether the cursor-following cookie may render given the current state.
    /// Restful / sleep / mood states allow it (user can feed any time). The
    /// active feed cycle hides it.
    private var cookieAllowed: Bool {
        switch state {
        case .eating, .excited, .purring,
             .clingTop, .peekLeft, .peekRight,
             .petting, .licking, .washing:
            return false
        case .idle, .sleepy, .hungry, .dozing, .sleeping:
            return true
        }
    }

    /// Combined animation key — re-evaluates whenever cursor presence OR
    /// state-driven allowance changes, so SwiftUI animates the fade-out
    /// when feed starts (state flips before cursor leaves).
    private var cookieVisibilityKey: Bool {
        !cursorInZone || !cookieAllowed
    }
}

// MARK: - The cat itself: APNG-driven, theme-mapped

/// Renders a state-specific animated cat. Asset mapping is read from
/// `CatTheme` (bundled `theme.json` → falls back to `CatTheme.default`).
/// `AnimatedCatView` plays APNG natively via NSImageView; PNG fallback
/// for any state whose APNG hasn't been generated yet.
struct CuteCatFace: View {
    let state: PetState
    let t: TimeInterval

    /// Loaded once per process — themes don't change at runtime today.
    private static let theme: CatTheme = CatTheme.load()

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let resource = Self.theme.resourceName(for: state.rawValue)
            let m = microMotion()
            AnimatedCatView(resourceName: resource)
                .frame(width: s, height: s)
                // Subtle realistic ground shadow only — no halo / glow.
                .shadow(color: .black.opacity(0.22),
                        radius: s * 0.06, x: 0, y: s * 0.04)
                // peekLeft shares the peekRight asset — mirror it horizontally.
                .scaleEffect(x: m.sx * (state == .peekLeft ? -1 : 1),
                             y: m.sy,
                             anchor: .bottom)
                .rotationEffect(.degrees(m.tilt), anchor: .bottom)
                .offset(x: m.dx, y: m.dy)
                // Cross-fade between states (0.5s) — outgoing APNG fades while
                // incoming APNG fades in. The brief overlap softens the cut
                // when the previous video's end pose doesn't match the next
                // video's start pose.
                .transition(.opacity)
                .id(state)
        }
        .animation(.easeInOut(duration: 0.5), value: state)
        // Play the matching m4a once on state change (no-op if no audio shipped).
        .onChange(of: state) { newState in
            CatAudio.shared.playIfChanged(stateKey: newState.rawValue)
        }
        .onAppear {
            CatAudio.shared.playIfChanged(stateKey: state.rawValue)
        }
    }

    /// Procedural micro-motion: breath + tilt + bob. Tuned subtle —
    /// motion should support the (eventual APNG) sprite, not fight with it.
    /// APNG itself owns the visible motion; this layer adds tiny living
    /// energy to whatever frame is currently shown.
    private func microMotion() -> (sx: CGFloat, sy: CGFloat, tilt: Double, dx: CGFloat, dy: CGFloat) {
        switch state {
        case .idle:
            let breath = CGFloat(sin(t * 1.2)) * 0.012
            return (1.0 + breath, 1.0 - breath * 0.5, sin(t * 0.5) * 0.5, 0, 0)
        case .eating:
            let chomp = CGFloat(abs(sin(t * 5.5)))
            return (1.0 - chomp * 0.03, 1.0 + chomp * 0.03, 0, 0, -chomp * 1.5)
        case .excited:
            let bounce = CGFloat(abs(sin(t * 3.8)))
            return (1.0 + bounce * 0.04, 1.0 + bounce * 0.05, 0, 0, -bounce * 6)
        case .purring:
            let purr = CGFloat(sin(t * 2.6)) * 0.018
            return (1.0 + purr, 1.0 - purr * 0.5, 0, 0, 0)
        case .sleepy, .dozing:
            let nap = CGFloat(sin(t * 0.7)) * 0.010
            return (1.0 + nap, 1.0 - nap, sin(t * 0.35) * 1.0 - 2, 0, 0)
        case .sleeping:
            let snore = CGFloat(sin(t * 0.5)) * 0.015
            return (1.0 + snore, 1.0 - snore * 0.4, -4, 0, 0)
        case .hungry:
            return (1.0, 1.0, sin(t * 0.5) * 0.5, sin(t * 0.9) * 1.5, 0)
        case .clingTop:
            // Body sway like a hanging weight.
            let sway = CGFloat(sin(t * 1.4)) * 0.025
            return (1.0 + sway, 1.0 - sway * 0.4, sin(t * 1.4) * 6, 0, 0)
        case .peekLeft, .peekRight:
            // Curious head bob, no body translation.
            return (1.0, 1.0, sin(t * 1.1) * 1.2, 0, 0)
        case .petting:
            // Tilt-relaxed bliss.
            let purr = CGFloat(sin(t * 2.0)) * 0.012
            return (1.0 + purr, 1.0 - purr * 0.5, sin(t * 0.7) * 1.0 + 4, 0, 0)
        case .licking, .washing:
            // Focused grooming — minimal body motion, the asset itself does
            // the head/paw choreography.
            let breath = CGFloat(sin(t * 1.0)) * 0.008
            return (1.0 + breath, 1.0 - breath * 0.5, 0, 0, 0)
        }
    }

}

// MARK: - Following token cookie

/// A claude-shaped cookie that lazily trails the cursor when it's near the
/// cat. Gentle bob + soft warm halo. `t` drives the wobble so we don't own
/// a separate clock.
private struct FollowingToken: View {
    let t: TimeInterval

    private static let cookieImage: NSImage? = {
        if let url = Bundle.module.url(forResource: "cookie", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            FileHandle.standardError.write("[cookie] loaded \(url.lastPathComponent) \(img.size)\n".data(using: .utf8)!)
            return img
        }
        FileHandle.standardError.write("[cookie] FAILED to load cookie.png from Bundle.module\n".data(using: .utf8)!)
        return nil
    }()

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [
                    Color(red: 0.88, green: 0.55, blue: 0.36).opacity(0.45),
                    Color(red: 0.88, green: 0.55, blue: 0.36).opacity(0)
                ], center: .center, startRadius: 6, endRadius: 24))
                .frame(width: 30, height: 30)
                .blur(radius: 1.5)

            Group {
                if let img = Self.cookieImage {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Text("🍪").font(.system(size: 16))
                }
            }
            .frame(width: 22, height: 22)
            .rotationEffect(.degrees(sin(t * 2.6) * 9 + sin(t * 1.1) * 3))
            .scaleEffect(1.0 + CGFloat(sin(t * 3.0)) * 0.04)
            .offset(
                x: CGFloat(sin(t * 1.7)) * 1.5,
                y: CGFloat(sin(t * 2.4)) * 2.5
            )
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
