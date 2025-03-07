import UIKit
import Foundation
import CoreTelephony
import AdSupport

public final class DeepLinkNow {
    private static var shared: DeepLinkNow?
    private let config: DLNConfig
    private let installTime: String = Date().toISO8601String()
    private var initResponse: InitResponse?
    private var validDomains: Set<String> = ["deeplinknow.com", "deeplink.now"]
    
    private init(config: DLNConfig) {
        self.config = config
    }
    
    private func log(_ message: String, _ args: Any...) {
        if config.enableLogs {
            print("[DeepLinkNow]", message, args)
        }
    }
    
    private func warn(_ message: String) {
        print("[DeepLinkNow] Warning:", message)
    }
    
    public static func initialize(apiKey: String, config: [String: Any] = [:]) async {
        let enableLogs = config["enableLogs"] as? Bool ?? false
        let customDomain = config["customDomain"] as? String
        let instance = DeepLinkNow(config: DLNConfig(
            apiKey: apiKey,
            enableLogs: enableLogs,
            customDomain: customDomain
        ))
        shared = instance
        
        // Make initialization request
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
            instance.validDomains.formUnion(
                response.app.customDomains
                    .compactMap { $0.domain }
                    .filter { $0.verified == true }
            )
            
            instance.log("Initialization successful", response)
        } catch {
            instance.warn("Initialization failed: \(error)")
        }
    }
    
    public static func isValidDomain(_ domain: String) -> Bool {
        guard let shared = shared else { return false }
        return shared.validDomains.contains(domain)
    }
    
    private func getFingerprint() -> [String: Any] {
        let device = UIDevice.current
        return [
            "user_agent": "DeepLinkNow-iOS/\(device.systemVersion)",
            "platform": "ios",
            "os_version": device.systemVersion,
            "device_model": device.model,
            "language": Locale.current.languageCode ?? "en",
            "timezone": TimeZone.current.identifier,
            "installed_at": installTime,
            "last_opened_at": Date().toISO8601String(),
            "device_id": nil,
            "advertising_id": nil,
            "vendor_id": nil,
            "hardware_fingerprint": nil
        ]
    }
    
    public static func findDeferredUser() async -> MatchResponse? {
        guard let shared = shared else {
            print("[DeepLinkNow] SDK not initialized. Call initialize() first")
            return nil
        }
        
        shared.log("Finding deferred user...")
        
        let matchRequest: [String: Any] = [
            "fingerprint": shared.getFingerprint()
        ]
        
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
        let baseURL = config.customDomain ?? "deeplinknow.com"
        let urlComponents = URLComponents {
            $0.scheme = "https"
            $0.host = baseURL
            $0.path = "/api/v1/sdk/\(endpoint)"
        }
        
        guard let url = urlComponents.url else {
            throw DLNError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.httpMethod = method
        
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
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
                let data = try await DeepLinkNow.makeAPIRequest(
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