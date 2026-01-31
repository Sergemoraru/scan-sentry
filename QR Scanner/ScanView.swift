import SwiftUI
import SwiftData
import AVFoundation
import UIKit

struct ScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @AppStorage("saveToHistory") private var saveToHistory: Bool = true
    @AppStorage("confirmBeforeOpen") private var confirmBeforeOpen: Bool = true

    @State private var isScanning = true
    @State private var lastScanValue: String?
    @State private var lastScanAt: Date?

    @State private var showingResult = false
    @State private var parsed: ParsedScan?

    @State private var showingPaste = false
    @State private var pasteText = ""

    @State private var cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isTorchOn = false

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
            .navigationTitle("Safe QR")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            handleScan("https://apple.com", symbology: "test")
                        } label: {
                            Label("Inject Test URL", systemImage: "link")
                        }
                        Button {
                            handleScan("Hello from simulator", symbology: "test")
                        } label: {
                            Label("Inject Test Text", systemImage: "text.quote")
                        }
                    } label: {
                        Label("Test", systemImage: "hammer")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Paste") { showingPaste = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isTorchOn.toggle()
                    } label: {
                        Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    }
                }
            }
            .sheet(isPresented: $showingPaste) {
                NavigationStack {
                    Form {
                        Section("Paste a QR payload") {
                            TextEditor(text: $pasteText)
                                .frame(minHeight: 160)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Button("Use This") {
                            handleScan(pasteText, symbology: "pasted")
                            showingPaste = false
                            pasteText = ""
                        }
                    }
                    .navigationTitle("Paste")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") { showingPaste = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingResult, onDismiss: {
                // Resume scanning when the user dismisses the result
                isScanning = true
            }) {
                if let parsed {
                    ScanResultView(parsed: parsed, confirmBeforeOpen: confirmBeforeOpen)
                        .presentationDetents([.medium, .large])
                }
            }
            .onAppear {
                cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }

    private var overlayUI: some View {
        VStack {
            Spacer()
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
            .padding(.bottom, 22)
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

        showingResult = true
        isScanning = false
    }
}
