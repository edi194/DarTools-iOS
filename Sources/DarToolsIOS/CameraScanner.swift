import SwiftUI
import AVFoundation

// Odpowiednik CameraBarcodeScanner.kt — podgląd + skan kodów przez AVFoundation.
// Delegate w osobnej (nie-izolowanej) klasie, bo conformance do
// AVCaptureMetadataOutputObjectsDelegate nie może przechodzić przez MainActor (Swift 6).
struct CameraBarcodeScanner: UIViewRepresentable {
    let onDetected: @MainActor (String) -> Void

    func makeUIView(context: Context) -> ScannerView {
        let view = ScannerView()
        view.onDetected = context.coordinator.onDetected
        return view
    }

    func updateUIView(_ uiView: ScannerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDetected: onDetected) }

    final class Coordinator {
        let onDetected: @MainActor (String) -> Void
        init(onDetected: @escaping @MainActor (String) -> Void) { self.onDetected = onDetected }
    }
}

// Wywoływany na main queue (ustawiona w setMetadataObjectsDelegate)
private final class MetaDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var handler: (@MainActor (String) -> Void)?

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                    didOutput metadataObjects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue, !value.isEmpty else { return }
        let h = handler
        Task { @MainActor in h?(value) }
    }
}

// UIKitowy podgląd z sesją kamery
final class ScannerView: UIView {
    var onDetected: (@MainActor (String) -> Void)?
    nonisolated(unsafe) private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var configured = false
    private let delegate = MetaDelegate()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stop()
        } else {
            start()
        }
    }

    private func start() {
        delegate.handler = { [weak self] value in
            self?.onDetected?(value)
            self?.onDetected = nil // jedno wywołanie — jak na Androidzie
        }
        guard !configured else {
            if !session.isRunning {
                let s = session
                DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
            }
            return
        }
        guard AVCaptureDevice.default(for: .video) != nil else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        let out = AVCaptureMetadataOutput()
        if session.canAddOutput(out) {
            session.addOutput(out)
        }
        session.commitConfiguration()
        configured = true

        // delegate/typy MUSZĄ być ustawione po commit — przed konfiguracją
        // availableMetadataObjectTypes jest puste → brak detekcji
        out.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
        out.metadataObjectTypes = out.availableMetadataObjectTypes

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        if let conn = layer.connection, conn.isVideoRotationAngleSupported(90) {
            conn.videoRotationAngle = 90 // podgląd pionowo jak na Androidzie
        }
        self.layer.addSublayer(layer)
        preview = layer
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
    }

    private func stop() {
        if session.isRunning { session.stopRunning() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        preview?.frame = bounds
    }
}
