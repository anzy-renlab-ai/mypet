import SwiftUI

/// Speech bubble overlay shown above the cat after a feed.
/// Tail points down to the cat's mouth.
struct TipBubble: View {
    let text: String
    let onDismiss: () -> Void

    @State private var appear = false

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.10))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 260)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.97))
                        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 4)
                )

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
            withAnimation(.easeOut(duration: 0.22)) {
                appear = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                onDismiss()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("猫说: \(text)")
        .accessibilityHint("点击关闭")
    }
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
