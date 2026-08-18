import SwiftUI
import AVFoundation

/// SwiftUI wrapper over AVCaptureSession: shows the camera preview
/// and streams either detected barcodes or raw frames (for photo/OCR).
struct BarcodeScannerView: UIViewControllerRepresentable {

    var onBarcodeDetected: (String) -> Void
    var onPhotoCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onBarcodeDetected = onBarcodeDetected
        controller.onPhotoCaptured = onPhotoCaptured
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate, AVCapturePhotoCaptureDelegate {

    var onBarcodeDetected: ((String) -> Void)?
    var onPhotoCaptured: ((UIImage) -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastDetectedCode: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()

        if session.canAddInput(input) {
            session.addInput(input)
        }

        // Barcodes
        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            metadataOutput.metadataObjectTypes = [.ean8, .ean13, .upce, .code128]
        }

        // Photo output for visual recognition / OCR
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    // Called manually (e.g. by tapping a "Capture" button),
    // when no barcode was found and the product needs to be recognized visually.
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue,
              code != lastDetectedCode else { return }

        lastDetectedCode = code
        onBarcodeDetected?(code)

        // A short debounce so the same code isn't spammed every frame
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.lastDetectedCode = nil
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        onPhotoCaptured?(image)
    }
}
