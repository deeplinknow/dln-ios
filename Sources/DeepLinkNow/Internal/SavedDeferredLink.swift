import Foundation

/// IOS-40: a deferred link that is held (`hold: true`) or has no handler yet, kept in the
/// SDK's `UserDefaults` so it survives the app being killed before it is delivered (the
/// first-launch flag is already set by then, so the chain will not find it again). Cleared
/// when the link is handed to the handler, by `clearPendingLink()` and by
/// `resetDeferredDeepLink()`; ignored and deleted after 24 hours.
struct SavedDeferredLink: Codable {
    static let defaultsKey = "com.deeplinknow.pendingDeferredLink"
    static let maxAge: TimeInterval = 24 * 60 * 60
    static let formatVersion = 1

    var formatVersion: Int = SavedDeferredLink.formatVersion
    let savedAt: Date
    let path: String
    let queryParams: [String: DLNQueryValue]
    let fullPath: String
    let url: String
    let source: DLNLinkSource
    let confidenceScore: Double
    let matchQuality: ConfidenceLevel
    let deeplinkId: String?
    let targetUrl: String?
    let campaignId: String?
    let metadata: [String: AnyCodable]?
    let matchedAt: String?
    let expiresAt: String?
    let matchDetails: MatchDetails?

    init(_ link: DLNLink, savedAt: Date) {
        self.savedAt = savedAt
        self.path = link.path
        self.queryParams = link.queryParams
        self.fullPath = link.fullPath
        self.url = link.url
        self.source = link.source
        self.confidenceScore = link.confidenceScore
        self.matchQuality = link.matchQuality
        self.deeplinkId = link.deeplinkId
        self.targetUrl = link.targetUrl
        self.campaignId = link.campaignId
        self.metadata = link.metadata
        self.matchedAt = link.matchedAt
        self.expiresAt = link.expiresAt
        self.matchDetails = link.matchDetails
    }

    var link: DLNLink {
        DLNLink(type: .deferred, path: path, queryParams: queryParams, fullPath: fullPath, url: url,
                source: source, confidenceScore: confidenceScore, matchQuality: matchQuality,
                deeplinkId: deeplinkId, targetUrl: targetUrl, campaignId: campaignId,
                metadata: metadata, matchedAt: matchedAt, expiresAt: expiresAt,
                matchDetails: matchDetails)
    }

    /// Under 24 hours old and not from the future.
    func isUsable(now: Date) -> Bool {
        guard formatVersion == SavedDeferredLink.formatVersion else { return false }
        let age = now.timeIntervalSince(savedAt)
        return age >= 0 && age < SavedDeferredLink.maxAge
    }

    static func load(from defaults: UserDefaults) -> SavedDeferredLink? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(SavedDeferredLink.self, from: data)
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: SavedDeferredLink.defaultsKey)
    }

    static func clear(in defaults: UserDefaults) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
