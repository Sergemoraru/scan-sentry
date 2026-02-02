import SwiftUI

struct CameraScannerView: UIViewControllerRepresentable {
    @Binding var isScanning: Bool
    @Binding var isTorchOn: Bool

    /// Region of interest in this view's coordinate space.
    /// When provided, the underlying AVCaptureMetadataOutput rectOfInterest
    /// will be set to match this visible scan box.
    var regionOfInterest: CGRect? = nil

    var onScan: (String, String?) -> Void
    var onLowLightChanged: ((Bool) -> Void)? = nil
    var onRequestOpenSettings: (() -> Void)? = nil

    typealias UIViewControllerType = ScannerViewController

    class Coordinator {
        var parent: CameraScannerView
        init(parent: CameraScannerView) { self.parent = parent }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.view.backgroundColor = .black
        vc.onScan = onScan
        vc.onLowLightChanged = onLowLightChanged
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        uiViewController.regionOfInterest = regionOfInterest

        if isScanning {
            uiViewController.startScanning()
        } else {
            uiViewController.stopScanning()
        }
        // Torch control
        uiViewController.setTorch(isTorchOn)
    }
}
// Usage hint: when using CameraScannerView in SwiftUI, consider applying `.frame(...)` modifier to ensure full-bleed appearance.

