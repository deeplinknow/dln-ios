import Foundation

// MARK: - Query values (SDK-35, FLOW-53)

/// One query parameter value with `URLSearchParams` semantics:
/// `?k=v` → `.string("v")`, `?k` or `?k=` → `.flag`, `?k=a&k=b` → `.list(["a", "b"])`.
public enum DLNQueryValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case flag
    case list([String])

    /// The value as a single string: the string, the first list element, or `nil` for a flag.
    public var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .list(let values): return values.first
        case .flag: return nil
        }
    }

    /// All values as strings (a flag yields `[]`).
    public var stringValues: [String] {
        switch self {
        case .string(let value): return [value]
        case .list(let values): return values
        case .flag: return []
        }
    }

    /// `String`, `true` (`Bool`) or `[String]`, i.e. the JSON wire shape.
    public var anyValue: Any {
        switch self {
        case .string(let value): return value
        case .flag: return true
        case .list(let values): return values
        }
    }

    init?(json value: Any) {
        switch value {
        case let string as String: self = .string(string)
        case let bool as Bool: if bool { self = .flag } else { return nil }
        case let array as [AnyCodable]:
            self = .list(array.compactMap { item in
                if let s = item.value as? String { return s }
                if let n = item.value as? NSNumber { return n.stringValue }
                return nil
            })
        case let int as Int: self = .string(String(int))
        case let double as Double: self = .string(String(double))
        default: return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let string = try? c.decode(String.self) {
            self = .string(string)
        } else if let bool = try? c.decode(Bool.self), bool {
            self = .flag
        } else if let list = try? c.decode([String].self) {
            self = .list(list)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected string, true or [string]")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let value): try c.encode(value)
        case .flag: try c.encode(true)
        case .list(let values): try c.encode(values)
        }
    }
}

// MARK: - Errors (SDK-04, SDK-55)

/// Error thrown by the throwing APIs (`initializeThrowing`, `checkDeferredDeepLinkThrowing`,
/// `findDeferredUserThrowing`) and kept in `DeepLinkNow.lastError` (SDK-85). Codes are the same
/// on every DLN SDK.
public struct DeepLinkNowError: Error, CustomStringConvertible, @unchecked Sendable {
    public enum Code: String, Sendable, CaseIterable {
        /// No successful `initialize`. `cause` holds the init failure when there was one.
        case notInitialized
        /// HTTP 401.
        case invalidApiKey
        /// HTTP 403 "Account is not active".
        case accountInactive
        /// HTTP 403 "No credits remaining".
        case noCredits
        /// HTTP 429.
        case rateLimited
        /// HTTP 400 (and other unexpected 4xx).
        case badRequest
        /// HTTP 5xx.
        case server
        /// Transport failure, timeout or offline.
        case network
        /// Unparseable or unexpected response body.
        case invalidResponse
        /// Invalid `DLNConfig` (e.g. malformed or non-https `baseUrl`, empty key). iOS-specific.
        case invalidConfiguration
    }

    public let code: Code
    /// HTTP status, when the error came from a response.
    public let statusCode: Int?
    /// The server's `error` / `message` string, or a short SDK description.
    public let message: String?
    /// The underlying error (`URLError`, `DecodingError`, or for `.notInitialized` the init failure).
    public let underlying: Error?

    public init(_ code: Code, statusCode: Int? = nil, message: String? = nil, underlying: Error? = nil) {
        self.code = code
        self.statusCode = statusCode
        self.message = message
        self.underlying = underlying
    }

    /// For `.notInitialized`: the error the last `initialize` failed with, if any.
    public var cause: DeepLinkNowError? { underlying as? DeepLinkNowError }

    /// Transient errors are retried (SDK-53).
    var isTransient: Bool {
        code == .network || code == .server || code == .rateLimited
    }

    public var description: String {
        var parts = ["DeepLinkNowError.\(code.rawValue)"]
        if let statusCode = statusCode { parts.append("HTTP \(statusCode)") }
        if let message = message { parts.append(message) }
        if let cause = cause { parts.append("cause: \(cause)") }
        return parts.joined(separator: " ")
    }
}

// MARK: - App info (SDK-03, SDK-05)

/// What a successful initialization learned about the app.
public struct DLNAppInfo: Equatable, Sendable {
    public let appId: String
    public let alias: String
    public let name: String?
    /// `{alias}.deeplinknow.com` plus every verified custom domain, lowercased.
    public let linkDomains: [String]
    /// First verified custom domain, else `{alias}.deeplinknow.com` (SDK-18).
    public let primaryDomain: String
    public let accountStatus: String
    public let creditsRemaining: Int?
}

// MARK: - Parsed link (SDK-30)

/// A link on one of the app's domains, parsed with the shared SDK rules.
public struct DLNParsedLink: Equatable, Sendable {
    /// Path, not decoded, always starting with "/" (SDK-34).
    public let path: String
    /// Query parameters (SDK-35).
    public let queryParams: [String: DLNQueryValue]
    /// "/" + path + "?query" exactly as in the URL (SDK-36). No fragment.
    public let fullPath: String
    /// The URL that was parsed.
    public let url: String

    /// Legacy shape: `String`, `true` or `[String]` values.
    public var parameters: [String: Any] {
        queryParams.mapValues { $0.anyValue }
    }
}

// MARK: - Deferred deep link (SDK-10…19)

public enum DLNDeferredSource: String, Codable, Sendable {
    /// Android Play Install Referrer (never produced on iOS; listed for parity).
    case referrer
    /// The link the landing page copied to the pasteboard.
    case clipboard
    /// Server fingerprint match (best effort, scored).
    case fingerprint
}

/// Options for `checkDeferredDeepLink`.
public struct DLNDeferredOptions: Sendable {
    /// Discard fingerprint candidates with `confidence_score` below this. `nil` = no filter (default).
    public var minConfidence: Double?
    /// Check the pasteboard before fingerprinting (default `true`). May show the iOS 16+ paste prompt.
    public var useClipboard: Bool
    /// Ignore the first-launch flag (default `false`).
    public var force: Bool

    public init(minConfidence: Double? = nil, useClipboard: Bool = true, force: Bool = false) {
        self.minConfidence = minConfidence
        self.useClipboard = useClipboard
        self.force = force
    }
}

public typealias DeferredDeepLinkOptions = DLNDeferredOptions

/// The result of `checkDeferredDeepLink` (same fields on every DLN SDK).
public struct DLNDeferredDeepLink: Sendable {
    /// `fullPath` up to the first "?", not decoded, starting with "/".
    public let path: String
    /// Query parameters (string, flag or list).
    public let queryParams: [String: DLNQueryValue]
    /// Path + query as received.
    public let fullPath: String
    /// Absolute https URL of the link.
    public let url: String
    public let source: DLNDeferredSource
    /// 0–100. Always 100 for `clipboard`.
    public let confidenceScore: Double
    /// Always `.high` for `clipboard`.
    public let matchQuality: ConfidenceLevel
    public let deeplinkId: String?
    public let targetUrl: String?
    public let campaignId: String?
    public let metadata: [String: AnyCodable]?
    public let matchedAt: String?
    public let expiresAt: String?
    /// Fingerprint results only.
    public let matchDetails: MatchDetails?

    /// Legacy-style `[String: Any]` view of `queryParams`.
    public var parameters: [String: Any] {
        queryParams.mapValues { $0.anyValue }
    }
}

public typealias DeferredDeepLink = DLNDeferredDeepLink
