import AVFoundation
import SwiftUI

/// A live camera preview that reports decoded QR *and common barcode*
/// payloads. Runs entirely on-device via `AVCaptureMetadataOutput` — no
/// network access.
struct QRScannerView: UIViewControllerRepresentable {
    var onDetect: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onDetect = onDetect
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {
        uiViewController.onDetect = onDetect
    }
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onDetect: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastDetection: (value: String, date: Date)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !session.isRunning else { return }
        let session = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard session.isRunning else { return }
        session.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureSession() {
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        // QR plus the common 1D/2D barcode symbologies (retail/product
        // barcodes, shipping labels, etc.) -- not QR-only, despite the type
        // name "QRCodeRegistration" elsewhere in the app.
        let supportedTypes: [AVMetadataObject.ObjectType] = [
            .qr, .aztec, .dataMatrix, .pdf417,
            .ean8, .ean13, .upce,
            .code39, .code39Mod43, .code93, .code128,
            .interleaved2of5, .itf14,
        ]
        output.metadataObjectTypes = output.availableMetadataObjectTypes.filter { supportedTypes.contains($0) }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        // No need to re-check `object.type` against our allowlist here --
        // `output.metadataObjectTypes` (configured in configureSession())
        // already restricts what this delegate is ever called with.
        guard
            let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let value = object.stringValue
        else { return }

        if let last = lastDetection, last.value == value, Date().timeIntervalSince(last.date) < 1.0 {
            return
        }
        lastDetection = (value, Date())
        onDetect?(value)
    }
}

/// A framing guide to overlay on top of `QRScannerView` so it's clear where
/// to aim — the bare camera preview alone gave no indication of that.
struct ScannerFrameOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * 0.7
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white, lineWidth: 3)
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .shadow(color: .black.opacity(0.5), radius: 6)
        }
        .allowsHitTesting(false)
    }
}
