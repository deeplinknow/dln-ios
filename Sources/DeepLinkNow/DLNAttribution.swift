public struct DLNAttribution: Codable {
    public let channel: String?
    public let campaign: String?
    public let medium: String?
    public let source: String?
    public let clickTimestamp: Date?
    public let installTimestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case channel, campaign, medium, source
        case clickTimestamp = "click_timestamp"
        case installTimestamp = "install_timestamp"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        channel = try container.decodeIfPresent(String.self, forKey: .channel)
        campaign = try container.decodeIfPresent(String.self, forKey: .campaign)
        medium = try container.decodeIfPresent(String.self, forKey: .medium)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        
        if let timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .clickTimestamp) {
            clickTimestamp = Date(timeIntervalSince1970: timestamp)
        } else {
            clickTimestamp = nil
        }
        
        let installTimestampValue = try container.decode(TimeInterval.self, forKey: .installTimestamp)
        installTimestamp = Date(timeIntervalSince1970: installTimestampValue)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(channel, forKey: .channel)
        try container.encodeIfPresent(campaign, forKey: .campaign)
        try container.encodeIfPresent(medium, forKey: .medium)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(clickTimestamp?.timeIntervalSince1970, forKey: .clickTimestamp)
        try container.encode(installTimestamp.timeIntervalSince1970, forKey: .installTimestamp)
    }
    
    public init(
        channel: String? = nil,
        campaign: String? = nil,
        medium: String? = nil,
        source: String? = nil,
        clickTimestamp: Date? = nil,
        installTimestamp: Date = Date()
    ) {
        self.channel = channel
        self.campaign = campaign
        self.medium = medium
        self.source = source
        self.clickTimestamp = clickTimestamp
        self.installTimestamp = installTimestamp
    }
    
    static func track(parameters: [String: Any]) {
        // Track install attribution
    }
} 