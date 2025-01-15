public struct DLNCustomParameters: Codable {
    private var parameters: [String: Any]
    
    public init(_ parameters: [String: Any] = [:]) {
        self.parameters = parameters
    }
    
    public subscript(key: String) -> Any? {
        get { parameters[key] }
        set { parameters[key] = newValue }
    }
    
    // Helper methods for type-safe access
    public func string(_ key: String) -> String? {
        parameters[key] as? String
    }
    
    public func int(_ key: String) -> Int? {
        parameters[key] as? Int
    }
    
    public func bool(_ key: String) -> Bool? {
        parameters[key] as? Bool
    }
    
    public func dictionary(_ key: String) -> [String: Any]? {
        parameters[key] as? [String: Any]
    }
} 