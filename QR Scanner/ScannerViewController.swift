import UIKit
import AVFoundation

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String, String?) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var configured = false
    private var isRunning = false

    private let overlayLayer = CAShapeLayer()
    private let reticleLayer = CAShapeLayer()
    private var metadataOutput: AVCaptureMetadataOutput?

    func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            // Ignore torch errors for now
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Setup overlay layers for bounding boxes and reticle
        overlayLayer.strokeColor = UIColor.systemGreen.cgColor
        overlayLayer.fillColor = UIColor.clear.cgColor
        overlayLayer.lineWidth = 2
        view.layer.addSublayer(overlayLayer)

        reticleLayer.strokeColor = UIColor.white.withAlphaComponent(0.8).cgColor
        reticleLayer.fillColor = UIColor.clear.cgColor
        reticleLayer.lineDashPattern = [6, 6]
        reticleLayer.lineWidth = 1.5
        view.layer.addSublayer(reticleLayer)

        // Gestures: pinch to zoom, tap to focus/expose
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        view.addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        checkPermissionAndConfigureIfNeeded()
    }

    func startScanning() {
        guard configured, !isRunning else { return }
        isRunning = true
        DispatchQueue.main.async { self.overlayLayer.path = nil }
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }

    func stopScanning() {
        guard isRunning else { return }
        isRunning = false
        DispatchQueue.main.async { self.overlayLayer.path = nil }
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.stopRunning()
        }
    }

    private func checkPermissionAndConfigureIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSessionIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.configureSessionIfNeeded() }
                }
            }
        default:
            // Denied/restricted: SwiftUI layer should show instructions
            break
        }
    }

    private func configureSessionIfNeeded() {
        guard !configured else { return }
        configured = true

        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        self.metadataOutput = output

        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [
            .qr,
            .ean8, .ean13, .upce,
            .code39, .code93, .code128,
            .pdf417, .aztec,
            .dataMatrix
        ]

        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        // Ensure full-screen preview respecting device bounds
        if let window = view.window {
            preview.frame = window.bounds
        } else {
            preview.frame = view.bounds
        }
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview

        setRegionOfInterest()
    }

    private func setRegionOfInterest() {
        guard let preview = previewLayer, let output = metadataOutput else { return }
        let bounds = view.bounds
        let side = min(bounds.width, bounds.height) * 0.6
        let roi = CGRect(x: (bounds.width - side)/2, y: (bounds.height - side)/2, width: side, height: side)

        let metadataRect = preview.metadataOutputRectConverted(fromLayerRect: roi)
        output.rectOfInterest = metadataRect

        // Update reticle path to show the ROI to the user
        let path = UIBezierPath(roundedRect: roi, cornerRadius: 12)
        reticleLayer.path = path.cgPath
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        if recognizer.state == .changed {
            do {
                try device.lockForConfiguration()
                let maxFactor = device.activeFormat.videoMaxZoomFactor
                var factor = device.videoZoomFactor * recognizer.scale
                factor = max(1.0, min(maxFactor, factor))
                device.videoZoomFactor = factor
                device.unlockForConfiguration()
                recognizer.scale = 1.0
            } catch {
                // Ignore zoom errors
            }
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: view)
        guard let device = AVCaptureDevice.default(for: .video), let pl = previewLayer else { return }
        let devicePoint = pl.captureDevicePointConverted(fromLayerPoint: point)
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            // Ignore focus/exposure errors
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let window = view.window {
            previewLayer?.frame = window.bounds
        } else {
            previewLayer?.frame = view.bounds
        }
        setRegionOfInterest()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        // Draw bounding box for the first detected code
        overlayLayer.path = nil
        if let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let transformed = previewLayer?.transformedMetadataObject(for: obj) as? AVMetadataMachineReadableCodeObject {
            let path = UIBezierPath()
            let corners = transformed.corners
            if corners.count > 0 {
                path.move(to: corners[0])
                for p in corners.dropFirst() { path.addLine(to: p) }
                path.close()
                overlayLayer.path = path.cgPath
            } else {
                overlayLayer.path = UIBezierPath(rect: transformed.bounds).cgPath
            }

            // Stop to prevent repeated callbacks
            stopScanning()

            // Haptic feedback on successful scan
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            let symbology = obj.type.rawValue
            if let value = obj.stringValue {
                onScan?(value, symbology)
            }
        }
    }
}

