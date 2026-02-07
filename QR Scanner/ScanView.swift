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

private struct TopOverlayHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct BottomOverlayHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @AppStorage("saveToHistory") private var saveToHistory: Bool = true
    @AppStorage("confirmBeforeOpen") private var confirmBeforeOpen: Bool = true
    
    @State private var showingPaywall = false

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

    @State private var topOverlayHeight: CGFloat = 0
    @State private var bottomOverlayHeight: CGFloat = 0
    @State private var topOverlayLift: CGFloat = 32

    private let scannerResetDelay: TimeInterval = 1.5
 
    var body: some View {
        NavigationStack {
            ZStack {
                // Base background for the entire tab, including under the tab bar.
                Color.black.ignoresSafeArea()

                GeometryReader { proxy in
                    let size = proxy.size
                    let safe = proxy.safeAreaInsets

                    // Visible scan box size.
                    let boxWidth = min(size.width * 0.8, 320.0)
                    let boxHeight = boxWidth

                    // Center the scan box within the full screen, but leave room for the measured overlays.
                    let effectiveTop = max(0, topOverlayHeight - topOverlayLift)
                    let usableHeight = max(0, size.height - safe.top - safe.bottom - effectiveTop - bottomOverlayHeight)
                    let boxY = safe.top + effectiveTop + max(0, (usableHeight - boxHeight) / 2) + (boxHeight / 2)

                    let boxRect = CGRect(
                        x: (size.width - boxWidth) / 2,
                        y: boxY - boxHeight / 2,
                        width: boxWidth,
                        height: boxHeight
                    )

                    if cameraAuth == .authorized {
                        // Full-bleed camera preview behind the scan UI.
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

                        // Dim everything outside the scan box.
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
                    } else {
                        permissionUI
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .ignoresSafeArea() // do not let GeometryReader be constrained by the tab bar
            }
            .sheet(item: $parsed, onDismiss: {
                DispatchQueue.main.asyncAfter(deadline: .now() + scannerResetDelay) {
                    isScanning = true
                }
                self.parsed = nil
            }) { parsed in
                ScanResultView(parsed: parsed, confirmBeforeOpen: confirmBeforeOpen)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingPaste) {
                PasteSheet(
                    pasteText: $pasteText,
                    onUse: { pasteText in
                        showingPaste = false
                        let parsed = ScanParser.parse(pasteText)
                        self.parsed = parsed
                    },
                    onClose: {
                        showingPaste = false
                    }
                )
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhoto, matching: .images)
            .sheet(isPresented: $showingPaywall, onDismiss: {
                // Resume scanning if user dismissed without subscribing
                if subscriptionManager.canScan {
                    isScanning = true
                }
            }) {
                PaywallView()
            }
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
                isScanning = false
                parsed = nil
                showingPaste = false
            }
            .safeAreaInset(edge: .top) {
                topOverlay
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: TopOverlayHeightKey.self, value: g.size.height)
                        }
                    )
                    .onPreferenceChange(TopOverlayHeightKey.self) { topOverlayHeight = $0 }
                    .padding(.top, -topOverlayLift)
            }
            .safeAreaInset(edge: .bottom) {
                bottomOverlay
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: BottomOverlayHeightKey.self, value: g.size.height)
                        }
                    )
                    .onPreferenceChange(BottomOverlayHeightKey.self) { bottomOverlayHeight = $0 }
            }
        }
    }

    private var topOverlay: some View {
        HStack {
            Button {
                guard subscriptionManager.canScan else {
                    isScanning = false
                    showingPaywall = true
                    return
                }
                showingPhotoPicker = true
            } label: {
                Label("Photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Paste") {
                guard subscriptionManager.canScan else {
                    isScanning = false
                    showingPaywall = true
                    return
                }
                showingPaste = true
            }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.top, 32)
        .padding(.bottom, 0)
    }

    private var bottomOverlay: some View {
        VStack(spacing: 20) {
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
                Button("Continue") {
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

        // Check subscription limit
        guard subscriptionManager.canScan else {
            isScanning = false
            showingPaywall = true
            return
        }

        // Simple dedupe throttle
        if let last = lastScanValue,
           let at = lastScanAt,
           last == trimmed,
           Date().timeIntervalSince(at) < scannerResetDelay {
            isScanning = true
            return
        }
        lastScanValue = trimmed
        lastScanAt = Date()

        // Pause scanning while showing the review sheet
        isScanning = false

        let parsed = ScanParser.parse(trimmed)
        self.parsed = parsed

        // Consume the one-time free scan for non-Pro users.
        subscriptionManager.consumeFreeUse(for: .scan)

        if saveToHistory {
            let record = ScanRecord(rawValue: parsed.raw, kindRaw: parsed.kind.rawValue, symbology: symbology)
            modelContext.insert(record)
        }
    }
}
