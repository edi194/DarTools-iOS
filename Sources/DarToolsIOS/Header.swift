import SwiftUI

// Wspólny kompaktowy pasek górny — login i ekran zalogowanego
struct CompactHeader<Leading: View, Center: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var center: Center
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 4)
            center
                .frame(maxWidth: .infinity)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing
        }
        .padding(.top, 4)
        .padding(.horizontal, 12)
    }
}

// Mały przycisk ikony w stylu glass
struct GlassIconButton: View {
    let systemName: String
    var label: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.footnote)
                .padding(8)
        }
        .buttonStyle(.glass)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

// Efekt naciśnięcia (skala + wygaszenie) dla kafelków
struct PressableTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// Wspólna sprężyna ekranów
extension Animation {
    static var screen: Animation { .spring(duration: 0.35, bounce: 0.2) }
    static var quick: Animation { .easeInOut(duration: 0.2) }
}

// Pływający dolny pasek z akcentowym przyciskiem głównym (Liquid Glass)
struct PrimaryActionBar: View {
    var title: String
    var systemImage: String?
    var isLoading = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading { ProgressView().controlSize(.small).tint(.white) }
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .glassEffect(.regular, in: .capsule)
            .background(.tint, in: .capsule)
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.55 : 1)
        .disabled(disabled)
        .padding(.bottom, 4)
    }
}
