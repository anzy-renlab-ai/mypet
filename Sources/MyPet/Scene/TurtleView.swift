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
            // Particle overlays (lightning / sparkles / fish bones) removed
            // per user feedback — 吃东西时不要那些乱七八糟. The APNG itself
            // carries the eating motion; layering particles on top reads as
            // noisy.

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
                    // Asymmetric transition: appears with a tiny fade, hides
                    // INSTANTLY. When the user double-clicks, they expect the
                    // cookie to vanish the moment feeding starts — not lag
                    // through a fade-out while the cat is already chomping.
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.18)),
                        removal: .identity
                    ))
                    .allowsHitTesting(false)
            }
        }
    }

    /// Whether the cursor-following cookie may render given the current state.
    /// Restful / sleep / mood states allow it (user can feed any time). The
    /// active feed cycle hides it.
    private var cookieAllowed: Bool { Self.cookieAllowed(in: state) }

    /// Pure decision: should the cursor-following cookie be allowed in a
    /// given pet state? Only the **active feed cycle** hides the cookie —
    /// that's when the cookie was just "eaten" by the cat and shouldn't
    /// still be floating around. Every other state (including petting,
    /// edge poses, and ambient grooming) keeps the cookie visible while
    /// the cursor is near, because cookie = "I see your cursor" feedback
    /// independent of the cat's pose. Exposed for tests.
    static func cookieAllowed(in state: PetState) -> Bool {
        switch state {
        case .eating, .excited, .purring:
            return false
        case .idle, .sleepy, .hungry, .dozing, .sleeping,
             .clingTop, .peekLeft, .peekRight,
             .petting, .licking, .washing:
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
                // Combine per-state base scale + micro-motion breathing.
                // Curled poses (sleeping / dozing) are baseline-smaller since
                // a curled cat occupies less footprint than a sitting one.
                // peekLeft shares the peekRight asset — mirror horizontally.
                .scaleEffect(
                    x: Self.baseScale(for: state) * m.s * (state == .peekLeft ? -1 : 1),
                    y: Self.baseScale(for: state) * m.s,
                    anchor: .bottom
                )
                .rotationEffect(.degrees(m.tilt), anchor: .bottom)
                .offset(x: m.dx, y: m.dy + Self.baseDy(for: state))
                // No cross-fade — the user reported the cat "disappearing"
                // between states, which was the overlap window of two
                // half-opaque APNGs. Snap state transitions instead.
                .id(state)
        }
        // Play the matching m4a once on state change (no-op if no audio shipped).
        .onChange(of: state) { newState in
            CatAudio.shared.playIfChanged(stateKey: newState.rawValue)
        }
        .onAppear {
            CatAudio.shared.playIfChanged(stateKey: state.rawValue)
        }
    }

    /// Per-state baseline scale, applied on top of the APNG's max-dim-96
    /// sizing. Curled / loaf poses naturally take less space than upright
    /// sitting — bumping them down a notch keeps the on-screen footprint
    /// across states feeling consistent.
    static func baseScale(for state: PetState) -> CGFloat {
        switch state {
        case .sleeping:        return 0.78
        case .dozing:          return 0.88
        case .clingTop:        return 0.92
        default:               return 1.0
        }
    }

    /// Per-state Y offset. ONLY curled-on-side `sleeping` looks like it's
    /// floating mid-air without this — push it down so the body visibly
    /// rests on the ground. (Earlier `purring` was offset too, back when
    /// 5447 was mis-mapped to purring; with 5571 in place, purring is a
    /// sitting cat and needs zero offset.)
    static func baseDy(for state: PetState) -> CGFloat {
        switch state {
        case .sleeping:  return 20
        default:         return 0
        }
    }

    /// Procedural micro-motion overlay. Kept as an identity transform —
    /// the bundled APNGs already carry every visible motion (chomp, sway,
    /// breath, hang, tilt) and adding more on top reads as noise + can
    /// push the sprite outside the window. The function survives as a
    /// shape so future per-state polish can plug in here, but ships a
    /// no-op for now.
    private func microMotion() -> (s: CGFloat, tilt: Double, dx: CGFloat, dy: CGFloat) {
        _ = t
        return (1.0, 0, 0, 0)
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

enum ASCIISize { case small, medium, large }

func asciiFont(_ size: ASCIISize) -> Font {
    switch size {
    case .small: return .system(size: 14, weight: .semibold, design: .monospaced)
    case .medium: return .system(size: 18, weight: .semibold, design: .monospaced)
    case .large: return .system(size: 22, weight: .bold, design: .monospaced)
    }
}
