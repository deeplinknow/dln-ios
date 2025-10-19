import Foundation
import UIKit
import CoreTelephony
import AdSupport

// Configuration
public struct DLNConfig {
    public let apiKey: String
    public let enableLogs: Bool
    public let baseUrl: String?
    public let timeout: TimeInterval?
    public let retryAttempts: Int?
    
    public init(
        apiKey: String,
        enableLogs: Bool = false,
        baseUrl: String? = nil,
        timeout: TimeInterval? = nil,
        retryAttempts: Int? = nil
    ) {
        self.apiKey = apiKey
        self.enableLogs = enableLogs
        self.baseUrl = baseUrl
        self.timeout = timeout
        self.retryAttempts = retryAttempts
    }
}

// Error types
public enum DLNError: Error {
    case invalidURL
    case serverError(String, String?, String?)  // error, status?, details?
    case notInitialized
    case badRequest
    case unauthorized
    case forbidden
    case notFound
    case tooManyRequests
    case internalServerError
    
    public var statusCode: Int {
        switch self {
        case .badRequest: return 400
        case .unauthorized: return 401
        case .forbidden: return 403
        case .notFound: return 404
        case .tooManyRequests: return 429
        case .internalServerError: return 500
        default: return 0
        }
    }
}

// Attribution data
public struct DLNAttribution: Codable, Sendable {
    public let campaign: String?
    public let source: String?
    public let medium: String?
    
    enum CodingKeys: String, CodingKey {
        case campaign
        case source
        case medium
    }
}

// Custom parameters
@frozen public struct DLNCustomParameters: Sendable {
    let dictionary: [String: String]
    
    public init(_ parameters: [String: String]) {
        self.dictionary = parameters
    }
    
    public init(_ parameters: [String: Any]) {
        self.dictionary = parameters.mapValues { String(describing: $0) }
    }
}

// Common Types
public struct CustomDomain: Codable {
    let domain: String?
    let verified: Bool?
}

public struct AppConfig: Codable {
    let id: String
    let name: String
    let timezone: String
    let alias: String
    let androidPackageName: String?
    let androidSha256Cert: String?
    let iosBundleId: String?
    let iosAppStoreId: String?
    let iosAppPrefix: String?
    let customDomains: [CustomDomain]
    
    enum CodingKeys: String, CodingKey {
        case id, name, timezone, alias
        case androidPackageName = "android_package_name"
        case androidSha256Cert = "android_sha256_cert"
        case iosBundleId = "ios_bundle_id"
        case iosAppStoreId = "ios_app_store_id"
        case iosAppPrefix = "ios_app_prefix"
        case customDomains = "custom_domains"
    }
}

public struct RateLimits: Codable {
    let matchesPerSecond: Int
    let matchesPerDay: Int
    
    enum CodingKeys: String, CodingKey {
        case matchesPerSecond = "matches_per_second"
        case matchesPerDay = "matches_per_day"
    }
}

public struct AccountConfig: Codable {
    public enum Status: String, Codable {
        case active
        case suspended
        case expired
    }
    
    let status: Status
    let creditsRemaining: Int
    let rateLimits: RateLimits
    
    enum CodingKeys: String, CodingKey {
        case status
        case creditsRemaining = "credits_remaining"
        case rateLimits = "rate_limits"
    }
}

// Init Response
public struct InitResponse: Codable {
    let app: AppConfig
    let account: AccountConfig
}

// Match Types
public struct DeepLink: Codable {
    public let id: String
    public let targetUrl: String
    public let metadata: [String: AnyCodable]
    public let campaignId: String?
    public let matchedAt: String
    public let expiresAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case targetUrl = "target_url"
        case metadata
        case campaignId = "campaign_id"
        case matchedAt = "matched_at"
        case expiresAt = "expires_at"
    }
}

// Fingerprint Types
public struct FingerprintMetadata: Codable {
    let screenWidth: Int?
    let screenHeight: Int?
    let pixelRatio: Double?
    let colorDepth: Int?
    let isTablet: Bool?
    let connectionType: String?
    let cpuCores: Int?
    let deviceMemory: Int?
    let source: String
    
    enum CodingKeys: String, CodingKey {
        case screenWidth = "screen_width"
        case screenHeight = "screen_height"
        case pixelRatio = "pixel_ratio"
        case colorDepth = "color_depth"
        case isTablet = "is_tablet"
        case connectionType = "connection_type"
        case cpuCores = "cpu_cores"
        case deviceMemory = "device_memory"
        case source
    }
}

public struct Fingerprint: Codable {
    let ipAddress: String
    let userAgent: String
    let platform: String
    let osVersion: String
    let deviceModel: String
    let language: String
    let timezone: String
    let installedAt: String
    let lastOpenedAt: String
    let deviceId: String?
    let advertisingId: String?
    let vendorId: String?
    let hardwareFingerprint: String?
    let metadata: FingerprintMetadata?
    
