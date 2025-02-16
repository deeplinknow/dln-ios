public struct DLNConfig {
    let apiKey: String
    let apiBaseURL: String = "https://deeplinknow.com/api/v1"
    let enableLogs: Bool
    
    public init(apiKey: String, enableLogs: Bool = false) {
        self.apiKey = apiKey
        self.enableLogs = enableLogs
    }
} 