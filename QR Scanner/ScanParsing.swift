import Foundation

enum ScanKind: String {
    case url
    case wifi
    case email
    case phone
    case sms
    case geo
    case vcard
    case text
}

struct ParsedScan {
    let raw: String
    let kind: ScanKind
    let normalizedURL: URL?
}

enum RiskLevel: String {
    case low, medium, high
}

struct URLRiskReport {
    let flags: [String]
    let level: RiskLevel
}

struct ScanParser {
    static func parse(_ input: String) -> ParsedScan {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)

        let lower = raw.lowercased()

        if lower.hasPrefix("wifi:") { return .init(raw: raw, kind: .wifi, normalizedURL: nil) }
        if lower.hasPrefix("begin:vcard") { return .init(raw: raw, kind: .vcard, normalizedURL: nil) }
        if lower.hasPrefix("mailto:") || looksLikeEmail(raw) { return .init(raw: raw, kind: .email, normalizedURL: nil) }
        if lower.hasPrefix("tel:") || looksLikePhone(raw) { return .init(raw: raw, kind: .phone, normalizedURL: nil) }
        if lower.hasPrefix("sms:") || lower.hasPrefix("smsto:") { return .init(raw: raw, kind: .sms, normalizedURL: nil) }
        if lower.hasPrefix("geo:") { return .init(raw: raw, kind: .geo, normalizedURL: nil) }

        if let url = normalizeURL(raw) {
            return .init(raw: raw, kind: .url, normalizedURL: url)
        }

        return .init(raw: raw, kind: .text, normalizedURL: nil)
    }

    private static func normalizeURL(_ raw: String) -> URL? {
        // Already has a scheme
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }

        // Common scheme-less URLs
        let lower = raw.lowercased()
        if lower.hasPrefix("www.") {
            return URL(string: "https://" + raw)
        }

        // Heuristic: contains a dot, no spaces
        if raw.contains(".") && !raw.contains(" ") {
            return URL(string: "https://" + raw)
        }

        return nil
    }

    private static func looksLikeEmail(_ raw: String) -> Bool {
        // Lightweight heuristic; keep MVP simple.
        return raw.contains("@") && raw.contains(".") && !raw.contains(" ")
    }

    private static func looksLikePhone(_ raw: String) -> Bool {
        let stripped = raw.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        return stripped.count >= 7 && stripped.count <= 16
    }
}

struct URLRiskAnalyzer {
    static let commonShorteners: Set<String> = [
        "bit.ly", "t.co", "tinyurl.com", "goo.gl", "is.gd", "buff.ly", "ow.ly", "rebrand.ly"
    ]

    static func analyze(_ url: URL, raw: String) -> URLRiskReport {
        var flags: [String] = []

        let scheme = (url.scheme ?? "").lowercased()
        if scheme != "https" { flags.append("Not HTTPS") }

        if url.user != nil || url.password != nil {
            flags.append("Contains user info (@ in URL)")
        }

        let host = (url.host ?? "").lowercased()

        if host.contains("xn--") {
            flags.append("Punycode domain (possible look‑alike)")
        }

        if isIPAddress(host) {
            flags.append("IP address host")
        }

        if commonShorteners.contains(host) {
            flags.append("Link shortener")
        }

        if raw.count >= 140 {
            flags.append("Very long URL")
        }

        // Non-standard port
        if let port = url.port, port != 443 {
            flags.append("Non-standard port :\(port)")
        }

        // Suspicious TLDs
        let suspiciousTLDs: Set<String> = ["zip", "mov", "gq", "tk", "ml", "cf"]
        if let hostTLD = host.split(separator: ".").last.map(String.init), suspiciousTLDs.contains(hostTLD) {
            flags.append("Suspicious TLD (\(hostTLD))")
        }

        // Many subdomains
        let subdomainCount = max(0, host.split(separator: ".").count - 2)
        if subdomainCount >= 3 {
            flags.append("Many subdomains")
        }

        // Long path or query
        if let path = url.path, path.count > 80 { flags.append("Long path") }
        if let query = url.query, query.count > 120 { flags.append("Long query") }

        // '@' in path or query (phishing technique)
        if raw.contains("@") && !host.contains("@") {
            flags.append("@ in path or query")
        }

        let level: RiskLevel
        // Small, opinionated scoring for MVP
        if flags.contains("Punycode domain (possible look‑alike)") || flags.contains("IP address host") {
            level = .high
        } else if flags.count >= 2 {
            level = .medium
        } else {
            level = .low
        }

        return .init(flags: flags, level: level)
    }

    private static func isIPAddress(_ host: String) -> Bool {
        // Simple IPv4 check
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        for p in parts {
            guard let n = Int(p), (0...255).contains(n) else { return false }
        }
        return true
    }
}
