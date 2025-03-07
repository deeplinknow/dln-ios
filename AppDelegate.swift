func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // Initialize SDK
    Task {
        await DeepLinkNow.initialize(apiKey: "your-api-key-here")
        
        // Check for deferred deep links
        if let match = await DeepLinkNow.findDeferredUser() {
            // Handle the match
            if let deepLink = match.deepLink {
                // Open the deep link
            }
        }
    }
    
    return true
}

// Creating a deep link with custom parameters
func createProductDeepLink(productId: String) -> URL? {
    var customParams = DLNCustomParameters()
    customParams["referrer"] = "social_share"
    customParams["is_promo"] = true
    customParams["discount"] = 20
    
    return DeepLinkNow.createDeepLink(
        path: "/product/\(productId)",
        customParameters: customParams
    )
} 