func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // Initialize SDK
    DeepLinkNow.initialize(apiKey: "your-api-key-here")
    
    // Set up deep link routing with custom parameters
    let router = DLNRouter()
    
    // Register a route that handles custom parameters
    router.register(pattern: "product/:id") { url, params in
        if let parsed = DeepLinkNow.parseDeepLink(url) {
            // Access custom parameters
            let productId = params["id"]
            let referrer = parsed.parameters.string("referrer")
            let isPromo = parsed.parameters.bool("is_promo") ?? false
            let discount = parsed.parameters.int("discount")
            
            // Navigate to product page with custom parameters
            navigateToProduct(
                id: productId,
                referrer: referrer,
                isPromo: isPromo,
                discount: discount
            )
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