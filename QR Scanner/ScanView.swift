import SwiftUI
import SwiftData
import AVFoundation
import UIKit
import PhotosUI
import Vision

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

    @State private var showingPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var pickedImageData: Data? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                if cameraAuth == .authorized {
                    CameraScannerView(isScanning: $isScanning, isTorchOn: $isTorchOn) { value, symbology in
                        handleScan(value, symbology: symbology)
                    }
                    .ignoresSafeArea()

                    overlayUI
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
                    guard let pasteText else { return }
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
            .onChange(of: selectedPhoto) { newItem in
                guard let item = newItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await analyzePickedImageData(data)
                    }
                    selectedPhoto = nil
                }
            }
            .onChange(of: isScanning) { scanning in
                if scanning { self.parsed = nil }
            }
        }
    }

    private var overlayUI: some View {
        VStack {
            // Top bar
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
            .padding(.top, 12)

            Spacer()

            // Info text centered above bottom controls
            VStack(spacing: 10) {
                Text("Does not auto‑open links.")
                    .font(.headline)
                Text("Scan → review → then open/copy/share.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Bottom bar
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
            .padding(.bottom, 24)
        }
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
        request.symbologies = [.QR, .Aztec, .DataMatrix, .PDF417, .Code128, .Code39, .EAN13, .EAN8, .UPCE]

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
