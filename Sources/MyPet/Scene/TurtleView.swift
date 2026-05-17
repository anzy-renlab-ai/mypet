import SwiftUI

/// Cute desktop cat. Hover 1s to feed.
///
/// Renders Apple's professionally-drawn cat emojis on top of a soft fluff
/// halo. Per-state expression comes "for free" via emoji swap; surrounding
/// motion (bounce, sway, tilt) + particles + overlay are owned here.
///
/// Invariants preserved:
/// - Zero CPU when fully idle (TimelineView gated by `needsAnimation`)
/// - Hover uses `.task(id:)`, never `Timer`
struct TurtleView: View {
    let state: PetState
    let excited: Bool
    let onFeed: (() -> Void)?

    @State private var hoverToken: UUID?
    @State private var hoverStart: Date?

    private let petDuration: TimeInterval = 1.0

    init(state: PetState, excited: Bool = false, onFeed: (() -> Void)? = nil) {
        self.state = state
        self.excited = excited
        self.onFeed = onFeed
    }

    private var needsAnimation: Bool {
        hoverToken != nil || state != .idle
    }

    var body: some View {
        Group {
            if needsAnimation {
                TimelineView(.animation) { context in
                    content(at: context.date)
                }
            } else {
                content(at: Date())
            }
        }
        .contentShape(Circle())
        .frame(width: 80, height: 80)
        .onHover { isHovering in
            if isHovering {
                hoverStart = Date()
                hoverToken = UUID()
            } else {
                hoverStart = nil
                hoverToken = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { _ in
                    hoverStart = nil
                    hoverToken = nil
                }
        )
        .task(id: hoverToken) {
            guard hoverToken != nil else { return }
            try? await Task.sleep(nanoseconds: UInt64(petDuration * 1_000_000_000))
            if !Task.isCancelled {
                onFeed?()
                hoverStart = nil
                hoverToken = nil
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("小猫")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("鼠标停留 1 秒喂它一口 token")
        .animation(.easeInOut(duration: 0.2), value: state)
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        let t = date.timeIntervalSinceReferenceDate
        let motion = bodyMotion(at: t)
        let progress = hoverProgress(now: date)

        ZStack {
            if state == .eating || state == .excited {
                ParticleField(at: t, state: state).allowsHitTesting(false)
            }

            VStack(spacing: 2) {
                if let above = overlayAbove(at: t) {
                    Text(above)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(overlayColor)
                        .opacity(overlayOpacity(at: t))
                } else {
                    Spacer().frame(height: 16)
                }

                CuteCatFace(state: state, t: t, hoverProgress: progress)
                    .frame(width: 60, height: 60)
                    .scaleEffect(motion.scale, anchor: .bottom)
                    .rotationEffect(.degrees(motion.tilt), anchor: .bottom)
                    .offset(x: motion.sway, y: motion.bounce)

                if progress > 0 {
                    ProgressRing(progress: progress).frame(width: 22, height: 6)
                } else {
                    Spacer().frame(height: 6)
                }
            }
        }
    }

    private func hoverProgress(now: Date) -> Double {
        guard let start = hoverStart else { return 0 }
        return min(1.0, now.timeIntervalSince(start) / petDuration)
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

// MARK: - The cat itself: emoji on a fluff halo

/// Renders a state-specific cat emoji on a soft glowing halo.
/// Apple's emoji art is the cutest cat we can ship without bundling assets,
/// and it scales crisply at any size.
struct CuteCatFace: View {
    let state: PetState
    let t: TimeInterval
    /// 0–1, pulses halo intensity while user is hovering to feed.
    var hoverProgress: Double = 0

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // Soft cozy halo — color tracks state, intensity bumps on hover
                Circle()
                    .fill(RadialGradient(
                        colors: [haloColor.opacity(haloAlpha), haloColor.opacity(0)],
                        center: .center,
                        startRadius: s * 0.18,
                        endRadius: s * 0.55))
                    .blur(radius: s * 0.04)

                // The cat
                Text(emoji)
                    .font(.system(size: s * 0.78))
                    .scaleEffect(emojiScale)
            }
        }
    }

    /// Hover intensifies the halo from baseline (0.40) up to (0.70).
    private var haloAlpha: Double {
        let base: Double
        switch state {
        case .excited: base = 0.70
        case .eating: base = 0.55
        case .purring: base = 0.55
        case .sleepy: base = 0.25
        case .hungry: base = 0.30
        default: base = 0.40
        }
        return min(0.85, base + hoverProgress * 0.30)
    }

    private var haloColor: Color {
        switch state {
        case .excited: return Color(red: 1.00, green: 0.78, blue: 0.30)
        case .eating: return Color(red: 1.00, green: 0.62, blue: 0.32)
        case .purring: return Color(red: 1.00, green: 0.55, blue: 0.70)
        case .sleepy: return Color(red: 0.65, green: 0.62, blue: 0.78)
        case .hungry: return Color(red: 0.85, green: 0.62, blue: 0.45)
        default: return Color(red: 1.00, green: 0.70, blue: 0.40)
        }
    }

    /// Emoji choice = the expression. All cat-face emoji for visual consistency.
    private var emoji: String {
        switch state {
        case .idle: return "🐱"
        case .eating: return "😺"   // smiling open-mouth cat — chomp time
        case .excited: return "😸"  // grinning cat with smiling eyes — yay
        case .purring: return "😻"  // heart-eyes cat — show tip
        case .sleepy: return "😽"   // kissing cat (eyes closed) — naptime
        case .hungry: return "😿"   // crying cat
        }
    }

    /// Tiny breathing scale-jitter on the emoji itself for purring/idle.
    private var emojiScale: CGFloat {
        switch state {
        case .purring: return 1.0 + CGFloat(sin(t * 3.0)) * 0.04
        case .eating: return 1.0
        case .idle: return 1.0 + CGFloat(sin(t * 1.6)) * 0.02
        default: return 1.0
        }
    }
}

// MARK: - Progress ring (hover-to-feed feedback)

/// A slim progress bar inside a pill — replaces the old 5-dot row, reads
/// clearer at small sizes and pulses when filling.
private struct ProgressRing: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color(red: 1.00, green: 0.72, blue: 0.30),
                                 Color(red: 1.00, green: 0.48, blue: 0.55)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * CGFloat(progress))
                    .shadow(color: Color(red: 1.0, green: 0.55, blue: 0.40).opacity(0.6 * progress),
                            radius: 3)
            }
            .frame(width: w, height: h)
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
