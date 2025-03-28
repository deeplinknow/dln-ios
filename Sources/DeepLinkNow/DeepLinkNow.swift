import UIKit
import Foundation
import CoreTelephony
import AdSupport

public final class DeepLinkNow {
    private static var shared: DeepLinkNow?
    private let config: DLNConfig
    private let urlSession: URLSessionProtocol
    private let installTime: String
    private var initResponse: InitResponse?
    private var validDomains: Set<String> = ["deeplinknow.com", "deeplink.now"]
    
    private init(config: DLNConfig, urlSession: URLSessionProtocol = URLSession.shared) {
        self.config = config
        self.urlSession = urlSession
        self.installTime = ISO8601DateFormatter().string(from: Date())
    }
    
    private func log(_ message: String, _ args: Any...) {
        if config.enableLogs {
            print("[DeepLinkNow]", message, args)
        }
    }
    
    private func warn(_ message: String) {
        print("[DeepLinkNow] Warning:", message)
    }
    
    public static func initialize(config: DLNConfig, urlSession: URLSessionProtocol = URLSession.shared) async {
        let instance = DeepLinkNow(config: config, urlSession: urlSession)
        shared = instance
        
        instance.log("Initializing with config:", config)
        
        do {
            let initRequest = ["api_key": config.apiKey]
            let data = try await instance.makeAPIRequest(
                endpoint: "init",
                method: "POST",
                body: initRequest
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
        let screen = UIScreen.main
        let dateFormatter = ISO8601DateFormatter()
        
        let currentTime = dateFormatter.string(from: Date())
        
        // Generate user agent string that matches web format
        let userAgent = "Mozilla/5.0 (\(device.model); CPU iOS \(device.systemVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(device.systemVersion) Mobile/15E148 Safari/604.1"
        
        // Determine device model based on device type, matching web implementation
        let deviceModel: String
        switch device.userInterfaceIdiom {
        case .pad:
            deviceModel = "iPad"
        case .phone:
            deviceModel = "iPhone"
        default:
            deviceModel = "iPhone" // Default to iPhone for other cases
        }
        
        let metadata = FingerprintMetadata(
            screenWidth: Int(screen.bounds.width * screen.scale),
            screenHeight: Int(screen.bounds.height * screen.scale),
            pixelRatio: round(Double(screen.scale) * 100) / 100, // Round to 2 decimal places
            colorDepth: 32, // Standard for iOS
            isTablet: device.userInterfaceIdiom == .pad,
            connectionType: nil,
            cpuCores: ProcessInfo.processInfo.processorCount,
            deviceMemory: nil,
            source: "mobile"
        )
        
        return Fingerprint(
            ipAddress: "", // Will be set by server
            userAgent: userAgent,
            platform: "ios",
            osVersion: device.systemVersion,
            deviceModel: deviceModel,
            language: Locale.current.languageCode ?? "en",
            timezone: TimeZone.current.identifier,
            installedAt: installTime,
            lastOpenedAt: currentTime,
            deviceId: device.identifierForVendor?.uuidString,
            advertisingId: ASIdentifierManager.shared().isAdvertisingTrackingEnabled ? 
                ASIdentifierManager.shared().advertisingIdentifier.uuidString : nil,
            vendorId: device.identifierForVendor?.uuidString,
            hardwareFingerprint: nil,
            metadata: metadata
        )
    }
    
    public static func findDeferredUser() async -> MatchResponse? {
        guard let shared = shared else {
            print("[DeepLinkNow] SDK not initialized. Call initialize() first")
            return nil
        }
        
        shared.log("Finding deferred user...")
        
        let fingerprint = shared.getFingerprint()
        
        // Break down the metadata dictionary creation
        var metadata: [String: Any] = [:]
        if let fingerprintMetadata = fingerprint.metadata {
            metadata["screen_width"] = fingerprintMetadata.screenWidth
            metadata["screen_height"] = fingerprintMetadata.screenHeight
            if let pixelRatio = fingerprintMetadata.pixelRatio {
                // Ensure the number is properly formatted for JSON
                let roundedRatio = NSNumber(value: round(pixelRatio * 100) / 100)
                metadata["pixel_ratio"] = roundedRatio
            }
            metadata["color_depth"] = fingerprintMetadata.colorDepth
            metadata["is_tablet"] = fingerprintMetadata.isTablet
            metadata["connection_type"] = fingerprintMetadata.connectionType
            metadata["cpu_cores"] = fingerprintMetadata.cpuCores
            metadata["device_memory"] = fingerprintMetadata.deviceMemory
            metadata["source"] = fingerprintMetadata.source
        }
        
        // Create the main fingerprint dictionary
        var fingerprintDict: [String: Any] = [:]
        fingerprintDict["platform"] = fingerprint.platform
        fingerprintDict["os_version"] = fingerprint.osVersion
        fingerprintDict["device_model"] = fingerprint.deviceModel
        fingerprintDict["language"] = fingerprint.language
        fingerprintDict["timezone"] = fingerprint.timezone
        fingerprintDict["installed_at"] = fingerprint.installedAt
        fingerprintDict["last_opened_at"] = fingerprint.lastOpenedAt
        fingerprintDict["device_id"] = fingerprint.deviceId ?? ""
        fingerprintDict["advertising_id"] = fingerprint.advertisingId ?? ""
        fingerprintDict["vendor_id"] = fingerprint.vendorId ?? ""
        fingerprintDict["hardware_fingerprint"] = fingerprint.hardwareFingerprint ?? ""
        fingerprintDict["user_agent"] = fingerprint.userAgent
        fingerprintDict["metadata"] = metadata
        
        let matchRequest = ["fingerprint": fingerprintDict]
        
        shared.log("Sending match request:", matchRequest)
        
        do {
            let data = try await shared.makeAPIRequest(
                endpoint: "match",
                method: "POST",
                body: matchRequest
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
        let baseUrl = config.baseUrl ?? "https://deeplinknow.com"
        let url = URL(string: "\(baseUrl)/api/v1/sdk/\(endpoint)")!
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.httpMethod = method
        
        if let timeout = config.timeout {
            request.timeoutInterval = timeout
        }
        
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            log("API request failed: Invalid response type")
            throw DLNError.serverError("Invalid response type", nil, nil)
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            log("API request failed: \(httpResponse.statusCode)")
            if let errorString = String(data: data, encoding: .utf8) {
                log("Error response: \(errorString)")
                
                // Try to decode error response
                if let errorResponse = try? JSONDecoder().decode([String: String].self, from: data) {
                    throw DLNError.serverError(
                        errorResponse["error"] ?? "Unknown error",
                        errorResponse["status"],
                        errorResponse["details"]
                    )
                }
            }
            
            // Map status codes to specific errors
            switch httpResponse.statusCode {
            case 400: throw DLNError.badRequest
            case 401: throw DLNError.unauthorized
            case 403: throw DLNError.forbidden
            case 404: throw DLNError.notFound
            case 429: throw DLNError.tooManyRequests
            case 500: throw DLNError.internalServerError
            default: throw DLNError.serverError("Unknown error", String(httpResponse.statusCode), nil)
            }
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
        
        Task { @Sendable in
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