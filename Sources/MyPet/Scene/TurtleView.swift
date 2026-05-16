import SwiftUI

/// Cute compact desktop cat. Hover for 1s to feed.
///
/// Per-state expression: idle wink, eating chomp, excited sparkle, purring
/// heart-eyes, sleepy slit eyes + zZz, hungry teary frown.
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

                CuteCatFace(state: state, t: t)
                    .frame(width: 56, height: 56)
                    .shadow(color: shadowColor.opacity(0.35), radius: 6, x: 0, y: 3)
                    .scaleEffect(motion.scale, anchor: .bottom)
                    .rotationEffect(.degrees(motion.tilt), anchor: .bottom)
                    .offset(x: motion.sway, y: motion.bounce)

                if progress > 0 {
                    ProgressDots(progress: progress).frame(height: 6)
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

    private var shadowColor: Color {
        switch state {
        case .eating, .excited: return Color(red: 1.00, green: 0.62, blue: 0.32)
        case .purring: return Color(red: 0.98, green: 0.55, blue: 0.62)
        case .hungry: return Color(red: 0.75, green: 0.55, blue: 0.40)
        case .sleepy: return Color(red: 0.55, green: 0.50, blue: 0.55)
        default: return Color(red: 0.95, green: 0.62, blue: 0.38)
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
        case .excited: return Color(red: 1.00, green: 0.78, blue: 0.30)
        case .purring: return Color(red: 0.98, green: 0.55, blue: 0.65)
        case .hungry: return Color(red: 0.75, green: 0.55, blue: 0.40)
        case .eating: return Color(red: 1.00, green: 0.72, blue: 0.32)
        default: return Color.white.opacity(0.5)
        }
    }
}

// MARK: - The cat itself

/// Custom-drawn cute cat face. All SwiftUI shapes — no SF Symbol.
/// `t` lets eyes blink, tail flick, etc. without owning its own clock.
struct CuteCatFace: View {
    let state: PetState
    let t: TimeInterval

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // --- Layer 1: outer fluff halo (soft blurred glow) ---
                Circle()
                    .fill(RadialGradient(
                        colors: [furTopColor.opacity(0.55), furTopColor.opacity(0)],
                        center: .center,
                        startRadius: s * 0.30,
                        endRadius: s * 0.62))
                    .frame(width: s * 1.20, height: s * 1.20)
                    .blur(radius: s * 0.06)

                // --- Layer 2: body peek below head ---
                Ellipse()
                    .fill(furRadialGradient)
                    .frame(width: s * 0.58, height: s * 0.26)
                    .offset(y: s * 0.34)
                FurFringe(count: 10, arcStart: 150, arcEnd: 30, radius: s * 0.29, tuftLen: s * 0.06)
                    .fill(furBottomColor)
                    .frame(width: s * 0.62, height: s * 0.26)
                    .offset(y: s * 0.34)
                HStack(spacing: s * 0.16) {
                    Capsule().fill(toeBeanColor).frame(width: s * 0.08, height: s * 0.05)
                    Capsule().fill(toeBeanColor).frame(width: s * 0.08, height: s * 0.05)
                }
                .offset(y: s * 0.42)

                // --- Layer 3: fur fringe around the head silhouette ---
                FurFringe(count: 26, arcStart: 200, arcEnd: 520, radius: s * 0.41, tuftLen: s * 0.075)
                    .fill(furBottomColor)
                    .frame(width: s * 0.82, height: s * 0.82)
                    .blur(radius: 0.4)

                // --- Layer 4: ears (behind head) ---
                HStack(spacing: s * 0.30) {
                    EarView(s: s, side: .left, fur: furGradient, inner: innerEarColor, tuft: earTuftColor)
                    EarView(s: s, side: .right, fur: furGradient, inner: innerEarColor, tuft: earTuftColor)
                }
                .offset(y: -s * 0.30)

