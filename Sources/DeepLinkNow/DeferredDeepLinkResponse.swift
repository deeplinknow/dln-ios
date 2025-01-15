struct DeferredDeepLinkResponse: Codable {
    let deepLink: String?
    let attribution: DLNAttribution?
    let customParameters: DLNCustomParameters?
} 