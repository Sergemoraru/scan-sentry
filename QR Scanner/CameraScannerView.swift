import SwiftUI

struct CameraScannerView: UIViewControllerRepresentable {
    @Binding var isScanning: Bool
    @Binding var isTorchOn: Bool
    var onScan: (String, String?) -> Void
    var onRequestOpenSettings: (() -> Void)? = nil

    class Coordinator {
        var parent: CameraScannerView
        init(parent: CameraScannerView) { self.parent = parent }
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onScan = onScan
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        if isScanning {
            uiViewController.startScanning()
        } else {
            uiViewController.stopScanning()
        }
        // Torch control
        uiViewController.setTorch(isTorchOn)
    }
}
