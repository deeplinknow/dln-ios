import UIKit
import Foundation
import CoreTelephony
import AdSupport

// Configuration
public struct DLNConfig {
    let apiKey: String
    let enableLogs: Bool
    
    public init(apiKey: String, enableLogs: Bool = false) {
        self.apiKey = apiKey
        self.enableLogs = enableLogs
    }
}

// Error types
public enum DLNError: Error {
    case invalidURL
    case serverError
    case notInitialized
}

// Attribution data
public struct DLNAttribution: Codable {
    public let campaign: String?
    public let source: String?
    public let medium: String?
}

// Custom parameters
public struct DLNCustomParameters {
    let dictionary: [String: Any]
    
    public init(_ parameters: [String: Any]) {
        self.dictionary = parameters
    }
}

// Fingerprint model for device information
struct Fingerprint: Codable {
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
    
    enum CodingKeys: String, CodingKey {
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
    }
}

struct DeeplinkMatch: Codable {
    let id: String
    let targetUrl: String
    let metadata: [String: AnyCodable]
    let campaignId: String?
    let matchedAt: String
    let expiresAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case targetUrl = "target_url"
        case metadata
        case campaignId = "campaign_id"
        case matchedAt = "matched_at"
        case expiresAt = "expires_at"
    }
}

struct MatchResponse: Codable {
    let match: Match
    
    struct Match: Codable {
        let deeplink: DeeplinkMatch?
        let confidenceScore: Double
        let ttlSeconds: Int
        
        enum CodingKeys: String, CodingKey {
            case deeplink
            case confidenceScore = "confidence_score"
            case ttlSeconds = "ttl_seconds"
        }
    }
}

struct InitResponse: Codable {
    let app: App
    let account: Account
    
    struct App: Codable {
        let id: String
        let name: String
        let timezone: String
        let androidPackageName: String?
        let androidSha256Cert: String?
        let iosBundleId: String?
        let iosAppStoreId: String?
        let iosAppPrefix: String?
        let customDomains: [CustomDomain]
        
        enum CodingKeys: String, CodingKey {
            case id, name, timezone
            case androidPackageName = "android_package_name"
            case androidSha256Cert = "android_sha256_cert"
            case iosBundleId = "ios_bundle_id"
            case iosAppStoreId = "ios_app_store_id"
            case iosAppPrefix = "ios_app_prefix"
            case customDomains = "custom_domains"
        }
        
        struct CustomDomain: Codable {
            let domain: String?
            let verified: Bool?
        }
    }
    
    struct Account: Codable {
        let status: String
        let creditsRemaining: Int
        let rateLimits: RateLimits
        
        enum CodingKeys: String, CodingKey {
            case status
            case creditsRemaining = "credits_remaining"
            case rateLimits = "rate_limits"
        }
        
        struct RateLimits: Codable {
            let matchesPerSecond: Int
            let matchesPerDay: Int
            
            enum CodingKeys: String, CodingKey {
                case matchesPerSecond = "matches_per_second"
                case matchesPerDay = "matches_per_day"
            }
        }
    }
}

// Helper for handling dynamic JSON values
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
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
    
    func encode(to encoder: Encoder) throws {
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

// DeferredDeepLinkResponse for checkDeferredDeepLink method
struct DeferredDeepLinkResponse: Codable {
    let deepLink: String?
    let attribution: DLNAttribution?
    
    enum CodingKeys: String, CodingKey {
        case deepLink = "deep_link"
        case attribution
    }
}

// DLNDeviceFingerprint for checkDeferredDeepLink method
struct DLNDeviceFingerprint {
    let deviceModel: String
    let systemVersion: String
    let screenResolution: String
    let timezone: String
    let language: String
    let carrier: String?
    let ipAddress: String?
    let advertisingIdentifier: String?
    
    static func generate() -> DLNDeviceFingerprint {
        let device = UIDevice.current
        let screen = UIScreen.main
        let screenSize = screen.bounds.size
        let scale = screen.scale
        let resolution = "\(Int(screenSize.width * scale))x\(Int(screenSize.height * scale))"
        
        var carrierName: String? = nil
        if #available(iOS 12.0, *) {
            let networkInfo = CTTelephonyNetworkInfo()
            let carrier = networkInfo.serviceSubscriberCellularProviders?.values.first
            carrierName = carrier?.carrierName
        }
        
        return DLNDeviceFingerprint(
            deviceModel: device.model,
            systemVersion: device.systemVersion,
            screenResolution: resolution,
            timezone: TimeZone.current.identifier,
            language: Locale.current.languageCode ?? "en",
            carrier: carrierName,
            ipAddress: nil,
            advertisingIdentifier: ASIdentifierManager.shared().isAdvertisingTrackingEnabled ? 
                ASIdentifierManager.shared().advertisingIdentifier.uuidString : nil
        )
    }
}

