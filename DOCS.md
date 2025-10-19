# DeepLinkNow iOS SDK Documentation

## Overview

DeepLinkNow (DLN) is a lightweight, powerful deep linking and attribution SDK for iOS applications. It enables you to handle deep links, deferred deep links, and track user attribution seamlessly. This document covers all the essential features and how to implement them in your iOS application.

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Getting Started](#getting-started)
  - [Initializing the SDK](#initializing-the-sdk)
  - [Configuration Options](#configuration-options)
- [Deep Linking Features](#deep-linking-features)
  - [Deferred Deep Linking](#deferred-deep-linking)
  - [Finding Fingerprinted Users](#finding-fingerprinted-users)
  - [Checking Clipboard for Deep Links](#checking-clipboard-for-deep-links)
  - [Creating Deep Links](#creating-deep-links)
  - [Parsing Deep Links](#parsing-deep-links)
- [Integration Examples](#integration-examples)
  - [SwiftUI Implementation](#swiftui-implementation)
  - [UIKit Implementation](#uikit-implementation)
- [Advanced Features](#advanced-features)
  - [Domain Validation](#domain-validation)
  - [Rate Limits and Account Status](#rate-limits-and-account-status)
  - [Custom Parameters](#custom-parameters)
- [Support](#support)
- [License](#license)

## Requirements

- iOS 13.0+
- Swift 5.0+
- Xcode 13.0+

## Installation

### CocoaPods

Add this to your `Podfile`:

```ruby
pod 'DeepLinkNow', '~> 0.4'
```

Then run:

```bash
pod install
```

## Getting Started

### Initializing the SDK

Before using any features of the SDK, you must initialize it with your API key. The API key can be obtained from your DeepLinkNow dashboard.

```swift
// Using async/await (recommended)
Task {
    let config = DLNConfig(
        apiKey: "your-api-key-here",
        enableLogs: true  // Set to true during development, false in production
    )
    await DeepLinkNow.initialize(config: config)

    // Now the SDK is ready to use
}
```

### Configuration Options

The SDK can be initialized with several configuration options:

```swift
let config = DLNConfig(
    apiKey: "your-api-key-here",
    enableLogs: true,           // Enable debug logging (optional)
    baseUrl: "custom-url.com",  // Custom API endpoint (optional)
    timeout: 30.0,              // Custom timeout in seconds (optional)
    retryAttempts: 3            // Number of retry attempts (optional)
)
```

## Deep Linking Features

### Deferred Deep Linking

Deferred deep linking allows you to route users to specific content even if they didn't have your app installed when they clicked on a link. The SDK can match users across installations using device fingerprinting.

#### Finding Fingerprinted Users

The most common use case is to check for deferred deep links when a user first opens your app. This should be done after initializing the SDK:

```swift
Task {
    // First, initialize the SDK
    let config = DLNConfig(apiKey: "your-api-key-here")
    await DeepLinkNow.initialize(config: config)

    // Then check for deferred users
    if let matchResponse = await DeepLinkNow.findDeferredUser() {
        // The SDK returns up to 5 potential matches with confidence scores
        for match in matchResponse.matches {
            // Check the confidence score to determine if the match is reliable
            let confidenceScore = match.confidenceScore

            // You can examine what parameters matched
            if let deviceMatch = match.matchDetails.deviceMatch {
                let deviceMatchScore = deviceMatch.score
                let platformMatched = deviceMatch.components.platform
                let osVersionMatched = deviceMatch.components.osVersion
                let deviceModelMatched = deviceMatch.components.deviceModel
            }

            // Check IP address match
            let ipMatch = match.matchDetails.ipMatch.matched
            let ipMatchScore = match.matchDetails.ipMatch.score

            // Check locale match (language, timezone)
            let localeMatchScore = match.matchDetails.localeMatch.score

            // Access the deep link if available
            if let deeplink = match.deeplink {
                // Get the target URL to route the user
                let targetUrl = deeplink.targetUrl

                // Access custom metadata
                let metadata = deeplink.metadata

                // Access campaign information if available
                let campaignId = deeplink.campaignId

                // Check expiration
                let expiresAt = deeplink.expiresAt

                // Use this information to route the user to the right place in your app
                navigateToContent(targetUrl, metadata)
            }
        }
    } else {
        // No deferred deep link found
        // Proceed with normal app flow
    }
}
```

### Checking Clipboard for Deep Links

If you don't find a fingerprinted user, you can optionally check the clipboard for a deep link. The SDK provides helper methods for this:

```swift
// First, check if the clipboard contains a potential deep link token
if DeepLinkNow.hasDeepLinkToken() {
    // The clipboard contains a potential deep link
    // Request permission from the user to access clipboard

    // After obtaining permission, check the clipboard
    if let clipboardUrl = DeepLinkNow.checkClipboard() {
        // Found a valid deep link in clipboard
        // Parse and handle it
        if let (path, parameters) = DeepLinkNow.parseDeepLink(URL(string: clipboardUrl)!) {
            // Use path and parameters to navigate
            navigateBasedOnPath(path, parameters)
        }
    }
}
```

**Note:** On iOS, you need to request permission to access the clipboard. Add the following to your `Info.plist`:

```xml
<key>NSPasteboardUsageDescription</key>
<string>We need access to the clipboard to check for deep links</string>
```

### Creating Deep Links

You can create deep links programmatically to share with users:

```swift
// Create custom parameters
let customParams = DLNCustomParameters([
    "referrer": "social_share",
    "campaign": "summer_sale",
    "is_promo": "true",
    "discount": "20"
])

// Create the deep link
if let url = DeepLinkNow.createDeepLink(
    path: "/product/123",
    customParameters: customParams
) {
    // Use the generated deep link
    shareDeepLink(url)
}
```

### Parsing Deep Links

When receiving deep links (via Universal Links, custom URL schemes, or clipboard), parse them with:

```swift
if let parsed = DeepLinkNow.parseDeepLink(url) {
    let path = parsed.path
    let parameters = parsed.parameters

    // Route the user based on path and parameters
    switch path {
    case "/product":
        if let productId = parameters["id"] as? String {
            navigateToProduct(productId)
        }
    case "/category":
        if let categoryId = parameters["id"] as? String {
            navigateToCategory(categoryId)
        }
    default:
        navigateToHome()
    }
}
```

## Integration Examples

### SwiftUI Implementation

Here's how to implement deep linking in a SwiftUI app:

```swift
struct ContentView: View {
    @State private var isInitialized = false
    @State private var lastReceivedDeepLink: URL? = nil

    var body: some View {
        VStack {
            if let deepLink = lastReceivedDeepLink {
                Text("Last Received Deep Link:")
                    .font(.headline)
                Text(deepLink.absoluteString)
                    .foregroundColor(.blue)
            }

            Button(action: initDln) {
                Text(!isInitialized ? "Initialize SDK" : "Initialized!")
            }
        }
        .onAppear {
            setupDeepLinkObserver()
            checkForDeferredDeepLinks()
        }
    }

    private func setupDeepLinkObserver() {
        NotificationCenter.default.addObserver(
            forName: .init("DeepLinkReceived"),
            object: nil,
            queue: .main
        ) { notification in
            if let url = notification.object as? URL {
                self.lastReceivedDeepLink = url
                handleDeepLink(url)
            }
        }
    }

    private func initDln() {
        Task {
            let config = DLNConfig(apiKey: "your-api-key", enableLogs: true)
            await DeepLinkNow.initialize(config: config)
            isInitialized = true
        }
    }

    private func checkForDeferredDeepLinks() {
        Task {
            if let matchResponse = await DeepLinkNow.findDeferredUser() {
                // Process matches based on confidence scores
                // For this example, just take the highest confidence match
                if let bestMatch = matchResponse.matches.max(by: { $0.confidenceScore < $1.confidenceScore }),
                   let deeplink = bestMatch.deeplink {

                    // Check if confidence score meets your threshold
                    if bestMatch.confidenceScore >= 75 { // High confidence
                        if let url = URL(string: deeplink.targetUrl) {
                            self.lastReceivedDeepLink = url
                            handleDeepLink(url)
                        }
                    }
                }
            } else {
                // Check clipboard as fallback
                if DeepLinkNow.hasDeepLinkToken() {
                    if let clipboardUrl = DeepLinkNow.checkClipboard(),
                       let url = URL(string: clipboardUrl) {
                        self.lastReceivedDeepLink = url
                        handleDeepLink(url)
                    }
                }
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        if let (path, parameters) = DeepLinkNow.parseDeepLink(url) {
            // Route based on path and parameters
            print("Routing to path: \(path) with parameters: \(parameters)")

            // Implement your navigation logic here
        }
    }
}
```

### UIKit Implementation

For UIKit apps, implement in your AppDelegate:

```swift
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Initialize the SDK
        Task {
            let config = DLNConfig(apiKey: "your-api-key")
            await DeepLinkNow.initialize(config: config)

            // Check for deferred deep links
            checkForDeferredDeepLinks()
        }

        return true
    }

    // Handle Universal Links
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            handleDeepLink(url)
            return true
        }
        return false
    }

    // Handle custom URL schemes
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        handleDeepLink(url)
        return true
    }

    private func checkForDeferredDeepLinks() {
        Task {
            if let matchResponse = await DeepLinkNow.findDeferredUser() {
                // Process matches based on confidence scores
                for match in matchResponse.matches {
                    if match.confidenceScore >= 75, // High confidence threshold
                       let deeplink = match.deeplink,
                       let url = URL(string: deeplink.targetUrl) {
                        DispatchQueue.main.async {
                            self.handleDeepLink(url)
                        }
                        break
                    }
                }
            } else {
                // Check clipboard as fallback
                if DeepLinkNow.hasDeepLinkToken() {
                    if let clipboardUrl = DeepLinkNow.checkClipboard(),
                       let url = URL(string: clipboardUrl) {
                        DispatchQueue.main.async {
                            self.handleDeepLink(url)
                        }
                    }
                }
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        if let parsed = DeepLinkNow.parseDeepLink(url) {
            // Implement your navigation logic here
            // For example:
            let navigationController = window?.rootViewController as? UINavigationController

            switch parsed.path {
            case "/product":
                if let productId = parsed.parameters["id"] as? String {
                    let productVC = ProductViewController(productId: productId)
                    navigationController?.pushViewController(productVC, animated: true)
                }
            case "/category":
                if let categoryId = parsed.parameters["id"] as? String {
                    let categoryVC = CategoryViewController(categoryId: categoryId)
                    navigationController?.pushViewController(categoryVC, animated: true)
                }
            default:
                // Default handling
                break
            }
        }
    }
}
```

## Advanced Features

### Domain Validation

The SDK automatically validates deep links against allowed domains:

- deeplinknow.com
- deeplink.now
- Your app's verified custom domains (configured in your dashboard)

These domains are automatically loaded during SDK initialization. You can check if a domain is valid with:

```swift
let isValid = DeepLinkNow.isValidDomain("yourdomain.com")
```

### Rate Limits and Account Status

The SDK includes built-in monitoring for:

- Matches per second limit
- Matches per day limit
- Account status tracking (active/suspended/expired)
- Remaining credits monitoring

These limits are returned in the initialization response and can be accessed for advanced implementations.

### Custom Parameters

The SDK supports rich custom parameters for deep links:

```swift
// Creating custom parameters with different value types
var customParams = DLNCustomParameters([
    "referrer": "social_share",
    "campaign": "summer_sale",
    "is_promo": true,      // Boolean values
    "discount": 20,        // Numeric values
    "source_id": "fb_123"  // String values
])

// Create deep link with parameters
let deepLink = DeepLinkNow.createDeepLink(
    path: "/product/123",
    customParameters: customParams
)
```

When parsing deep links, you can access these parameters in a type-safe way:

```swift
if let parsed = DeepLinkNow.parseDeepLink(url) {
    let parameters = parsed.parameters

    // String values
    let referrer = parameters["referrer"] as? String

    // Boolean values (converted to strings in URL)
    let isPromoString = parameters["is_promo"] as? String
    let isPromo = isPromoString == "true"

    // Numeric values (converted to strings in URL)
    let discountString = parameters["discount"] as? String
    let discount = Int(discountString ?? "0") ?? 0
}
```

## Support

- 📧 Email: support@deeplinknow.com
- 💬 Discord: Join our community
- 📚 Documentation: [docs.deeplinknow.com](https://docs.deeplinknow.com)

## License

DeepLinkNow is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
