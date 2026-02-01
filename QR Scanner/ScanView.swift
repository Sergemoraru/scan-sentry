import SwiftUI
import SwiftData
import AVFoundation
import UIKit
import PhotosUI
import Vision

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

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
    /// Space reserved at the bottom for the custom tab bar (and its offset),
    /// so the scan window never sits behind it.
    var bottomReserved: CGFloat = 0
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

    @State private var showingPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var pickedImageData: Data? = nil

    @State private var topBarHeight: CGFloat = 0
    @State private var bottomBarHeight: CGFloat = 0

    var body: some View {
        NavigationStack {
            ZStack {
                if cameraAuth == .authorized {
                    // Camera area fills the screen; controls are separate "bars" pinned
                    // to the top/bottom safe areas (not inside the camera box).
                    GeometryReader { proxy in
                        let size = proxy.size
                        let safe = proxy.safeAreaInsets
                        let availableTop = safe.top + topBarHeight
                        // Also reserve space for the custom bottom tab bar.
                        let availableBottom = safe.bottom + bottomBarHeight + bottomReserved

                        let boxWidth = min(size.width * 0.8, 320.0)
                        let boxHeight = boxWidth

                        // Center the scan box within the space between the two bars.
                        let usableHeight = max(0, size.height - availableTop - availableBottom)
                        let boxY = availableTop + max(0, (usableHeight - boxHeight) / 2) + (boxHeight / 2)
                        let boxRect = CGRect(x: (size.width - boxWidth)/2,
                                             y: boxY - boxHeight/2,
                                             width: boxWidth,
                                             height: boxHeight)

                        ZStack {
                            Color(.systemBackground)

                            // Dim everything outside the scan box with a cut-out hole
                            Color.black.opacity(0.35)
                                .mask(
                                    Canvas { context, _ in
                                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                                        let rounded = Path(roundedRect: boxRect, cornerRadius: 20)
                                        context.blendMode = .destinationOut
                                        context.fill(rounded, with: .color(.black))
                                    }
                                )

                            // Camera feed clipped to the scan box
                            CameraScannerView(isScanning: $isScanning, isTorchOn: $isTorchOn) { value, symbology in
                                handleScan(value, symbology: symbology)
                            }
                            .frame(width: boxRect.width, height: boxRect.height)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
                            )
                            .position(x: boxRect.midX, y: boxRect.midY)

                            // Top bar (pinned to very top of the phone)
                            VStack(spacing: 0) {
                                topControls
                                    .background(
                                        GeometryReader { g in
                                            Color.clear
                                                .preference(key: SizePreferenceKey.self, value: g.size.height)
                                        }
                                    )
                                    .onPreferenceChange(SizePreferenceKey.self) { topBarHeight = $0 }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                            // Bottom bar (pinned to very bottom *above the TabView*)
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                bottomControls
                                    .background(
                                        GeometryReader { g in
                                            Color.clear
                                                .preference(key: SizePreferenceKey.self, value: g.size.height)
                                        }
                                    )
                                    .onPreferenceChange(SizePreferenceKey.self) { bottomBarHeight = $0 }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                        .ignoresSafeArea()
                    }
                } else {
                    permissionUI
                }
            }
            .sheet(item: $parsed, onDismiss: {
                // Resume scanning when the user dismisses the result
                isScanning = true
                // Clear previous result so a new scan presents fresh
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
            .onChange(of: isScanning) { _, scanning in
                if scanning { self.parsed = nil }
            }
            // When switching tabs, make sure any sheets from ScanView are dismissed
            // so History/Settings can appear full-screen.
            .onDisappear {
                isScanning = false
                parsed = nil
                showingPaste = false
            }
            .background(Color(.systemBackground))
        }
    }

    private var topControls: some View {
        VStack(spacing: 8) {
            // Buttons row
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
            .padding(.horizontal)
            .padding(.top, 0)

            // Info text below buttons
            HStack {
                Text("Does not auto‑open links.")
                    .font(.headline)
                Spacer(minLength: 12)
            }
            .padding(.horizontal)

            HStack {
                Text("Scan → review → then open/copy/share.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
            }
            .padding(.horizontal)
            .padding(.bottom, 0)
        }
        .background(Color(.systemBackground).ignoresSafeArea(.container, edges: .top))
        .overlay(Divider(), alignment: .bottom)
    }

    private var bottomControls: some View {
        HStack {
            Spacer()
            Button {
                isTorchOn.toggle()
            } label: {
                Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.title2)
                    .padding()
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 0)
        .background(Color(.systemBackground).ignoresSafeArea(.container, edges: .bottom))
        .overlay(Divider(), alignment: .top)
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
        pickedImageData = data
        guard let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage else { return }

        let request = VNDetectBarcodesRequest { request, _ in
            if let result = (request.results as? [VNBarcodeObservation])?.first,
               let payload = result.payloadStringValue {
                handleScan(payload, symbology: result.symbology.rawValue)
            } else {
                // Optional: show a gentle alert/toast; for now, no-op
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
           Date().timeIntervalSince(at) < 2.0 {
            isScanning = true
            return
        }
        lastScanValue = trimmed
        lastScanAt = Date()

        let parsed = ScanParser.parse(trimmed)
        self.parsed = parsed

        if saveToHistory {
            let record = ScanRecord(rawValue: parsed.raw, kindRaw: parsed.kind.rawValue, symbology: symbology)
            modelContext.insert(record)
        }
    }
}

