import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import UIKit

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Create/preview QR codes. Export actions include one free try, then require Pro.
struct QRCodeGeneratorView: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.openURL) private var openURL

    @FocusState private var isTextFocused: Bool

    @State private var text: String = "https://"

    @State private var shareItems: [Any] = []
    @State private var activeSheet: ActiveSheet?

    @State private var alertTitle: String?
    @State private var alertMessage: String?

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Text or URL", text: $text, axis: .vertical)
                            .focused($isTextFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.URL)
                            .submitLabel(.done)
                            .onSubmit { isTextFocused = false }

                        HStack {
                            Spacer()
                            Button("Done") { isTextFocused = false }
                                .buttonStyle(.bordered)
                        }
                    }
                }

                Section("Preview") {
                    if let ui = makeUIImage(from: text) {
                        Image(uiImage: ui)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    } else {
                        Image(systemName: "qrcode")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary)
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }

                Section {
                    Button {
                        Task { await exportTapped(kind: .share) }
                    } label: {
                        Label("Share QR Code", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }

                    Button {
                        Task { await exportTapped(kind: .save) }
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                } footer: {
                    if !subscriptionManager.isPro {
                        if subscriptionManager.remainingQRCodeExports > 0 {
                            Text("You get one free QR export before Pro is required.")
                        } else {
                            Text("Your free QR export has been used. Upgrade to Pro for unlimited exports.")
                        }
                    }
                }
            }
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isTextFocused = false }
                }
            }
            .simultaneousGesture(TapGesture().onEnded {
                isTextFocused = false
            })
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .paywall:
                    PaywallView()
                case .share:
                    ActivityView(items: shareItems)
                }
            }
            .alert(alertTitle ?? "", isPresented: .init(get: { alertTitle != nil }, set: { if !$0 { alertTitle = nil; alertMessage = nil } })) {
                if alertTitle == "Photos Permission" {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    Button("OK", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private enum ExportKind {
        case share
        case save
    }

    private enum ActiveSheet: Identifiable {
        case paywall
        case share

        var id: String {
            switch self {
            case .paywall:
                return "paywall"
            case .share:
                return "share"
            }
        }
    }

    private func exportTapped(kind: ExportKind) async {
        guard subscriptionManager.canExportQRCode else {
            activeSheet = .paywall
            return
        }
        guard let ui = makeUIImage(from: text) else {
            alertTitle = "Error"
            alertMessage = "Couldn’t generate a QR code from that text."
            return
        }

        switch kind {
        case .share:
            shareItems = [ui]
            activeSheet = .share
            subscriptionManager.consumeFreeUse(for: .qrExport)

        case .save:
            let didSave = await saveToPhotos(ui)
            if didSave {
                subscriptionManager.consumeFreeUse(for: .qrExport)
            }
        }
    }

    private func saveToPhotos(_ image: UIImage) async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let granted: Bool
        switch status {
        case .authorized, .limited:
            granted = true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            granted = (newStatus == .authorized || newStatus == .limited)
        default:
            granted = false
        }

        guard granted else {
            alertTitle = "Photos Permission"
            alertMessage = "Allow Photos access to save QR codes.\n\nSettings → Privacy & Security → Photos → Scan Sentry"
            return false
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            alertTitle = "Saved"
            alertMessage = "QR code saved to Photos."
            return true
        } catch {
            alertTitle = "Error"
            alertMessage = "Couldn’t save to Photos: \(error.localizedDescription)"
            return false
        }
    }

    // Preview image is rendered inline in the Form.

    private func makeUIImage(from string: String) -> UIImage? {
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        // Scale up so it’s crisp.
        let transform = CGAffineTransform(scaleX: 12, y: 12)
        let scaled = outputImage.transformed(by: transform)

        guard let cgimg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgimg)
    }
}