                // --- Layer 5: head with radial volume (highlight upper-left) ---
                Circle()
                    .fill(furRadialGradient)
                    .frame(width: s * 0.82, height: s * 0.82)
                    .overlay(
                        Circle()
                            .stroke(LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.clear],
                                startPoint: .topLeading, endPoint: .center),
                                lineWidth: s * 0.015)
                            .frame(width: s * 0.82, height: s * 0.82)
                            .blur(radius: 0.6)
                    )

                // --- Layer 6: forehead tabby tufts (M-mark) ---
                ForeheadM()
                    .stroke(stripeColor, style: StrokeStyle(lineWidth: s * 0.028, lineCap: .round))
                    .frame(width: s * 0.30, height: s * 0.14)
                    .offset(y: -s * 0.22)
                    .opacity(0.50)

                // Tabby stripes on cheeks/temple (subtle)
                StripesShape()
                    .stroke(stripeColor, style: StrokeStyle(lineWidth: s * 0.022, lineCap: .round))
                    .frame(width: s * 0.55, height: s * 0.14)
                    .offset(y: -s * 0.04)
                    .opacity(0.35)

                // Cheek blush
                HStack(spacing: s * 0.42) {
                    Circle().fill(blushColor).frame(width: s * 0.16, height: s * 0.10).blur(radius: 1.5)
                    Circle().fill(blushColor).frame(width: s * 0.16, height: s * 0.10).blur(radius: 1.5)
                }
                .offset(y: s * 0.08)

                // Whiskers
                WhiskersShape()
                    .stroke(whiskerColor, style: StrokeStyle(lineWidth: s * 0.018, lineCap: .round))
                    .frame(width: s * 0.80, height: s * 0.18)
                    .offset(y: s * 0.06)

                // Eyes
                HStack(spacing: s * 0.22) {
                    EyeView(state: state, t: t, blink: blinkPhase, side: .left)
                        .frame(width: s * 0.18, height: s * 0.22)
                    EyeView(state: state, t: t, blink: blinkPhase, side: .right)
                        .frame(width: s * 0.18, height: s * 0.22)
                }
                .offset(y: -s * 0.04)

                // Nose
                NoseShape()
                    .fill(noseGradient)
                    .frame(width: s * 0.10, height: s * 0.075)
                    .offset(y: s * 0.10)

                // Mouth
                MouthView(state: state, t: t)
                    .frame(width: s * 0.20, height: s * 0.10)
                    .offset(y: s * 0.17)

                // Tear (hungry only)
                if state == .hungry {
                    TearShape()
                        .fill(LinearGradient(
                            colors: [Color(red: 0.65, green: 0.85, blue: 1.0),
                                     Color(red: 0.35, green: 0.65, blue: 0.95)],
                            startPoint: .top, endPoint: .bottom))
                        .frame(width: s * 0.08, height: s * 0.13)
                        .offset(x: -s * 0.16, y: s * 0.10 + CGFloat(sin(t * 1.4)) * 1.5)
                        .opacity(0.8 + 0.2 * sin(t * 2))
                }
            }
        }
    }

    // Blink: full open most of time, brief blink every ~3.5s
    private var blinkPhase: Double {
        if state == .sleepy || state == .eating || state == .purring { return 0 } // own expression
        let cycle = t.truncatingRemainder(dividingBy: 3.5)
        if cycle < 0.12 { return 1.0 - cycle / 0.12 } // closing
        if cycle < 0.22 { return (cycle - 0.12) / 0.10 } // opening
        return 1.0
    }

    // Colors — orange tabby palette, state-aware
    private var furTopColor: Color {
        switch state {
        case .sleepy: return Color(red: 0.92, green: 0.78, blue: 0.62)
        case .hungry: return Color(red: 0.95, green: 0.78, blue: 0.55)
        default: return Color(red: 1.00, green: 0.86, blue: 0.62)
        }
    }
    private var furMidColor: Color {
        switch state {
        case .sleepy: return Color(red: 0.82, green: 0.65, blue: 0.50)
        case .hungry: return Color(red: 0.88, green: 0.68, blue: 0.45)
        default: return Color(red: 0.98, green: 0.70, blue: 0.40)
        }
    }
    private var furBottomColor: Color {
        switch state {
        case .sleepy: return Color(red: 0.70, green: 0.52, blue: 0.40)
        case .hungry: return Color(red: 0.78, green: 0.58, blue: 0.36)
        default: return Color(red: 0.95, green: 0.58, blue: 0.30)
        }
    }
    private var furGradient: LinearGradient {
        LinearGradient(colors: [furTopColor, furBottomColor], startPoint: .top, endPoint: .bottom)
    }
    private var furRadialGradient: RadialGradient {
        RadialGradient(
            colors: [furTopColor, furMidColor, furBottomColor],
            center: UnitPoint(x: 0.40, y: 0.32),
            startRadius: 2,
            endRadius: 36)
    }

    private var innerEarColor: Color { Color(red: 1.00, green: 0.72, blue: 0.78) }
    private var earTuftColor: Color { Color(red: 1.00, green: 0.92, blue: 0.80) }
    private var toeBeanColor: Color { Color(red: 1.00, green: 0.66, blue: 0.72) }
    private var stripeColor: Color { Color(red: 0.78, green: 0.42, blue: 0.20) }
    private var blushColor: Color { Color(red: 1.00, green: 0.62, blue: 0.68).opacity(0.55) }
    private var whiskerColor: Color { Color(red: 0.50, green: 0.38, blue: 0.30).opacity(0.7) }

    private var noseGradient: LinearGradient {
        LinearGradient(colors: [
            Color(red: 1.00, green: 0.58, blue: 0.65),
            Color(red: 0.90, green: 0.42, blue: 0.52)
        ], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Sub-shapes

/// Soft fluff fringe around a circular silhouette. Draws `count` small tufts
/// (rounded teardrops) along an arc from `arcStart` to `arcEnd` degrees,
/// measured clockwise from 12-o'clock.
private struct FurFringe: Shape {
    let count: Int
    let arcStart: Double
    let arcEnd: Double
    let radius: CGFloat
    let tuftLen: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX
        let cy = rect.midY
        let span = arcEnd - arcStart
        for i in 0..<count {
            let frac = Double(i) / Double(max(count - 1, 1))
            // Slight randomness via deterministic offset to break monotony
            let jitter = sin(Double(i) * 1.7) * 1.5
            let deg = arcStart + span * frac + jitter
            let rad = deg * .pi / 180.0
            let baseR = radius
            let lenWave = 1.0 + 0.20 * sin(Double(i) * 0.9)
            let len = tuftLen * CGFloat(lenWave)
            let widthHalf = tuftLen * 0.32
            // Tuft as a 3-point teardrop pointing outward
            let outX = cx + (baseR + len) * CGFloat(sin(rad))
            let outY = cy - (baseR + len) * CGFloat(cos(rad))
            let baseLX = cx + baseR * CGFloat(sin(rad - 0.10)) + widthHalf * CGFloat(cos(rad))
            let baseLY = cy - baseR * CGFloat(cos(rad - 0.10)) + widthHalf * CGFloat(sin(rad))
            let baseRX = cx + baseR * CGFloat(sin(rad + 0.10)) - widthHalf * CGFloat(cos(rad))
            let baseRY = cy - baseR * CGFloat(cos(rad + 0.10)) - widthHalf * CGFloat(sin(rad))
            p.move(to: CGPoint(x: baseLX, y: baseLY))
            p.addQuadCurve(
                to: CGPoint(x: outX, y: outY),
                control: CGPoint(x: (baseLX + outX) / 2 + len * 0.1 * CGFloat(cos(rad)),
                                 y: (baseLY + outY) / 2 + len * 0.1 * CGFloat(sin(rad))))
            p.addQuadCurve(
                to: CGPoint(x: baseRX, y: baseRY),
                control: CGPoint(x: (outX + baseRX) / 2 - len * 0.1 * CGFloat(cos(rad)),
                                 y: (outY + baseRY) / 2 - len * 0.1 * CGFloat(sin(rad))))
            p.closeSubpath()
        }
        return p
    }
}

/// Cute forehead M-mark (classic tabby trio).
private struct ForeheadM: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        // Three down-strokes
        for fx in [0.18, 0.50, 0.82] as [CGFloat] {
            p.move(to: CGPoint(x: w * fx, y: 0))
            p.addQuadCurve(
                to: CGPoint(x: w * fx, y: h),
                control: CGPoint(x: w * fx + w * 0.04, y: h * 0.5))
        }
        return p
    }
}

