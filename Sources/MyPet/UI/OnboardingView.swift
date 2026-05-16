import SwiftUI

/// First-launch onboarding wizard — cute card style, no system chrome.
@MainActor
struct OnboardingView: View {

    enum Step {
        case detecting
        case foundClaude(path: String)
        case notFound
        case loginItemAsk
        case demo
        case done
    }

    @State private var step: Step = .detecting
    @State private var pulse = false
    let coordinator: FeedCoordinator
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            // Soft cream-to-pink gradient background, cat-themed warmth
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.96, blue: 0.90),  // cream
                    Color(red: 1.00, green: 0.90, blue: 0.92)   // soft blush
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Floating paw prints decoration
            PawPrintsBackground()
                .opacity(0.08)

            VStack(spacing: 20) {
                Spacer(minLength: 10)
                content
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .id(stepID)
                Spacer(minLength: 10)
            }
            .padding(28)
        }
        .frame(width: 480, height: 380)
        .task(id: stepID) {
            await runStepTask()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: stepID)
    }

    private var stepID: String {
        switch step {
        case .detecting: return "detecting"
        case .foundClaude: return "found"
        case .notFound: return "notfound"
        case .loginItemAsk: return "login"
        case .demo: return "demo"
        case .done: return "done"
        }
    }

    private func runStepTask() async {
        switch step {
        case .detecting:
            // Pulse the detection emoji for ≥800ms so it doesn't blink past
            try? await Task.sleep(nanoseconds: 800_000_000)
            if let path = await ClaudeSubprocess.discoverBinary() {
                step = .foundClaude(path: path)
            } else {
                step = .notFound
            }
        case .demo:
            await coordinator.feed()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            coordinator.dismissTip()
            try? await Task.sleep(nanoseconds: 400_000_000)
            step = .done
        case .done:
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            onComplete()
        default:
            break
        }
    }

    // MARK: - Step views

    @ViewBuilder
    private var content: some View {
        switch step {
        case .detecting:
            detectingCard
        case .foundClaude(let path):
            foundCard(path: path)
        case .notFound:
            notFoundCard
        case .loginItemAsk:
            loginCard
        case .demo:
            demoCard
        case .done:
            doneCard
        }
    }

    private var detectingCard: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(accentPink)
                .scaleEffect(1.2)
            Text("小猫在嗅嗅 Claude Code…")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(textPrimary)
            Text("检查 CLI 是否在你的电脑上")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(textSecondary)
        }
    }

    private func foundCard(path: String) -> some View {
        VStack(spacing: 14) {
            CatBadge()
            Text("找到啦")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundColor(textPrimary)
            Text("Claude Code 已就位")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(textSecondary)
            Text(path)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(textSecondary.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(.white.opacity(0.7))
                )
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 380)
            CuteButton(title: "下一步") {
                step = .loginItemAsk
            }
            .padding(.top, 6)
        }
    }

    private var notFoundCard: some View {
        VStack(spacing: 14) {
            CatBadge()
            Text("找不到 Claude Code")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundColor(textPrimary)
            Text("先装上 Claude Code 才能喂它")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                CuteButton(title: "去装", style: .secondary) {
                    if let url = URL(string: "https://docs.anthropic.com/claude-code") {
                        NSWorkspace.shared.open(url)
                    }
                }
                CuteButton(title: "我装好了") {
                    step = .detecting
                }
            }
            .padding(.top, 4)
        }
    }

    private var loginCard: some View {
        VStack(spacing: 14) {
            CatBadge()
            Text("要不要开机自启？")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundColor(textPrimary)
                .multilineTextAlignment(.center)
            Text("托盘菜单里随时可以改")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(textSecondary)
            HStack(spacing: 10) {
                CuteButton(title: "先不", style: .secondary) {
                    step = .demo
                }
                CuteButton(title: "好") {
                    LoginItem.enable()
                    step = .demo
                }
            }
            .padding(.top, 4)
        }
    }

    private var demoCard: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(accentPink)
                .scaleEffect(1.2)
            Text("喂它第一口 token…")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(textPrimary)
            Text("看右下角")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(textSecondary)
        }
    }

    private var doneCard: some View {
        VStack(spacing: 12) {
            CatBadge()
            Text("搞定")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundColor(textPrimary)
            Text("小猫住在右下角了。\n鼠标移到它身上停一秒就喂它一口，\n或者菜单栏 🐾 → Feed now。")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Styling

    private var textPrimary: Color { Color(red: 0.18, green: 0.14, blue: 0.20) }
    private var textSecondary: Color { Color(red: 0.45, green: 0.40, blue: 0.45) }
    private var accentPink: Color { Color(red: 0.95, green: 0.52, blue: 0.62) }
}

// MARK: - Cat badge for onboarding

private struct CatBadge: View {
    /// Drives idle blink/breathe without owning a clock.
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            CuteCatFace(state: .idle, t: t)
                .frame(width: 76, height: 76)
                .scaleEffect(1.0 + sin(t * 1.6) * 0.025)
                .shadow(color: Color(red: 0.98, green: 0.55, blue: 0.40).opacity(0.35),
                        radius: 10, x: 0, y: 5)
        }
    }
}

