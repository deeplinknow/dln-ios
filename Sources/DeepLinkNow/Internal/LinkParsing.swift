import Foundation

/// Host rule (SDK-31/33/37/38) and URL parsing (SDK-30/32/34/35/36).
/// Pure functions: no SDK state, no UIKit, no I/O.
enum LinkParsing {

    static let primaryHostSuffix = "deeplinknow.com"

    /// Subdomains of deeplinknow.com that belong to DLN itself, never to a tenant.
    static let reservedSubdomains: Set<String> = ["www", "app", "api", "docs", "m", "mail"]

    /// Lowercases the host, drops a trailing "." and any ":port".
    static func normalizeHost(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Strip a port when the input is "host:port" (not an IPv6 literal).
        if !host.hasPrefix("["), let colon = host.lastIndex(of: ":") {
            let port = host[host.index(after: colon)...]
            if !port.isEmpty, port.allSatisfy({ $0.isNumber }) {
                host = String(host[..<colon])
            }
        }
        while host.hasSuffix(".") { host.removeLast() }
        return host
    }

    /// SDK-31 / SDK-37.
    /// - Parameter domains: the app's link domains after a successful init (lowercased), or
    ///   `nil` when no init has succeeded yet (provisional rule).
    static func isAllowedHost(_ rawHost: String, domains: Set<String>?) -> Bool {
        let host = normalizeHost(rawHost)
        guard !host.isEmpty else { return false }
        if let domains = domains {
            return domains.contains(host)
        }
        // Provisional rule: exactly one non-reserved label in front of ".deeplinknow.com".
        let suffix = "." + primaryHostSuffix
        guard host.hasSuffix(suffix) else { return false }
        let label = String(host.dropLast(suffix.count))
        guard !label.isEmpty, !label.contains("."), !reservedSubdomains.contains(label) else { return false }
        return label.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
    }

    struct Parsed {
        let path: String
        let queryParams: [String: DLNQueryValue]
        let queryOrder: [String]
        let fullPath: String
        let url: String
    }

    /// Parses an absolute http(s) URL on an allowed host. Returns nil for anything else.
    static func parse(_ urlString: String, domains: Set<String>?) -> Parsed? {
        guard let components = URLComponents(string: urlString) else { return nil }
        return parse(components: components, original: urlString, domains: domains)
    }

    static func parse(url: URL, domains: Set<String>?) -> Parsed? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return parse(components: components, original: url.absoluteString, domains: domains)
    }

    private static func parse(components: URLComponents, original: String, domains: Set<String>?) -> Parsed? {
        guard let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        guard let host = components.host, isAllowedHost(host, domains: domains) else { return nil }

        var path = components.percentEncodedPath
        if path.isEmpty { path = "/" }
        if !path.hasPrefix("/") { path = "/" + path }

        var fullPath = path
        let query = components.percentEncodedQuery ?? ""
        if !query.isEmpty { fullPath += "?" + query }

        let (params, order) = parseQuery(query)
        return Parsed(path: path, queryParams: params, queryOrder: order, fullPath: fullPath, url: original)
    }

    /// `path` = `fullPath` up to the first "?" (or "#"), undecoded, always starting with "/" (SDK-34).
    static func path(fromFullPath fullPath: String) -> String {
        var end = fullPath.endIndex
        if let q = fullPath.firstIndex(where: { $0 == "?" || $0 == "#" }) { end = q }
        var path = String(fullPath[..<end])
        if path.isEmpty { path = "/" }
        if !path.hasPrefix("/") { path = "/" + path }
        return path
    }

    /// The query portion of a full path (after the first "?", without any fragment).
    static func query(fromFullPath fullPath: String) -> String {
        guard let q = fullPath.firstIndex(of: "?") else { return "" }
        var query = String(fullPath[fullPath.index(after: q)...])
        if let hash = query.firstIndex(of: "#") { query = String(query[..<hash]) }
        return query
    }

    /// WHATWG `URLSearchParams` semantics, reduced to FLOW-53:
    /// "+" → space, %XX as UTF-8, a single empty value → `.flag`, repeated keys → `.list` in order.
    static func parseQuery(_ query: String) -> ([String: DLNQueryValue], [String]) {
        var values: [String: [String]] = [:]
        var order: [String] = []
        let trimmed = query.hasPrefix("?") ? String(query.dropFirst()) : query
        for pair in trimmed.split(separator: "&", omittingEmptySubsequences: true) {
            let name: Substring
            let value: Substring
            if let eq = pair.firstIndex(of: "=") {
                name = pair[..<eq]
                value = pair[pair.index(after: eq)...]
            } else {
                name = pair
                value = ""
            }
            let key = decodeComponent(name)
            if values[key] == nil { order.append(key) }
            values[key, default: []].append(decodeComponent(value))
        }
        var result: [String: DLNQueryValue] = [:]
        for (key, list) in values {
            if list.count > 1 {
                result[key] = .list(list)
            } else if let only = list.first, !only.isEmpty {
                result[key] = .string(only)
            } else {
                result[key] = .flag
            }
        }
        return (result, order)
    }

    /// application/x-www-form-urlencoded decoding. Invalid percent sequences are kept literally.
    static func decodeComponent<S: StringProtocol>(_ raw: S) -> String {
        let spaced = raw.replacingOccurrences(of: "+", with: " ")
        if let decoded = spaced.removingPercentEncoding { return decoded }
        // Decode valid %XX runs only, keep the rest (WHATWG percent-decode is lenient).
        var bytes: [UInt8] = []
        let utf8 = Array(spaced.utf8)
        var i = 0
        while i < utf8.count {
            if utf8[i] == UInt8(ascii: "%"), i + 2 < utf8.count,
               let byte = UInt8(String(bytes: utf8[(i + 1)...(i + 2)], encoding: .ascii) ?? "", radix: 16) {
                bytes.append(byte)
                i += 3
            } else {
                bytes.append(utf8[i])
                i += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Strict encoding used by `createDeepLink` so the output round-trips through `parseQuery`.
    static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func encodeQueryComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? value
    }

    static let pathAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "?#%")
        return set
    }()
}
