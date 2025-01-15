public struct DLNConfig {
    let apiKey: String
    let apiBaseURL: String = "https://deeplinknow.com/api/v1"
    
    public init(apiKey: String) {
        self.apiKey = apiKey
    }
} 