private struct EarView: View {
    let s: CGFloat
    let side: EyeSide
    let fur: LinearGradient
    let inner: Color
    let tuft: Color

    var body: some View {
        ZStack {
            // Outer fluffy halo on ear
            EarShape()
                .fill(tuft.opacity(0.7))
                .frame(width: s * 0.32, height: s * 0.34)
                .blur(radius: 1.2)
            EarShape()
                .fill(fur)
                .frame(width: s * 0.28, height: s * 0.30)
            EarShape()
                .fill(inner)
                .frame(width: s * 0.16, height: s * 0.20)
                .offset(y: s * 0.04)
            // White tuft inside ear (lynx point)
            Capsule()
                .fill(tuft)
                .frame(width: s * 0.04, height: s * 0.10)
                .offset(y: s * 0.02)
                .rotationEffect(.degrees(side == .left ? -15 : 15))
        }
        .rotationEffect(.degrees(side == .left ? -18 : 18))
    }
}

private struct EarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.maxX + rect.width * 0.05, y: rect.midY * 0.7)
        )
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX - rect.width * 0.05, y: rect.midY * 0.7)
        )
        return p
    }
}

private struct StripesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let segments: [(CGFloat, CGFloat, CGFloat)] = [
            (0.20, 0.0, 0.40), // start-x, y-mid, end-x
            (0.45, 0.0, 0.55),
            (0.70, 0.0, 0.90)
        ]
        for (sx, _, ex) in segments {
            p.move(to: CGPoint(x: rect.width * sx, y: rect.height * 0.4))
            p.addQuadCurve(
                to: CGPoint(x: rect.width * ex, y: rect.height * 0.4),
                control: CGPoint(x: rect.width * (sx + ex) / 2, y: 0)
            )
        }
        return p
    }
}

