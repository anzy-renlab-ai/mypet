import SwiftUI

/// Hover-revealed feed button.
/// Shows as a small white circle with the ⚡ (token/compute) symbol.
struct FeedButton: View {
    let isCoolingDown: Bool
    let cooldownProgress: Double  // 0...1
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

                if isCoolingDown {
                    Circle()
                        .trim(from: 0, to: cooldownProgress)
                        .stroke(
                            Color(red: 0.91, green: 0.62, blue: 0.69),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                }

                Image(systemName: "bolt.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.68, blue: 0.36),
                                Color(red: 0.93, green: 0.62, blue: 0.69)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(isCoolingDown ? 0.3 : 1)
            }
            .frame(width: 48, height: 48)
            .scaleEffect(hovering ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isCoolingDown)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        .accessibilityLabel("喂 token 给猫")
        .accessibilityHint(isCoolingDown ? "冷却中，请稍候" : "用一次 Claude Code 调用换一条技巧或新闻")
    }
}
