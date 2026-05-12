import SwiftUI

/// Cute compact desktop turtle (`tortoise.fill` SF Symbol). Hover for 1s to feed.
struct TurtleView: View {
    let state: PetState
    let excited: Bool
    let onFeed: (() -> Void)?

    @State private var hovering = false
    @State private var hoverStart: Date?
    @State private var hoverProgress: Double = 0
    @State private var hoverTimer: Timer?

    private let petDuration: TimeInterval = 1.0

    init(state: PetState, excited: Bool = false, onFeed: (() -> Void)? = nil) {
        self.state = state
        self.excited = excited
        self.onFeed = onFeed
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let motion = bodyMotion(at: t)

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

                    Image(systemName: petSymbol)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(petGradient)
                        .shadow(color: shadowColor.opacity(0.5), radius: 6, x: 0, y: 3)
                        .scaleEffect(motion.scale, anchor: .bottom)
                        .rotationEffect(.degrees(motion.tilt), anchor: .bottom)
                        .offset(x: motion.sway, y: motion.bounce)

                    if hovering && hoverProgress > 0 {
                        ProgressDots(progress: hoverProgress).frame(height: 6)
                    } else {
                        Spacer().frame(height: 6)
                    }
                }
            }
        }
        .contentShape(Circle())
        .frame(width: 80, height: 80)
        .onHover { isHovering in
            hovering = isHovering
            if isHovering { startPetTimer() } else { cancelPetTimer() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("乌龟")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("鼠标停留 1 秒触发喂 token")
        .animation(.easeInOut(duration: 0.2), value: state)
    }

    private var petSymbol: String { "tortoise.fill" }

    private var petGradient: LinearGradient {
        switch state {
        case .idle:
            return LinearGradient(colors: [Color(red: 0.55, green: 0.78, blue: 0.55), Color(red: 0.38, green: 0.62, blue: 0.40)], startPoint: .top, endPoint: .bottom)
        case .eating:
            return LinearGradient(colors: [Color(red: 0.62, green: 0.85, blue: 0.50), Color(red: 0.40, green: 0.65, blue: 0.32)], startPoint: .top, endPoint: .bottom)
        case .excited:
            return LinearGradient(colors: [Color(red: 0.70, green: 0.92, blue: 0.45), Color(red: 0.45, green: 0.72, blue: 0.30)], startPoint: .top, endPoint: .bottom)
        case .purring:
            return LinearGradient(colors: [Color(red: 0.62, green: 0.82, blue: 0.62), Color(red: 0.45, green: 0.65, blue: 0.48)], startPoint: .top, endPoint: .bottom)
        case .sleepy:
            return LinearGradient(colors: [Color(red: 0.50, green: 0.58, blue: 0.52), Color(red: 0.35, green: 0.42, blue: 0.38)], startPoint: .top, endPoint: .bottom)
        case .hungry:
            return LinearGradient(colors: [Color(red: 0.58, green: 0.72, blue: 0.50), Color(red: 0.45, green: 0.58, blue: 0.38)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var shadowColor: Color {
        switch state {
        case .eating, .excited: return Color(red: 0.40, green: 0.75, blue: 0.30)
        case .purring: return Color(red: 0.50, green: 0.70, blue: 0.50)
        case .hungry: return Color(red: 0.45, green: 0.58, blue: 0.38)
        default: return Color.black.opacity(0.3)
        }
    }

    private func bodyMotion(at t: TimeInterval) -> (sway: CGFloat, bounce: CGFloat, scale: CGFloat, tilt: Double) {
        switch state {
        case .idle:
            return (CGFloat(sin(t * 0.6)) * 1.5, 0, 1.0 + sin(t * 0.9) * 0.015, 0)
        case .eating:
            return (0, CGFloat(abs(sin(t * 6.0))) * -4, 1.0, sin(t * 4.0) * 5.0)
        case .excited:
            return (0, CGFloat(abs(sin(t * 5.0))) * -12, 1.0 + abs(sin(t * 5.0)) * 0.1, 0)
        case .purring:
            return (0, 0, 1.0 + sin(t * 1.4) * 0.04, 0)
        case .sleepy:
            return (0, 0, 1.0 + sin(t * 0.5) * 0.02, -8)
        case .hungry:
            return (CGFloat(sin(t * 0.8)) * 2.5, 0, 1.0, 0)
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
        case .excited: return Color(red: 0.55, green: 0.85, blue: 0.35)
        case .purring: return Color(red: 0.55, green: 0.75, blue: 0.55)
        case .hungry: return Color(red: 0.50, green: 0.65, blue: 0.42)
        case .eating: return Color(red: 0.50, green: 0.80, blue: 0.35)
        default: return Color.white.opacity(0.5)
        }
    }

    private func startPetTimer() {
        cancelPetTimer()
        hoverStart = Date()
        hoverProgress = 0
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { _ in
            guard let start = hoverStart else { return }
            let elapsed = Date().timeIntervalSince(start)
            hoverProgress = min(1.0, elapsed / petDuration)
            if hoverProgress >= 1.0 {
                hoverTimer?.invalidate()
                hoverTimer = nil
                hoverStart = nil
                onFeed?()
                hoverProgress = 0
            }
        }
    }

    private func cancelPetTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hoverStart = nil
        withAnimation(.easeOut(duration: 0.2)) { hoverProgress = 0 }
    }
}

private struct ProgressDots: View {
    let progress: Double
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { i in
                Circle()
                    .fill(progress >= Double(i + 1) / 5.0
                          ? Color(red: 0.40, green: 0.78, blue: 0.30)
                          : Color.gray.opacity(0.3))
                    .frame(width: 5, height: 5)
            }
        }
    }
}

private struct ParticleField: View {
    let at: TimeInterval
    let state: PetState

    var body: some View {
        Canvas { ctx, size in
            for p in particleSpec() {
                let cycle = (at * p.speed + p.phase).truncatingRemainder(dividingBy: 1.0)
                let alpha = 1.0 - cycle
                let yOffset = -CGFloat(cycle) * size.height * 0.4
                ctx.draw(
                    Text(p.glyph).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(color.opacity(alpha)),
                    at: CGPoint(x: size.width * CGFloat(p.x), y: size.height * 0.5 + yOffset)
                )
            }
        }
    }

    private var color: Color {
        state == .excited
            ? Color(red: 0.55, green: 0.85, blue: 0.35)
            : Color(red: 1.0, green: 0.86, blue: 0.50)
    }

    private struct Particle { let x: Double; let phase: Double; let speed: Double; let glyph: String }

    private func particleSpec() -> [Particle] {
        switch state {
        case .eating:
            return [
                .init(x: 0.25, phase: 0.0, speed: 0.7, glyph: "⚡"),
                .init(x: 0.55, phase: 0.4, speed: 0.7, glyph: "⚡"),
                .init(x: 0.80, phase: 0.7, speed: 0.7, glyph: "⚡"),
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
