import Foundation

/// SDK-83: the last successful `/init` result, kept on the device so a cold start within
/// 24 hours (and the same UTC month) needs no network call. The server counts MAU on
/// `/init`, so the same-month rule keeps every device counted once a month (BILL-19).
/// Stored in the SDK's `UserDefaults`; the public API key is not a secret (KEY-16).
struct InitCache: Codable, Equatable {
    static let defaultsKey = "com.deeplinknow.initCache"
    static let maxAge: TimeInterval = 24 * 60 * 60
    static let formatVersion = 1

    var formatVersion: Int = InitCache.formatVersion
    let apiKey: String
    let baseUrl: String
    let savedAt: Date
    let appId: String
    let alias: String
    let name: String?
    let linkDomains: [String]
    let primaryDomain: String
    let accountStatus: String
    let creditsRemaining: Int?

    init(apiKey: String, baseUrl: String, savedAt: Date, appInfo: DLNAppInfo) {
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        self.savedAt = savedAt
        self.appId = appInfo.appId
        self.alias = appInfo.alias
        self.name = appInfo.name
        self.linkDomains = appInfo.linkDomains
        self.primaryDomain = appInfo.primaryDomain
        self.accountStatus = appInfo.accountStatus
        self.creditsRemaining = appInfo.creditsRemaining
    }

    var appInfo: DLNAppInfo {
        DLNAppInfo(
            appId: appId,
            alias: alias,
            name: name,
            linkDomains: linkDomains,
            primaryDomain: primaryDomain,
            accountStatus: accountStatus,
            creditsRemaining: creditsRemaining
        )
    }

    /// Usable for this key and base URL at `now`: under 24 hours old, not from the future,
    /// and saved in the same UTC month.
    func isUsable(apiKey: String, baseUrl: String, now: Date) -> Bool {
        guard formatVersion == InitCache.formatVersion,
              self.apiKey == apiKey, self.baseUrl == baseUrl,
              !linkDomains.isEmpty else { return false }
        let age = now.timeIntervalSince(savedAt)
        guard age >= 0, age < InitCache.maxAge else { return false }
        return InitCache.utcMonth(savedAt) == InitCache.utcMonth(now)
    }

    static func utcMonth(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    static func load(from defaults: UserDefaults) -> InitCache? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(InitCache.self, from: data)
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: InitCache.defaultsKey)
    }

    static func clear(in defaults: UserDefaults) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
