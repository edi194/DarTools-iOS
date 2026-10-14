import SwiftUI
import AVFoundation

// Wspólna morfująca pigułka aparatu (odpowiednik CameraPill.kt / MorphCameraPill):
// 130x40 → 170x170, ukrywanie przy scrollu (visible), zamykanie tapem poza pigułką.
struct CameraPill: View {
    @Binding var showScanner: Bool
    var visible: Bool
    // wysokość nad dolnym paskiem akcji (żeby nie zasłaniał przycisków)
    var bottomInset: CGFloat = 12
    let onDetect: (String) -> Void

    @State private var denied = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // gdy skaner otwarty — pełnoekranowy przechwytacz tapa zamykający podgląd
            if showScanner {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { showScanner = false }
            }

            // prawdziwy Button (nie onTapGesture): pewniejszy odbiór tapów przy scrollu
            // i klawiaturze + natywna animacja naciśnięcia dzięki .interactive()
            Button {
                if showScanner { showScanner = false } else { requestCamera() }
            } label: {
                ZStack {
                    Label("Aparat", systemImage: "camera.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(showScanner ? Color.white : Color.accentColor)
                        .opacity(showScanner ? 0 : 1)
                    if showScanner {
                        CameraBarcodeScanner { value in
                            showScanner = false
                            onDetect(value)
                        }
                    }
                }
                .frame(width: showScanner ? 170 : 130, height: showScanner ? 170 : 40)
                .contentShape(RoundedRectangle(cornerRadius: showScanner ? 18 : 22))
                .background(showScanner ? Color.black : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: showScanner ? 18 : 22))
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: showScanner ? 18 : 22))
            // ukryta = nie przechwytuje tapów (opacity samo tego nie robi)
            .allowsHitTesting(showScanner ? false : visible)
            .opacity(visible || showScanner ? 1 : 0)
            .padding(.bottom, bottomInset)
            .animation(.easeInOut(duration: 0.38), value: showScanner) // morph jak tween(380)
            .animation(.quick, value: visible)                          // fade jak AnimatedVisibility
        }
        .alert("Kamera", isPresented: $denied) {
            Button("OK", role: .cancel) {}
        } message: { Text("Brak uprawnień do kamery") }
    }

    private func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showScanner = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { showScanner = granted; denied = !granted }
            }
        default:
            denied = true
        }
    }
}