/// Rounded cute button matching cat palette.
private struct CuteButton: View {
    enum Style {
        case primary
        case secondary
    }

    let title: String
    var style: Style = .primary
    let action: () -> Void

    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Text(title)
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundColor(textColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(fillGradient)
            )
            .scaleEffect(pressed ? 0.95 : (hovering ? 1.03 : 1.0))
            .shadow(color: shadowColor, radius: hovering ? 10 : 6, x: 0, y: 4)
            .onHover { hovering = $0 }
            .onTapGesture {
                pressed = true
                action()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    pressed = false
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovering)
            .animation(.spring(response: 0.18, dampingFraction: 0.5), value: pressed)
    }

    private var textColor: Color {
        style == .primary ? .white : Color(red: 0.45, green: 0.32, blue: 0.40)
    }

    private var fillGradient: LinearGradient {
        switch style {
        case .primary:
            return LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.68, blue: 0.36),  // orange
                    Color(red: 0.95, green: 0.52, blue: 0.62)   // pink
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .secondary:
            return LinearGradient(
                colors: [.white.opacity(0.85), .white.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var shadowColor: Color {
        style == .primary
            ? Color(red: 0.95, green: 0.52, blue: 0.62).opacity(0.35)
            : .black.opacity(0.08)
    }
}

/// Subtle floating paw prints behind cards.
private struct PawPrintsBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let positions: [(CGFloat, CGFloat, CGFloat)] = [
                (0.12, 0.18, 26), (0.85, 0.12, 22), (0.18, 0.78, 30),
                (0.78, 0.82, 28), (0.55, 0.08, 18), (0.08, 0.50, 24),
                (0.92, 0.55, 20), (0.45, 0.92, 22),
            ]
            for (fx, fy, s) in positions {
                let cx = size.width * fx
                let cy = size.height * fy
                drawPaw(in: &ctx, x: cx, y: cy, size: s)
            }
        }
    }

    private func drawPaw(in ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, size: CGFloat) {
        let color = Color(red: 0.95, green: 0.52, blue: 0.62)
        // Main pad
        let pad = Path(ellipseIn: CGRect(x: x - size * 0.5, y: y, width: size, height: size * 0.7))
        ctx.fill(pad, with: .color(color))
        // 4 toes around the pad
        for (dx, dy) in [(-0.5, -0.5), (-0.15, -0.7), (0.2, -0.7), (0.5, -0.5)] {
            let toeSize = size * 0.35
            let toe = Path(ellipseIn: CGRect(
                x: x + size * dx - toeSize / 2,
                y: y + size * dy - toeSize / 2,
                width: toeSize,
                height: toeSize * 0.85
            ))
            ctx.fill(toe, with: .color(color))
        }
    }
}
