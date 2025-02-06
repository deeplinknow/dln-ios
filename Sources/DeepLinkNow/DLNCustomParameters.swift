public struct DLNCustomParameters: Codable {
    private var parameters: [String: CodableValue]
    
    public init(_ parameters: [String: Any] = [:]) {
        self.parameters = parameters.mapValues(CodableValue.init)
    }
    
    public subscript(key: String) -> Any? {
        get { parameters[key]?.value }
        set { parameters[key] = newValue.map(CodableValue.init) }
    }
    
    // Helper methods for type-safe access
    public func string(_ key: String) -> String? {
        parameters[key]?.value as? String
    }
    
    public func int(_ key: String) -> Int? {
        parameters[key]?.value as? Int
    }
    
    public func bool(_ key: String) -> Bool? {
        parameters[key]?.value as? Bool
    }
    
    public func dictionary(_ key: String) -> [String: Any]? {
        parameters[key]?.value as? [String: Any]
    }
    
    var dictionary: [String: Any] {
        parameters.mapValues { $0.value }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        parameters = try container.decode([String: CodableValue].self, forKey: .parameters)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(parameters, forKey: .parameters)
    }
    
    private enum CodingKeys: String, CodingKey {
        case parameters
    }
}

private struct CodableValue: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    private enum ValueType: String, Codable {
        case string, number, bool, null
    }
    
    private enum CodingKeys: String, CodingKey {
        case type, value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch value {
        case let string as String:
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(string, forKey: .value)
        case let number as NSNumber:
            try container.encode(ValueType.number, forKey: .type)
            try container.encode(number.stringValue, forKey: .value)
        case let bool as Bool:
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(bool, forKey: .value)
        case is NSNull:
            try container.encode(ValueType.null, forKey: .type)
        default:
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(String(describing: value), forKey: .value)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)
        
        switch type {
        case .string:
            value = try container.decode(String.self, forKey: .value)
        case .number:
            let stringValue = try container.decode(String.self, forKey: .value)
            if let intValue = Int(stringValue) {
                value = intValue
            } else if let doubleValue = Double(stringValue) {
                value = doubleValue
            } else {
                value = stringValue
            }
        case .bool:
            value = try container.decode(Bool.self, forKey: .value)
        case .null:
            value = NSNull()
        }
    }
} 