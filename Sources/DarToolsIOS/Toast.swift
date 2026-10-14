import SwiftUI

// Lekki toast na dole ekranu (odpowiednik Android Toast.LENGTH_SHORT)
private struct ToastModifier: ViewModifier {
    @Binding var text: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let t = text {
                    Text(t)
                        .font(.footnote)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.85), in: .capsule)
                        .foregroundStyle(.white)
                        .padding(.bottom, 80)
                        .transition(.opacity)
                        .task(id: t) {
                            try? await Task.sleep(nanoseconds: 2_200_000_000)
                            if text == t { text = nil }
                        }
                }
            }
            .animation(.quick, value: text)
    }
}

extension View {
    func toast(_ text: Binding<String?>) -> some View { modifier(ToastModifier(text: text)) }
}
