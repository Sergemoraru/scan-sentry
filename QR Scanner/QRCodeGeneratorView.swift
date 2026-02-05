import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Create/preview QR codes. Export actions can be paywalled by the caller.
struct QRCodeGeneratorView: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager

    @State private var text: String = "https://"
    @State private var showingPaywall = false

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    TextField("Text or URL", text: $text, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                Section("Preview") {
                    qrImage
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }

                Section {
                    Button {
                        exportTapped(kind: .share)
                    } label: {
                        Label("Share QR Code", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        exportTapped(kind: .save)
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    Text(subscriptionManager.isPro ? "" : "Exporting QR codes requires Pro.")
                }
            }
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
    }

    private enum ExportKind {
        case share
        case save
    }

    private func exportTapped(kind: ExportKind) {
        guard subscriptionManager.isPro else {
            showingPaywall = true
            return
        }
        // Placeholder: we’ll wire up actual share/save next (UIActivityViewController / Photos).
        // For now, just show paywall gating works.
        if kind == .save {
            // no-op
        }
    }

    @ViewBuilder
    private var qrImage: Image {
        if let ui = makeUIImage(from: text) {
            Image(uiImage: ui)
        } else {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(height: 180)
        }
    }

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
