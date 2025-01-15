import UIKit
import Foundation

public final class DeepLinkNow {
    private let config: DLNConfig
    private static var shared: DeepLinkNow?
    
    private init(config: DLNConfig) {
        self.config = config
    }
    
    public static func initialize(apiKey: String) {
        shared = DeepLinkNow(config: DLNConfig(apiKey: apiKey))
    }
    
    public static func checkClipboard() -> String? {
        guard let shared = shared else {
            print("DeepLinkNow SDK not initialized. Call initialize() first")
            return nil
        }
        
        return UIPasteboard.general.string
    }
    
    private func makeAPIRequest(endpoint: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard var urlComponents = URLComponents(string: "\(config.apiBaseURL)/\(endpoint)") else {
            throw DLNError.invalidURL
        }
        
        var request = URLRequest(url: urlComponents.url!)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
    
    public typealias DeferredDeepLinkHandler = (URL?, DLNAttribution?) -> Void
    
    public static func checkDeferredDeepLink(completion: @escaping DeferredDeepLinkHandler) {
        guard let shared = shared else {
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
                let data = try await shared.makeAPIRequest(
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
        guard let shared = shared else { return nil }
        
        var components = URLComponents()
        components.scheme = "deeplinknow"
        components.host = "app"
        components.path = path
        
        if let params = customParameters?.dictionary {
            components.queryItems = params.map { key, value in
                URLQueryItem(name: key, string: String(describing: value))
            }
        }
        
        return components.url
    }
    
    public static func parseDeepLink(_ url: URL) -> (path: String, parameters: DLNCustomParameters)? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return nil
        }
        
        let path = components.path
        var parameters = DLNCustomParameters()
        
        // Parse query parameters
        components.queryItems?.forEach { item in
            if let value = item.value {
                parameters[item.name] = value
            }
        }
        
        return (path, parameters)
    }
}

struct DeferredDeepLinkResponse: Codable {
    let deepLink: String?
    let attribution: DLNAttribution?
} 