import SwiftUI
import UIKit

struct ScanResultView: View {
    @Environment(\.openURL) private var openURL
    @State private var showConfirm = false
    @AppStorage("aggressiveRiskAnalysis") private var aggressive = true

    let parsed: ParsedScan
    let confirmBeforeOpen: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    HStack {
                        Text("Detected")
                        Spacer()
                        Text(parsed.kind.rawValue.uppercased())
                            .foregroundStyle(.secondary)
                    }
                }

                if parsed.kind == .url, let url = parsed.normalizedURL {
                    urlSection(url)
                }

                Section("Decoded content") {
                    Text(parsed.raw)
                        .textSelection(.enabled)

                    Button("Copy") {
                        UIPasteboard.general.string = parsed.raw
                    }

                    ShareLink(item: parsed.raw) {
                        Text("Share")
                    }
                }
            }
            .navigationTitle("Review")
        }
    }

    private func urlSection(_ url: URL) -> some View {
        let report = URLRiskAnalyzer.analyze(url, raw: parsed.raw, aggressive: aggressive)

        return Section("URL preview") {
            HStack {
                Text("Host")
                Spacer()
                Text(url.host ?? "—")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Text("Scheme")
                Spacer()
                Text((url.scheme ?? "—").uppercased())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Risk")
                Spacer()
                Text(report.level.rawValue.uppercased())
                    .foregroundStyle(report.level == .high ? .red : (report.level == .medium ? .orange : .secondary))
            }

            if !report.flags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Flags")
                    ForEach(report.flags, id: \.self) { flag in
                        let isHigh = flag == "Punycode domain (possible look‑alike)" ||
                                     flag == "IP address host" ||
                                     flag == "Path traversal sequences" ||
                                     flag.hasPrefix("Suspicious file type")
                        Text("• \(flag)")
                            .foregroundStyle(isHigh ? .red : .secondary)
                    }
                }
            }

            Button("Open Link") {
                if confirmBeforeOpen {
                    showConfirm = true
                } else {
                    openURL(url)
                }
            }
            .alert("Open this link?", isPresented: $showConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Open") { openURL(url) }
            } message: {
                Text(url.absoluteString)
            }
        }
    }
}

