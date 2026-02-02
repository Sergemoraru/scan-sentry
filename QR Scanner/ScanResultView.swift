import SwiftUI
import UIKit
import NetworkExtension
import SafariServices

struct ScanResultView: View {
    @Environment(\.openURL) private var openURL
    @State private var showConfirm = false
    @AppStorage("aggressiveRiskAnalysis") private var aggressive = true
    @State private var wifiAlert: (title: String, message: String)? = nil
    @State private var safariURL: URL? = nil
    @State private var isShowingSafari: Bool = false

    let parsed: ParsedScan
    let confirmBeforeOpen: Bool

    private var urlReport: URLRiskReport? {
        guard parsed.kind == .url, let url = parsed.normalizedURL else { return nil }
        return URLRiskAnalyzer.analyze(url, raw: parsed.raw, aggressive: aggressive)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let report = urlReport {
                    Section {
                        HStack(spacing: 10) {
                            RiskBadge(level: report.level)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Review before opening")
                                    .font(.headline)
                                if let url = parsed.normalizedURL {
                                    Text(url.host ?? url.absoluteString)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                }

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

                    if parsed.kind == .wifi, let wifi = ScanParser.parseWiFi(parsed.raw) {
                        Button {
                            joinWiFi(wifi)
                        } label: {
                            Label("Join Wi‑Fi \(wifi.ssid)", systemImage: "wifi")
                        }
                    }
                }
            }
            .navigationTitle("Review")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if parsed.kind == .url, let url = parsed.normalizedURL {
                        Button {
                            UIPasteboard.general.string = URLSanitizer.sanitized(url).absoluteString
                        } label: {
                            Label("Copy Sanitized", systemImage: "link.badge.plus")
                        }
                    }

                    Button {
                        UIPasteboard.general.string = parsed.raw
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }

                    ShareLink(item: parsed.raw) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .alert(wifiAlert?.title ?? "", isPresented: .init(get: { wifiAlert != nil }, set: { if !$0 { wifiAlert = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(wifiAlert?.message ?? "")
            }
            .sheet(isPresented: $isShowingSafari) {
                if let url = safariURL {
                    SafariView(url: url)
                }
            }
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

            Button {
                safariURL = url
                isShowingSafari = true
            } label: {
                Label("Open In‑App", systemImage: "safari")
            }

            Button {
                UIPasteboard.general.string = URLSanitizer.sanitized(url).absoluteString
            } label: {
                Label("Copy Sanitized URL", systemImage: "link.badge.plus")
            }
        }
    }

    private func joinWiFi(_ wifi: WiFiConfig) {
        let config: NEHotspotConfiguration
        if wifi.isOpen {
            config = NEHotspotConfiguration(ssid: wifi.ssid)
        } else if let pass = wifi.passphrase {
            config = NEHotspotConfiguration(ssid: wifi.ssid, passphrase: pass, isWEP: wifi.isWEP)
        } else {
            wifiAlert = ("Wi‑Fi", "Missing password for network \(wifi.ssid)")
            return
        }
        config.joinOnce = true
        config.hidden = wifi.hidden
        NEHotspotConfigurationManager.shared.apply(config) { error in
            DispatchQueue.main.async {
                if let nsError = error as NSError? {
                    if nsError.domain == NEHotspotConfigurationErrorDomain,
                       let code = NEHotspotConfigurationError(rawValue: nsError.code) {
                        switch code {
                        case .userDenied:
                            wifiAlert = ("Wi‑Fi", "User canceled join.")
                        case .invalid:
                            wifiAlert = ("Wi‑Fi", "Invalid configuration.")
                        case .invalidSSID:
                            wifiAlert = ("Wi‑Fi", "Invalid SSID.")
                        case .invalidWPAPassphrase, .invalidWEPPassphrase:
                            wifiAlert = ("Wi‑Fi", "Invalid Wi‑Fi password.")
                        case .alreadyAssociated:
                            wifiAlert = ("Wi‑Fi", "Already connected to \(wifi.ssid)")
                        default:
                            wifiAlert = ("Wi‑Fi", nsError.localizedDescription)
                        }
                    } else {
                        wifiAlert = ("Wi‑Fi", nsError.localizedDescription)
                    }
                } else {
                    wifiAlert = ("Wi‑Fi", "Joined \(wifi.ssid)")
                }
            }
        }
    }
}

private struct RiskBadge: View {
    let level: RiskLevel

    private var title: String {
        switch level {
        case .low: return "LOW"
        case .medium: return "MEDIUM"
        case .high: return "HIGH"
        }
    }

    private var color: Color {
        switch level {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.35)))
            .foregroundStyle(color)
            .accessibilityLabel("Risk \(level.rawValue)")
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
