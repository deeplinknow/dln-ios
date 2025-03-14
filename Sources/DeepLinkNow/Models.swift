import Foundation

// Renamed to DLNConfiguration to avoid conflict
public struct DLNConfiguration {
    public let apiKey: String
    public let enableLogs: Bool
    public let customDomain: String?
    
    public init(apiKey: String, enableLogs: Bool = false, customDomain: String? = nil) {
        self.apiKey = apiKey
        self.enableLogs = enableLogs
        self.customDomain = customDomain
    }
}

// Renamed to DLNErrorType to avoid conflict
public enum DLNErrorType: Error {
    case notInitialized
    case invalidURL
    case serverError
    case clipboardAccessDenied
}

public struct Attribution: Codable {
    public let channel: String?
    public let campaign: String?
    public let medium: String?
    public let source: String?
}

// Renamed to DLNDeeplinkMatch to avoid conflict
public struct DLNDeeplinkMatch: Codable {
    public let id: String
    public let targetUrl: String
    public let metadata: [String: DLNAnyCodable]
    public let campaignId: String?
    public let matchedAt: String
    public let expiresAt: String
    public let attribution: Attribution?
    
    private enum CodingKeys: String, CodingKey {
        case id
        case targetUrl = "target_url"
        case metadata
        case campaignId = "campaign_id"
        case matchedAt = "matched_at"
        case expiresAt = "expires_at"
        case attribution
    }
}

// Renamed to DLNMatchResponse to avoid conflict
public struct DLNMatchResponse: Codable {
    public let match: Match
    public let deepLink: String?
    public let attribution: Attribution?
    
    private enum CodingKeys: String, CodingKey {
        case match
        case deepLink = "deep_link"
        case attribution
    }
    
    public struct Match: Codable {
        public let deeplink: DLNDeeplinkMatch?
        public let confidenceScore: Double
        public let ttlSeconds: Int
        
        private enum CodingKeys: String, CodingKey {
            case deeplink
            case confidenceScore = "confidence_score"
            case ttlSeconds = "ttl_seconds"
        }
    }
}

// Renamed to DLNInitResponse to avoid conflict
public struct DLNInitResponse: Codable {
    public let app: App
    public let account: Account
    
    public struct App: Codable {
        public let id: String
        public let name: String
        public let timezone: String
        public let androidPackageName: String?
        public let androidSha256Cert: String?
        public let iosBundleId: String?
        public let iosAppStoreId: String?
        public let iosAppPrefix: String?
        public let customDomains: [CustomDomain]
        
        private enum CodingKeys: String, CodingKey {
            case id, name, timezone
            case androidPackageName = "android_package_name"
            case androidSha256Cert = "android_sha256_cert"
            case iosBundleId = "ios_bundle_id"
            case iosAppStoreId = "ios_app_store_id"
            case iosAppPrefix = "ios_app_prefix"
            case customDomains = "custom_domains"
        }
        
        public struct CustomDomain: Codable {
            public let domain: String?
            public let verified: Bool?
        }
    }
    
    public struct Account: Codable {
        public let status: String
        public let creditsRemaining: Int
        public let rateLimits: RateLimits
        
        private enum CodingKeys: String, CodingKey {
            case status
            case creditsRemaining = "credits_remaining"
            case rateLimits = "rate_limits"
        }
        
        public struct RateLimits: Codable {
            public let matchesPerSecond: Int
            public let matchesPerDay: Int
            
            private enum CodingKeys: String, CodingKey {
                case matchesPerSecond = "matches_per_second"
                case matchesPerDay = "matches_per_day"
            }
        }
    }
}

// Renamed to DLNAnyCodable to avoid conflict
public struct DLNAnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = value
        } else if let value = try? container.decode(Double.self) {
            self.value = value
        } else if let value = try? container.decode(Bool.self) {
            self.value = value
        } else if let value = try? container.decode([String: DLNAnyCodable].self) {
            self.value = value
        } else if let value = try? container.decode([DLNAnyCodable].self) {
            self.value = value
        } else {
            self.value = NSNull()
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let value as String:
            try container.encode(value)
        case let value as Int:
            try container.encode(value)
        case let value as Double:
            try container.encode(value)
        case let value as Bool:
            try container.encode(value)
        case let value as [String: DLNAnyCodable]:
            try container.encode(value)
        case let value as [DLNAnyCodable]:
            try container.encode(value)
        default:
            try container.encodeNil()
        }
    }
} 