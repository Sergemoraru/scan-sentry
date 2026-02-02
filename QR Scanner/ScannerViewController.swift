import UIKit
import AVFoundation

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String, String?) -> Void)?
    var onLowLightChanged: ((Bool) -> Void)?

    /// Region of interest in this view's coordinate space.
    /// Set by the SwiftUI layer to match the visible scan box.
    var regionOfInterest: CGRect? = nil {
        didSet {
            // Update on the next layout pass.
            if isViewLoaded { setRegionOfInterest() }
        }
    }

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var configured = false
    private var isRunning = false

    private let overlayLayer = CAShapeLayer()
    private let reticleLayer = CAShapeLayer()
    private let focusLayer = CAShapeLayer()
    private var metadataOutput: AVCaptureMetadataOutput?

    private var lowLightTimer: DispatchSourceTimer?
    private var lastLowLight: Bool? = nil

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

        reticleLayer.strokeColor = UIColor.white.withAlphaComponent(0.0).cgColor
        reticleLayer.fillColor = UIColor.clear.cgColor
        reticleLayer.lineDashPattern = [6, 6]
        reticleLayer.lineWidth = 1.5
        view.layer.addSublayer(reticleLayer)

        // Focus indicator (tap-to-focus)
        focusLayer.strokeColor = UIColor.systemYellow.withAlphaComponent(0.95).cgColor
        focusLayer.fillColor = UIColor.clear.cgColor
        focusLayer.lineWidth = 2
        focusLayer.opacity = 0
        view.layer.addSublayer(focusLayer)

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
        startLowLightMonitoring()
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }

    func stopScanning() {
        guard isRunning else { return }
        isRunning = false
        DispatchQueue.main.async { self.overlayLayer.path = nil }
        stopLowLightMonitoring()
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
        // Respect the container view's bounds (SwiftUI may size this view)
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview

        setRegionOfInterest()
    }

    private func setRegionOfInterest() {
        guard let preview = previewLayer, let output = metadataOutput else { return }

        let bounds = view.bounds
        let roi: CGRect
        if let provided = regionOfInterest, provided.width > 0, provided.height > 0 {
            // Clamp to the preview bounds in case SwiftUI provided something slightly out-of-bounds.
            roi = provided.intersection(bounds)
        } else {
            // Default ROI: centered square, slightly inset.
            let side = min(bounds.width, bounds.height) * 0.8
            roi = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        }

        let metadataRect = preview.metadataOutputRectConverted(fromLayerRect: roi)
        output.rectOfInterest = metadataRect

        // Reticle path (kept for debugging; SwiftUI draws the visible scan box)
        let path = UIBezierPath(roundedRect: roi, cornerRadius: 12)
        reticleLayer.path = path.cgPath
    }

    private func startLowLightMonitoring() {
        stopLowLightMonitoring()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.2, repeating: 0.6)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.updateLowLightHint()
        }
        self.lowLightTimer = timer
        timer.resume()
    }

    private func stopLowLightMonitoring() {
        lowLightTimer?.cancel()
        lowLightTimer = nil
        lastLowLight = nil
        onLowLightChanged?(false)
    }

    private func updateLowLightHint() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            if lastLowLight != false { lastLowLight = false; onLowLightChanged?(false) }
            return
        }
        // exposureTargetOffset is negative when the camera is underexposed.
        // Threshold chosen empirically; keep conservative to avoid nagging.
        let isLow = device.exposureTargetOffset < -0.75
        if lastLowLight != isLow {
            lastLowLight = isLow
            onLowLightChanged?(isLow)
        }
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

        showFocusIndicator(at: point)
    }

    private func showFocusIndicator(at point: CGPoint) {
        let size: CGFloat = 72
        let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        focusLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 12).cgPath

        focusLayer.removeAllAnimations()
        focusLayer.opacity = 1

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.15
        scale.toValue = 1.0
        scale.duration = 0.18
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.65
        fade.beginTime = CACurrentMediaTime() + 0.12
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = fade.beginTime - CACurrentMediaTime() + fade.duration
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        focusLayer.add(group, forKey: "focus")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Respect the container view's bounds (SwiftUI may size this view)
        previewLayer?.frame = view.bounds
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

            // Let SwiftUI control pausing/resuming scanning (cooldown handled there).

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

