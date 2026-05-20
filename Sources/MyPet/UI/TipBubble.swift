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
            Text(copied ? L10n.t("copied!", "已复制") : text)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(Color(red: 0.14, green: 0.14, blue: 0.16))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 28) // room for the token/hint row below
                .frame(maxWidth: 300)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.96))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.04), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 3)
                )
                // Theme chip (top-left)
                .overlay(alignment: .topLeading) {
                    if let badge = themeBadge {
                        HStack(spacing: 3) {
                            Text(badge.emoji).font(.system(size: 11))
                            Text(badge.label)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(badge.tint)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(badge.tint.opacity(0.15)))
                        .offset(x: -4, y: -8)
                    }
                }
                // Close-hint chip (top-right) — visual cue that any click
                // copies + dismisses (the window is click-through so an
                // actual button can't fire). Stays even when no tokens.
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L10n.t("click to copy", "点击复制"))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Color(red: 0.45, green: 0.30, blue: 0.20))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(red: 1.00, green: 0.78, blue: 0.30).opacity(0.22)))
                    .offset(x: 4, y: -8)
                }
                // Token count chip (bottom-right inside the bubble) — bigger
                // + clearer than the old "🐟 150t" version which was tiny
                // and easy to miss.
                .overlay(alignment: .bottomTrailing) {
                    if let n = tokens, n > 0 {
                        let label = n == 1
                            ? L10n.t("1 token", "1 token")
                            : L10n.t("\(n) tokens", "\(n) tokens")
                        HStack(spacing: 4) {
                            Text("🐟").font(.system(size: 12))
                            Text(label)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(red: 0.45, green: 0.30, blue: 0.20))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(red: 1.00, green: 0.78, blue: 0.30).opacity(0.22)))
                        .padding(.trailing, 10)
                        .padding(.bottom, 6)
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
        .accessibilityLabel(L10n.t("cat says: \(text)", "猫说: \(text)"))
        .accessibilityHint(L10n.t("Click to copy and dismiss", "点击复制到剪贴板并关闭"))
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