    enum CodingKeys: String, CodingKey {
        case ipAddress = "ip_address"
        case userAgent = "user_agent"
        case platform
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case language
        case timezone
        case installedAt = "installed_at"
        case lastOpenedAt = "last_opened_at"
        case deviceId = "device_id"
        case advertisingId = "advertising_id"
        case vendorId = "vendor_id"
        case hardwareFingerprint = "hardware_fingerprint"
        case metadata
    }
}

public struct FingerprintMatch: Codable {
    let ipAddress: String
    let platform: String
    let osVersion: String
    let deviceModel: String
    let language: String
    let timezone: String
    let createdAt: String
    let expiresAt: String
    let deviceId: String?
    let advertisingId: String?
    let vendorId: String?
    let hardwareFingerprint: String?
    let metadata: [String: AnyCodable]?
    
    enum CodingKeys: String, CodingKey {
        case ipAddress = "ip_address"
        case platform
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case language
        case timezone
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case deviceId = "device_id"
        case advertisingId = "advertising_id"
        case vendorId = "vendor_id"
        case hardwareFingerprint = "hardware_fingerprint"
        case metadata
    }
}

public struct MatchComponentDetails: Codable, Sendable {
    public let matched: Bool
    public let score: Double
}

public struct DeviceMatchDetails: Codable, Sendable {
    public let matched: Bool
    public let score: Double
    public let components: DeviceMatchComponents

    public struct DeviceMatchComponents: Codable, Sendable {
        public let platform: Bool
        public let osVersion: Bool
        public let deviceModel: Bool
        public let hardwareFingerprint: Bool
        
        enum CodingKeys: String, CodingKey {
            case platform
            case osVersion = "os_version"
            case deviceModel = "device_model"
            case hardwareFingerprint = "hardware_fingerprint"
        }
    }
}

public struct LocaleMatchDetails: Codable, Sendable {
    public let matched: Bool
    public let score: Double
    public let components: LocaleMatchComponents

    public struct LocaleMatchComponents: Codable, Sendable {
        public let language: Bool
        public let timezone: Bool
    }
}

public struct TimeProximityDetails: Codable, Sendable {
    public let score: Double
    public let timeDifferenceMinutes: Int
    
    enum CodingKeys: String, CodingKey {
        case score
        case timeDifferenceMinutes = "time_difference_minutes"
    }
}

public struct MatchDetails: Codable, Sendable {
    public let ipMatch: MatchComponentDetails
    public let deviceMatch: DeviceMatchDetails
    public let timeProximity: TimeProximityDetails
    public let localeMatch: LocaleMatchDetails
    
    enum CodingKeys: String, CodingKey {
        case ipMatch = "ip_match"
        case deviceMatch = "device_match"
        case timeProximity = "time_proximity"
        case localeMatch = "locale_match"
    }
}

public struct DeeplinkMatch: Codable, Sendable {
    public let id: String
    public let targetUrl: String
    public let metadata: [String: AnyCodable]
    public let campaignId: String?
    public let matchedAt: String
    public let expiresAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case targetUrl = "target_url"
        case metadata
        case campaignId = "campaign_id"
        case matchedAt = "matched_at"
        case expiresAt = "expires_at"
    }
}

public struct Match: Codable, Identifiable, Sendable {
    public let id = UUID()
    public let confidenceScore: Double
    public let matchDetails: MatchDetails
    public let deeplink: DeeplinkMatch?
    
    enum CodingKeys: String, CodingKey {
        case confidenceScore = "confidence_score"
        case matchDetails = "match_details"
        case deeplink
    }
}

public struct MatchResponse: Codable, Sendable {
    public let matches: [Match]
    public let ttlSeconds: Int
    
    enum CodingKeys: String, CodingKey {
        case matches
        case ttlSeconds = "ttl_seconds"
    }
}

public enum ConfidenceLevel: String {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
    
    public var threshold: Int {
        switch self {
        case .high: return 75
        case .medium: return 50
        case .low: return 25
        }
    }
}

// Helper for handling dynamic JSON values
public struct AnyCodable: Codable, @unchecked Sendable {
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
        } else if let value = try? container.decode([String: AnyCodable].self) {
            self.value = value
        } else if let value = try? container.decode([AnyCodable].self) {
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
        case let value as [String: AnyCodable]:
            try container.encode(value)
        case let value as [AnyCodable]:
            try container.encode(value)
        default:
            try container.encodeNil()
        }
    }
}

// Protocol for testable networking
public protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

// Make URLSession conform to the protocol
extension URLSession: URLSessionProtocol {}

// Helper extensions
public extension URLComponents {
    init(_ configure: (inout URLComponents) -> Void) {
        self.init()
        configure(&self)
    }
} 