public final class DeepLinkNow {
    private static var shared: DeepLinkNow?
    private let config: DLNConfig
    private let installTime: String
    private var initResponse: InitResponse?
    private var validDomains: Set<String> = ["deeplinknow.com", "deeplink.now"]
    
    private init(config: DLNConfig) {
        self.config = config
        self.installTime = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: "Z", with: "+00:00")
    }
    
    private func log(_ message: String, _ args: Any...) {
        if config.enableLogs {
            print("[DeepLinkNow]", message, args)
        }
    }
    
    private func warn(_ message: String) {
        print("[DeepLinkNow] Warning:", message)
    }
    
    public static func initialize(apiKey: String, config: DLNConfig = DLNConfig(apiKey: "", enableLogs: false)) async {
        let instance = DeepLinkNow(config: DLNConfig(
            apiKey: apiKey,
            enableLogs: config.enableLogs
        ))
        shared = instance
        
        instance.log("Initializing with config:", config)
        
        do {
            let data = try await instance.makeAPIRequest(
                endpoint: "init",
                method: "POST",
                body: ["api_key": apiKey]
            )
            
            let decoder = JSONDecoder()
            let response = try decoder.decode(InitResponse.self, from: data)
            instance.initResponse = response
            
            // Cache valid domains
            response.app.customDomains
                .filter { $0.domain != nil && $0.verified == true }
                .forEach { domain in
                    if let domain = domain.domain {
                        instance.validDomains.insert(domain)
                    }
                }
            
            instance.log("Init response:", response)
            instance.log("Valid domains:", instance.validDomains)
        } catch {
            instance.warn("Initialization failed: \(error)")
        }
    }
    
    public static func isValidDomain(_ domain: String) -> Bool {
        guard let shared = shared else { return false }
        return shared.validDomains.contains(domain)
    }
    
    private func getFingerprint() -> Fingerprint {
        let device = UIDevice.current
        let currentTime = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: "Z", with: "+00:00")
        
        return Fingerprint(
            userAgent: "DLN-iOS/\(device.systemVersion)",
            platform: "ios",
            osVersion: device.systemVersion,
            deviceModel: device.model,
            language: Locale.current.languageCode ?? "en",
            timezone: TimeZone.current.identifier,
            installedAt: installTime,
            lastOpenedAt: currentTime,
            deviceId: UIDevice.current.identifierForVendor?.uuidString,
            advertisingId: ASIdentifierManager.shared().advertisingIdentifier.uuidString,
            vendorId: nil,
            hardwareFingerprint: nil
        )
    }
    
    public static func findDeferredUser() async -> MatchResponse? {
        guard let shared = shared else {
            print("[DeepLinkNow] SDK not initialized. Call initialize() first")
            return nil
        }
        
        shared.log("Finding deferred user...")
        
        let fingerprint = shared.getFingerprint()
        let matchRequest = ["fingerprint": fingerprint]
        
        shared.log("Sending match request:", matchRequest)
        
        do {
            let data = try await shared.makeAPIRequest(
                endpoint: "match",
                method: "POST",
                body: try JSONSerialization.jsonObject(with: JSONEncoder().encode(matchRequest)) as? [String: Any]
            )
            
            let decoder = JSONDecoder()
            let response = try decoder.decode(MatchResponse.self, from: data)
            shared.log("Match response:", response)
            return response
            
        } catch {
            shared.warn("API request failed: \(error)")
            return nil
        }
    }
    
    private func makeAPIRequest(endpoint: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        let url = URL(string: "https://deeplinknow.com/api/v1/sdk/\(endpoint)")!
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.httpMethod = method
        
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            log("API request failed: Invalid response type")
            throw DLNError.serverError
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            log("API request failed: \(httpResponse.statusCode)")
            if let errorString = String(data: data, encoding: .utf8) {
                log("Error response: \(errorString)")
            }
            throw DLNError.serverError
        }
        
        return data
    }
    
    public static func checkClipboard() -> String? {
        guard let shared = shared else {
            print("[DeepLinkNow] SDK not initialized. Call initialize() first")
            return nil
        }
        
        shared.log("Checking clipboard")
        let content = UIPasteboard.general.string
        shared.log("Clipboard content:", content ?? "nil")
        return content
    }
    
    public typealias DeferredDeepLinkHandler = (URL?, DLNAttribution?) -> Void
    
    public static func checkDeferredDeepLink(completion: @escaping DeferredDeepLinkHandler) {
        if shared == nil {
            print("DeepLinkNow SDK not initialized. Call initialize() first")
            completion(nil, nil)
            return
        }
        
        // Generate device fingerprint
        let fingerprint = DLNDeviceFingerprint.generate()
        
        // Create request body
        let body: [String: Any] = [
            "fingerprint": [
                "device_model": fingerprint.deviceModel,
                "system_version": fingerprint.systemVersion,
                "screen_resolution": fingerprint.screenResolution,
                "timezone": fingerprint.timezone,
                "language": fingerprint.language,
                "carrier": fingerprint.carrier as Any,
                "ip_address": fingerprint.ipAddress as Any,
                "advertising_id": fingerprint.advertisingIdentifier as Any
            ]
        ]
        
        Task {
            do {
                let data = try await shared!.makeAPIRequest(
                    endpoint: "deferred_deeplink",
                    method: "POST",
                    body: body
                )
                
                let decoder = JSONDecoder()
                let response = try decoder.decode(DeferredDeepLinkResponse.self, from: data)
                
                DispatchQueue.main.async {
                    if let urlString = response.deepLink,
                       let url = URL(string: urlString) {
                        completion(url, response.attribution)
                    } else {
                        completion(nil, response.attribution)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(nil, nil)
                }
            }
        }
    }
    
    public static func handleUniversalLink(_ url: URL) {
        // Handle universal links
    }
    
    public static func handleCustomScheme(_ url: URL) {
        // Handle custom scheme deep links
    }
    
    public static func createDeepLink(
        path: String,
        customParameters: DLNCustomParameters? = nil
    ) -> URL? {
        let components = URLComponents {
            $0.scheme = "deeplinknow"
            $0.host = "app"
            $0.path = path
            
            if let params = customParameters?.dictionary {
                $0.queryItems = params.compactMap { key, value in
                    URLQueryItem(name: key, value: String(describing: value))
                }
            }
        }
        
        return components.url
    }
    
    public static func parseDeepLink(_ url: URL) -> (path: String, parameters: [String: Any])? {
        guard let shared = shared,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              shared.validDomains.contains(components.host ?? "") else {
            return nil
        }
        
        let path = components.path
        var parameters: [String: Any] = [:]
        
        // Parse query parameters
        components.queryItems?.forEach { item in
            if let value = item.value {
                parameters[item.name] = value
            }
        }
        
        return (path, parameters)
    }
}

// Helper extensions
private extension Date {
    func toISO8601String() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}

private extension URLComponents {
    init(_ configure: (inout URLComponents) -> Void) {
        self.init()
        configure(&self)
    }
} 