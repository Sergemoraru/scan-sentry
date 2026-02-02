import Foundation

enum URLSanitizer {
    /// Removes common tracking parameters (utm_*, fbclid, gclid, etc.) while preserving
    /// the rest of the URL.
    static func sanitized(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        guard let items = comps.queryItems, !items.isEmpty else { return url }

        let blockedExact: Set<String> = [
            "fbclid",
            "gclid",
            "dclid",
            "igshid",
            "msclkid",
            "mc_cid",
            "mc_eid"
        ]

        let filtered = items.filter { item in
            let key = item.name.lowercased()
            if key.hasPrefix("utm_") { return false }
            if blockedExact.contains(key) { return false }
            return true
        }

        comps.queryItems = filtered.isEmpty ? nil : filtered
        return comps.url ?? url
    }
}