private struct WhiskersShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let leftX = rect.width * 0.08
        let rightX = rect.width * 0.92
        let midY = rect.height * 0.5
        // Left side — 3 whiskers
        for offset in [-0.30, 0.0, 0.30] as [CGFloat] {
            p.move(to: CGPoint(x: rect.width * 0.30, y: midY + offset * rect.height * 0.5))
            p.addLine(to: CGPoint(x: leftX, y: midY + offset * rect.height * 0.8))
        }
        // Right side — 3 whiskers
        for offset in [-0.30, 0.0, 0.30] as [CGFloat] {
            p.move(to: CGPoint(x: rect.width * 0.70, y: midY + offset * rect.height * 0.5))
            p.addLine(to: CGPoint(x: rightX, y: midY + offset * rect.height * 0.8))
        }
        return p
    }
}

private struct NoseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.3),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.3),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.2)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        return p
    }
}

private struct TearShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY * 0.65),
            control: CGPoint(x: rect.maxX, y: rect.midY * 0.6)
        )
        p.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY * 0.7),
            radius: rect.width * 0.5,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: false
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.midY * 0.6)
        )
        return p
    }
}

// MARK: - Eyes

private enum EyeSide { case left, right }

private struct EyeView: View {
    let state: PetState
    let t: TimeInterval
    /// 1.0 = fully open, 0.0 = fully closed.
    let blink: Double
    let side: EyeSide

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                switch state {
                case .sleepy:
                    // Closed slit, slight smile arc
                    ClosedArc(curveUp: false)
                        .stroke(eyeColor, style: StrokeStyle(lineWidth: h * 0.18, lineCap: .round))
                        .frame(width: w * 0.85, height: h * 0.35)

                case .eating:
                    // Happy closed ^ ^
                    ClosedArc(curveUp: true)
                        .stroke(eyeColor, style: StrokeStyle(lineWidth: h * 0.16, lineCap: .round))
                        .frame(width: w * 0.85, height: h * 0.5)

                case .purring:
                    // Heart eyes
                    HeartShape()
                        .fill(LinearGradient(
                            colors: [Color(red: 1.0, green: 0.45, blue: 0.55),
                                     Color(red: 0.92, green: 0.30, blue: 0.45)],
                            startPoint: .top, endPoint: .bottom))
                        .frame(width: w * 0.95, height: h * 0.85)

                default:
                    // Round eye + pupil + sparkle (blink-aware)
                    let openness = max(0.05, blink)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: w, height: h * openness)
                        .overlay(
                            Capsule().stroke(eyeRimColor, lineWidth: max(0.5, h * 0.04))
                        )
                    if openness > 0.4 {
                        Capsule()
                            .fill(eyeColor)
                            .frame(width: w * 0.62, height: h * 0.88 * openness)
                            .offset(x: pupilOffsetX(w: w))
                        // Sparkle
                        Circle()
                            .fill(Color.white)
                            .frame(width: w * 0.20, height: w * 0.20)
                            .offset(
                                x: pupilOffsetX(w: w) - w * 0.10,
                                y: -h * 0.18 * openness
                            )
                    }
                }
            }
            .frame(width: w, height: h, alignment: .center)
        }
    }

    private func pupilOffsetX(w: CGFloat) -> CGFloat {
        // Pupils look slightly inward, slight darting motion
        let dart = CGFloat(sin(t * 0.6)) * w * 0.04
        let inward: CGFloat = side == .left ? w * 0.04 : -w * 0.04
        return inward + dart
    }

    private var eyeColor: Color { Color(red: 0.16, green: 0.10, blue: 0.08) }
    private var eyeRimColor: Color { Color(red: 0.55, green: 0.35, blue: 0.20).opacity(0.45) }
}

