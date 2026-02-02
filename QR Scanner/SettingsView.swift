import SwiftUI

struct SettingsView: View {
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
                    Toggle("Save scans to History", isOn: $saveToHistory)
                    Toggle("Confirm before opening links", isOn: $confirmBeforeOpen)
                    Toggle("Aggressive risk analysis", isOn: $aggressiveRiskAnalysis)
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Aggressive mode applies extra heuristics (suspicious TLDs, file types, path tricks, encoding, keywords) to highlight potentially risky links.")
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
