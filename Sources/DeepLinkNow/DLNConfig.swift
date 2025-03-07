public struct DLNConfig {
    let apiKey: String
    let enableLogs: Bool
    let customDomain: String?
    
    public init(apiKey: String, enableLogs: Bool = false, customDomain: String? = nil) {
        self.apiKey = apiKey
        self.enableLogs = enableLogs
        self.customDomain = customDomain
    }
} 