public struct InitResponse: Codable {
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
    }
    
    public struct CustomDomain: Codable {
        public let domain: String?
        public let verified: Bool?
    }
    
    public struct RateLimits: Codable {
        public let matchesPerSecond: Int
        public let matchesPerDay: Int
        
        private enum CodingKeys: String, CodingKey {
            case matchesPerSecond = "matches_per_second"
            case matchesPerDay = "matches_per_day"
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
    }
    
    public let app: App
    public let account: Account
} 