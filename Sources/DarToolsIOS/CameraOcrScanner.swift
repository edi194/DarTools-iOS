import SwiftUI
import AVFoundation
import Vision

// Odpowiednik trybu OCR z ManualPartSearchActivity (MLKit TextRecognition → Vision).
// Szuka ciągów 3–6 cyfr, cooldown 1.5 s między detekcjami.
struct CameraOcrScanner: UIViewRepresentable {
    let onRecognized: @MainActor ([String]) -> Void

    func makeUIView(context: Context) -> OcrScannerView {
        let v = OcrScannerView()
        v.onRecognized = context.coordinator.onRecognized
        return v
    }

    func updateUIView(_ uiView: OcrScannerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onRecognized: onRecognized) }

    final class Coordinator {
        let onRecognized: @MainActor ([String]) -> Void
        init(onRecognized: @escaping @MainActor ([String]) -> Void) { self.onRecognized = onRecognized }
    }
}

// Osobny delegate (jak MetaDelegate) — AVCaptureVideoDataOutputSampleBufferDelegate
// nie może przechodzić przez MainActor (Swift 6).
private final class OcrDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var handler: (@MainActor ([String]) -> Void)?
    private let queue = DispatchQueue(label: "ocr.scanner")
    private var busy = false
    private var lastFire: TimeInterval = 0
    private let pattern = try! NSRegularExpression(pattern: "\\d{3,6}")

    var sampleQueue: DispatchQueue { queue }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date().timeIntervalSince1970
        guard !busy, now - lastFire >= 1.5,
              let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        busy = true
        lastFire = now

        let pattern = self.pattern
        let handler = self.handler
        let req = VNRecognizeTextRequest { [weak self] r, _ in
            defer { self?.busy = false }
            let texts = (r.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
            let joined = texts.joined(separator: " ")
            let range = NSRange(joined.startIndex..<joined.endIndex, in: joined)
            var found: [String] = []
            pattern.enumerateMatches(in: joined, range: range) { m, _, _ in
                if let m, let r = Range(m.range, in: joined) { found.append(String(joined[r])) }
            }
            if !found.isEmpty {
                Task { @MainActor in handler?(found) }
            }
        }
        req.recognitionLevel = .accurate
        queue.async { try? VNImageRequestHandler(cvPixelBuffer: pb, options: [:]).perform([req]) }
    }
}

// UIKitowy podgląd z sesją kamery + analiza klatek (Vision OCR)
final class OcrScannerView: UIView {
    var onRecognized: (@MainActor ([String]) -> Void)?
    nonisolated(unsafe) private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var configured = false
    private let delegate = OcrDelegate()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else { start() }
    }

    private func start() {
        delegate.handler = { [weak self] codes in self?.onRecognized?(codes) }
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

        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        if session.canAddOutput(out) { session.addOutput(out) }
        session.commitConfiguration()
        configured = true

        out.setSampleBufferDelegate(delegate, queue: delegate.sampleQueue)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        if let conn = layer.connection, conn.isVideoRotationAngleSupported(90) {
            conn.videoRotationAngle = 90
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
