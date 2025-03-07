public struct MatchResponse: Codable {
    public let deepLink: String?
    public let attribution: Attribution?
    
    private enum CodingKeys: String, CodingKey {
        case deepLink = "deep_link"
        case attribution
    }
}

public struct Attribution: Codable {
    public let channel: String?
    public let campaign: String?
    public let medium: String?
    public let source: String?
} 