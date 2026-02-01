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

struct WiFiConfig {
    let ssid: String
    let passphrase: String?
    let isWEP: Bool
    let isOpen: Bool
    let hidden: Bool
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

    static func parseWiFi(_ raw: String) -> WiFiConfig? {
        // Expect format WIFI:T:WPA;S:SSID;P:password;H:true;; (case-insensitive)
        let prefix = "wifi:"
        guard raw.lowercased().hasPrefix(prefix) else { return nil }
        let body = String(raw.dropFirst(prefix.count))

        // Split into key:value pairs by ';' while handling escaped '\;' and '\\'
        var pairs: [String] = []
        var current = ""
        var escape = false
        for ch in body {
            if escape {
                current.append(ch)
                escape = false
            } else if ch == "\\" {
                escape = true
            } else if ch == ";" {
                pairs.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { pairs.append(current) }

        func unescape(_ s: String) -> String {
            var out = ""
            var esc = false
            for c in s {
                if esc {
                    out.append(c)
                    esc = false
                } else if c == "\\" {
                    esc = true
                } else {
                    out.append(c)
                }
            }
            return out
        }

        var ssid: String?
        var type: String?
        var pass: String?
        var hidden = false

        for pair in pairs {
            let parts = pair.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].uppercased()
            let value = unescape(parts[1])
            switch key {
            case "S": ssid = value
            case "T": type = value.uppercased()
            case "P": pass = value
            case "H": hidden = (value == "true" || value == "TRUE" || value == "1")
            default: break
            }
        }

        guard let ssidUnwrapped = ssid, !ssidUnwrapped.isEmpty else { return nil }
        let t = (type ?? "").uppercased()
        let isOpen = (t == "NOPASS") || (pass ?? "").isEmpty
        let isWEP = (t == "WEP")
        return WiFiConfig(ssid: ssidUnwrapped, passphrase: isOpen ? nil : pass, isWEP: isWEP, isOpen: isOpen, hidden: hidden)
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

    static func analyze(_ url: URL, raw: String, aggressive: Bool = true) -> URLRiskReport {
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

        if aggressive {
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
            if url.path.count > 80 { flags.append("Long path") }
            if let query = url.query, query.count > 120 { flags.append("Long query") }

            // '@' in path or query (phishing technique)
            if raw.contains("@") && !host.contains("@") {
                flags.append("@ in path or query")
            }

            // Suspicious file extension
            let suspiciousExtensions: Set<String> = ["exe","apk","scr","bat","cmd","jar","dmg","pkg","appx","iso"]
            let ext = url.pathExtension.lowercased()
            if !ext.isEmpty && suspiciousExtensions.contains(ext) {
                flags.append("Suspicious file type (.\(ext))")
            }

            // Path traversal sequences
            let rawLower = raw.lowercased()
            if rawLower.contains("../") || rawLower.contains("..%2f") || rawLower.contains("%2e%2e") {
                flags.append("Path traversal sequences")
            }

            // Heavily percent-encoded
            let percentCount = raw.filter { $0 == "%" }.count
            if percentCount > 10 {
                flags.append("Heavily percent-encoded")
            }

            // Non-ASCII characters
            if raw.unicodeScalars.contains(where: { $0.value > 127 }) {
                flags.append("Non-ASCII characters")
            }

            // Phishing keywords in host or path
            let keywords: [String] = ["login","verify","account","update","secure","bank"]
            let pathLower = url.path.lowercased()
            if keywords.contains(where: { host.contains($0) || pathLower.contains($0) }) {
                flags.append("Phishing keywords")
            }

            // Extremely long URL
            if raw.count > 2048 {
                flags.append("Extremely long URL")
            }
        }

        let level: RiskLevel
        // Expanded scoring with additional high-risk triggers
        let hasSuspiciousFileType = flags.contains(where: { $0.hasPrefix("Suspicious file type") })
        let hasHighRisk = flags.contains("Punycode domain (possible look‑alike)") ||
                          flags.contains("IP address host") ||
                          flags.contains("Path traversal sequences") ||
                          hasSuspiciousFileType

        if hasHighRisk {
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

