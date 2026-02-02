import SwiftUI
import SwiftData
import AVFoundation
import UIKit
import PhotosUI
import Vision

struct VisualEffectBlur: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemThinMaterial

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

extension ParsedScan: Identifiable {
    var id: String { raw }
}

struct ScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @AppStorage("saveToHistory") private var saveToHistory: Bool = true
    @AppStorage("confirmBeforeOpen") private var confirmBeforeOpen: Bool = true

    @State private var isScanning = true
    @State private var lastScanValue: String?
    @State private var lastScanAt: Date?

    @State private var parsed: ParsedScan?

    @State private var showingPaste = false
    @State private var pasteText = ""

    @State private var cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isTorchOn = false
    @State private var lowLightHint = false

    @State private var showingPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                // Never show white on the Scan tab.
                Color.black.ignoresSafeArea()

                if cameraAuth == .authorized {
                    GeometryReader { proxy in
                        let size = proxy.size
                        let safe = proxy.safeAreaInsets

                        // Visible scan box size.
                        let boxWidth = min(size.width * 0.8, 320.0)
                        let boxHeight = boxWidth

                        // Keep the box centered between top safe area and tab bar safe area.
                        // (TabView reduces the available safe area automatically.)
                        let availableTop = safe.top + 86 // approx height of top overlay
                        let availableBottom = safe.bottom + 120 // approx space for bottom overlays
                        let usableHeight = max(0, size.height - availableTop - availableBottom)
                        let boxY = availableTop + max(0, (usableHeight - boxHeight) / 2) + (boxHeight / 2)

                        let boxRect = CGRect(
                            x: (size.width - boxWidth) / 2,
                            y: boxY - boxHeight / 2,
                            width: boxWidth,
                            height: boxHeight
                        )

                        ZStack {
                            // Full-bleed camera behind everything.
                            CameraScannerView(
                                isScanning: $isScanning,
                                isTorchOn: $isTorchOn,
                                regionOfInterest: boxRect
                            ) { value, symbology in
                                handleScan(value, symbology: symbology)
                            } onLowLightChanged: { isLow in
                                lowLightHint = isLow
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                            .ignoresSafeArea()

                            // Darken outside the scan box.
                            Color.black.opacity(0.35)
                                .mask(
                                    Canvas { context, _ in
                                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                                        let rounded = Path(roundedRect: boxRect, cornerRadius: 20)
                                        context.blendMode = .destinationOut
                                        context.fill(rounded, with: .color(.black))
                                    }
                                )
                                .allowsHitTesting(false)

                            // Scan frame overlay.
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                                .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
                                .frame(width: boxRect.width, height: boxRect.height)
                                .position(x: boxRect.midX, y: boxRect.midY)
                                .allowsHitTesting(false)
                        }
                    }
                } else {
                    permissionUI
                }
            }
            // Top overlay pinned to top safe area.
            .safeAreaInset(edge: .top, spacing: 0) {
                topOverlay
            }
            // Bottom overlay pinned above tab bar (safe area already accounts for it).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomOverlay
            }
            .sheet(item: $parsed, onDismiss: {
                // Cooldown before resuming scanning
                let cooldown: TimeInterval = 3.0
                DispatchQueue.main.asyncAfter(deadline: .now() + cooldown) {
                    isScanning = true
                }
                self.parsed = nil
            }) { parsed in
                ScanResultView(parsed: parsed, confirmBeforeOpen: confirmBeforeOpen)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingPaste) {
                PasteSheet(pasteText: $pasteText) { pasteText in
                    showingPaste = false
                    let parsed = ScanParser.parse(pasteText)
                    self.parsed = parsed
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhoto, matching: .images)
            .onAppear {
                cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
                if cameraAuth == .authorized { isScanning = true }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
            }
            .onChange(of: selectedPhoto) { _, newItem in
                guard let item = newItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await analyzePickedImageData(data)
                    }
                    selectedPhoto = nil
                }
            }
            .onDisappear {
                // Ensure Scan sheets don't linger when switching tabs.
                isScanning = false
                parsed = nil
                showingPaste = false
            }
        }
    }

    private var topOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    showingPhotoPicker = true
                } label: {
                    Label("Photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Paste") { showingPaste = true }
                    .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Does not auto‑open links.")
                    .font(.headline)
                Text("Scan → review → then open/copy/share.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .bottom)
    }

    private var bottomOverlay: some View {
        VStack(spacing: 10) {
            // Instruction chip (optional) pinned just above the tab bar.
            if lowLightHint && !isTorchOn {
                Text("Low light — try the flashlight")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
            }

            HStack {
                Spacer()
                Button {
                    isTorchOn.toggle()
                } label: {
                    Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.title2)
                        .padding(14)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.15)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color.clear)
    }

    private var permissionUI: some View {
        VStack(spacing: 14) {
            Text("Camera permission required to scan.")
                .font(.headline)

            if cameraAuth == .notDetermined {
                Button("Allow Camera") {
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        DispatchQueue.main.async {
                            cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
                            if cameraAuth == .authorized { isScanning = true }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Enable Camera in Settings → Privacy & Security → Camera.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Paste Instead") { showingPaste = true }
                    .buttonStyle(.bordered)

                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    @MainActor
    private func analyzePickedImageData(_ data: Data) async {
        guard let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage else { return }

        let request = VNDetectBarcodesRequest { request, _ in
            if let result = (request.results as? [VNBarcodeObservation])?.first,
               let payload = result.payloadStringValue {
                handleScan(payload, symbology: result.symbology.rawValue)
            }
        }
        request.symbologies = [.qr, .aztec, .dataMatrix, .pdf417, .code128, .code39, .ean13, .ean8, .upce]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }

    private func handleScan(_ value: String, symbology: String?) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Simple dedupe throttle
        if let last = lastScanValue,
           let at = lastScanAt,
           last == trimmed,
           Date().timeIntervalSince(at) < 3.0 {
            isScanning = true
            return
        }
        lastScanValue = trimmed
        lastScanAt = Date()

        // Pause scanning while showing the review sheet
        isScanning = false

        let parsed = ScanParser.parse(trimmed)
        self.parsed = parsed

        if saveToHistory {
            let record = ScanRecord(rawValue: parsed.raw, kindRaw: parsed.kind.rawValue, symbology: symbology)
            modelContext.insert(record)
        }
    }
}
