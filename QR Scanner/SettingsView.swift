import SwiftUI

struct SettingsView: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @AppStorage("saveToHistory") private var saveToHistory: Bool = true
    @AppStorage("confirmBeforeOpen") private var confirmBeforeOpen: Bool = true
    @AppStorage("aggressiveRiskAnalysis") private var aggressiveRiskAnalysis: Bool = true

    private var appDisplayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
        ?? "—"
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }

    private var appBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "—"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Plan")
                        Spacer()
                        Text(subscriptionManager.isPro ? "Pro" : "Free")
                            .fontWeight(.semibold)
                            .foregroundStyle(subscriptionManager.isPro ? .green : .secondary)
                    }

                    if subscriptionManager.isPro {
                        HStack {
                            Text("Premium Access")
                            Spacer()
                            Text("Unlimited")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            Text("QR Scans Left")
                            Spacer()
                            Text("\(subscriptionManager.remainingScans)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Document Scans Left")
                            Spacer()
                            Text("\(subscriptionManager.remainingDocuments)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("QR Exports Left")
                            Spacer()
                            Text("\(subscriptionManager.remainingQRCodeExports)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("PDF Exports Left")
                            Spacer()
                            Text("\(subscriptionManager.remainingPDFExports)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Membership")
                } footer: {
                    if !subscriptionManager.isPro {
                        Text("Each premium feature includes one free try before Pro is required.")
                    }
                }

#if DEBUG
                Section {
                    Toggle("Force Pro", isOn: Binding(
                        get: { subscriptionManager.debugForcePro },
                        set: { enabled in
                            subscriptionManager.setDebugForcePro(enabled)
                        }
                    ))
                    .tint(.orange)
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Debug-only override for local testing. This does not affect App Store subscriptions.")
                }
#endif

                Section {
                    Toggle("Save scans to History", isOn: $saveToHistory)
                    Toggle("Confirm before opening links", isOn: $confirmBeforeOpen)
                    Toggle("Aggressive risk analysis", isOn: $aggressiveRiskAnalysis)
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Aggressive mode applies extra heuristics (suspicious TLDs, file types, path tricks, encoding, keywords) to highlight potentially risky links.")
                }

                Section {
                    NavigationLink("How to Use", destination: HowToUseView())
                } header: {
                    Text("Help")
                }

                Section {
                    HStack {
                        Text("App")
                        Spacer()
                        Text(appDisplayName)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(appVersion) (\(appBuild))")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .background(Color(.systemBackground))
    }
}

struct HowToUseView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Scan Codes", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text("Point your camera at a QR code or barcode to scan it automatically. Ensure there is enough light and the code is clearly visible.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 12) {
                    Label("Import from Photos", systemImage: "photo.on.rectangle")
                        .font(.headline)
                         .foregroundStyle(.primary)
                    
                    Text("Have a code saved in your gallery? Tap the 'Photo' button on the scan screen to import it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 12) {
                    Label("Paste Content", systemImage: "doc.on.clipboard")
                        .font(.headline)
                         .foregroundStyle(.primary)
                    
                    Text("You can paste text or access the clipboard directly to analyze potential codes or links.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("How to Scan")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Automatic History", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                         .foregroundStyle(.primary)
                    
                    Text("All your scans are saved to the History tab automatically, so you can find them later.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Features")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Document Scanning", systemImage: "doc.text.viewfinder")
                        .font(.headline)
                         .foregroundStyle(.primary)
                    
                    Text("Use the Documents tab to scan physical documents. The app will automatically detect edges and crop them. You can save multi-page documents and export them as PDFs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Document Scanner")
            }
            
            Section {
                Text("This app supports various formats including QR Code, Aztec, DataMatrix, PDF417, EAN-13, EAN-8, UPC-E, Code 39, and Code 128.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Supported Formats")
            }
        }
        .navigationTitle("How to Use")
        .navigationBarTitleDisplayMode(.inline)
    }
}