private struct ClosedArc: Shape {
    let curveUp: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: curveUp ? rect.minY : rect.maxY)
        )
        return p
    }
}

private struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w / 2, y: h))
        p.addCurve(
            to: CGPoint(x: 0, y: h * 0.30),
            control1: CGPoint(x: w * 0.30, y: h * 0.80),
            control2: CGPoint(x: 0, y: h * 0.60)
        )
        p.addArc(
            center: CGPoint(x: w * 0.25, y: h * 0.30),
            radius: w * 0.25,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        p.addArc(
            center: CGPoint(x: w * 0.75, y: h * 0.30),
            radius: w * 0.25,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        p.addCurve(
            to: CGPoint(x: w / 2, y: h),
            control1: CGPoint(x: w, y: h * 0.60),
            control2: CGPoint(x: w * 0.70, y: h * 0.80)
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - Mouth

private struct MouthView: View {
    let state: PetState
    let t: TimeInterval

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                switch state {
                case .eating:
                    // Open chomping oval
                    let chomp = 0.5 + abs(sin(t * 6)) * 0.5
                    Ellipse()
                        .fill(Color(red: 0.40, green: 0.18, blue: 0.22))
                        .frame(width: w * 0.85, height: h * (0.4 + 0.6 * chomp))
                    // Little tongue
                    Capsule()
                        .fill(Color(red: 1.0, green: 0.5, blue: 0.55))
                        .frame(width: w * 0.50, height: h * 0.30 * chomp)
                        .offset(y: h * 0.20 * chomp)

                case .hungry:
                    // Sad downturn
                    MouthArc(downturn: true)
                        .stroke(mouthColor, style: StrokeStyle(lineWidth: h * 0.18, lineCap: .round))
                        .frame(width: w, height: h * 0.7)

                case .excited:
                    // Big smile w/ teeth dot
                    MouthArc(downturn: false)
                        .stroke(mouthColor, style: StrokeStyle(lineWidth: h * 0.20, lineCap: .round))
                        .frame(width: w, height: h)

                default:
                    // Tiny content w-mouth
                    WMouth()
                        .stroke(mouthColor, style: StrokeStyle(lineWidth: h * 0.18, lineCap: .round, lineJoin: .round))
                        .frame(width: w * 0.7, height: h * 0.5)
                }
            }
            .frame(width: w, height: h, alignment: .center)
        }
    }

    private var mouthColor: Color { Color(red: 0.45, green: 0.25, blue: 0.22) }
}

private struct MouthArc: Shape {
    let downturn: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: downturn ? rect.minY : rect.maxY)
        )
        return p
    }
}

private struct WMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY * 0.7),
            control: CGPoint(x: rect.width * 0.25, y: rect.maxY)
        )
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY * 0.7),
            control: CGPoint(x: rect.width * 0.75, y: rect.maxY)
        )
        return p
    }
}

// MARK: - Progress + particles (unchanged from prior turtle, palette tweaked)

private struct ProgressDots: View {
    let progress: Double
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { i in
                Circle()
                    .fill(progress >= Double(i + 1) / 5.0
                          ? Color(red: 1.00, green: 0.62, blue: 0.32)
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
