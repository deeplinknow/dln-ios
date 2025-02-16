public struct DeferredDeepLinkResponse: Codable, Sendable {
    public let deepLink: String?
    public let attribution: DLNAttribution?
    public let customParameters: DLNCustomParameters?
    
    private enum CodingKeys: String, CodingKey {
        case deepLink = "deep_link"
        case attribution
        case customParameters = "custom_parameters"
    }
    
    public init(
        deepLink: String? = nil,
        attribution: DLNAttribution? = nil,
        customParameters: DLNCustomParameters? = nil
    ) {
        self.deepLink = deepLink
        self.attribution = attribution
        self.customParameters = customParameters
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deepLink = try container.decodeIfPresent(String.self, forKey: .deepLink)
        attribution = try container.decodeIfPresent(DLNAttribution.self, forKey: .attribution)
        customParameters = try container.decodeIfPresent(DLNCustomParameters.self, forKey: .customParameters)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(deepLink, forKey: .deepLink)
        try container.encodeIfPresent(attribution, forKey: .attribution)
        try container.encodeIfPresent(customParameters, forKey: .customParameters)
    }
} 