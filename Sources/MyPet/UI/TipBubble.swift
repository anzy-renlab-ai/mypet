import SwiftUI
import AppKit

/// Speech bubble overlay shown above the cat after a feed.
/// Tail points down to the cat's mouth.
struct TipBubble: View {
    let text: String
    /// Optional category badge ("tip" / "prompt" / "news" / "TIL" / "joke" / "打油诗")
    /// Rendered as a tiny chip in the top-left corner of the bubble.
    var themeBadge: ThemeBadge? = nil
    /// Tokens the cat just ate (input + output). Rendered as a small chip
    /// in the top-right; nil to omit (welcome / cooldown / error tips).
    var tokens: Int? = nil
    let onDismiss: () -> Void

    @State private var appear = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            Text(copied ? "✓ 已复制到剪贴板" : text)
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.10))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 300)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.97))
                        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 4)
                )
                .overlay(alignment: .topLeading) {
                    if let badge = themeBadge {
                        HStack(spacing: 3) {
                            Text(badge.emoji).font(.system(size: 10))
                            Text(badge.label)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(badge.tint)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(badge.tint.opacity(0.15))
                        )
                        .offset(x: -4, y: -7)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let n = tokens, n > 0 {
                        HStack(spacing: 2) {
                            Text("🐟").font(.system(size: 10))
                            Text("\(n)t")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(red: 0.45, green: 0.30, blue: 0.20))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color(red: 1.00, green: 0.78, blue: 0.30).opacity(0.20))
                        )
                        .offset(x: 4, y: -7)
                    }
                }

            BubbleTail()
                .fill(.white.opacity(0.97))
                .frame(width: 18, height: 10)
                .offset(y: -1)
        }
        .scaleEffect(appear ? 1 : 0.85)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                appear = true
            }
        }
        .onTapGesture {
            copyToPasteboard(text)
            withAnimation(.easeInOut(duration: 0.18)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                withAnimation(.easeOut(duration: 0.22)) { appear = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    onDismiss()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("猫说: \(text)")
        .accessibilityHint("点击复制到剪贴板并关闭")
    }

    private func copyToPasteboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

struct ThemeBadge: Equatable {
    let emoji: String
    let label: String
    let tint: Color

    static let claudeTip = ThemeBadge(emoji: "☕", label: "tip",
        tint: Color(red: 0.65, green: 0.45, blue: 0.20))
    static let promptIdea = ThemeBadge(emoji: "💡", label: "prompt",
        tint: Color(red: 0.85, green: 0.55, blue: 0.10))
    static let techNews = ThemeBadge(emoji: "📰", label: "news",
        tint: Color(red: 0.30, green: 0.50, blue: 0.75))
    static let til = ThemeBadge(emoji: "🤓", label: "TIL",
        tint: Color(red: 0.45, green: 0.50, blue: 0.80))
    static let devJoke = ThemeBadge(emoji: "😆", label: "joke",
        tint: Color(red: 0.80, green: 0.40, blue: 0.55))
    static let dayouShi = ThemeBadge(emoji: "🥟", label: "打油诗",
        tint: Color(red: 0.78, green: 0.42, blue: 0.30))
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
