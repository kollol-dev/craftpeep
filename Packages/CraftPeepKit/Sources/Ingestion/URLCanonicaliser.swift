import Foundation

/// Produces the key used to recognise the same page across sources and refreshes.
/// The result is a comparison key, not necessarily a URL worth opening: always open the original.
public enum URLCanonicaliser {
    /// Query parameters that identify a campaign or a click, never the page.
    private static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid", "yclid",
        "_hsenc", "_hsmi", "ref_src", "ref_url", "cmpid", "ncid", "guccounter"
    ]

    /// Returns nil for anything that is not an absolute http or https URL with a host.
    public static func canonical(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var host = components.host?.lowercased(), !host.isEmpty
        else { return nil }

        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasSuffix(".") { host.removeLast() }

        // http and https versions of a page are the same story.
        components.scheme = "https"
        components.host = host
        components.fragment = nil
        components.user = nil
        components.password = nil
        if components.port == 80 || components.port == 443 { components.port = nil }

        var path = components.percentEncodedPath
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        if path == "/" { path = "" }
        components.percentEncodedPath = path

        if let items = components.queryItems {
            let kept = items
                .filter { item in
                    let name = item.name.lowercased()
                    return !name.hasPrefix("utm_") && !trackingParameters.contains(name)
                }
                .sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
            components.queryItems = kept.isEmpty ? nil : kept
        }

        return components.string
    }

    /// The same check without rewriting: an absolute http(s) URL, or nil.
    public static func webURL(_ string: String, relativeTo base: String? = nil) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let baseURL = base.flatMap { URL(string: $0) }
        guard let url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }
}
