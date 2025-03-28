# DeepLinkNow iOS SDK

[![Version](https://img.shields.io/cocoapods/v/DeepLinkNow.svg?style=flat)](https://cocoapods.org/pods/DeepLinkNow)
[![License](https://img.shields.io/cocoapods/l/DeepLinkNow.svg?style=flat)](https://cocoapods.org/pods/DeepLinkNow)
[![Platform](https://img.shields.io/cocoapods/p/DeepLinkNow.svg?style=flat)](https://cocoapods.org/pods/DeepLinkNow)

DeepLinkNow (DLN) is a lightweight SDK for handling deferred deep linking in iOS applications.

## Requirements

- iOS 13.0+
- Swift 5.0+
- Xcode 13.0+

## Installation

Add this to your `Podfile`:

```ruby
pod 'DeepLinkNow'
```

Then run:

```bash
pod install
```

## Usage

### Initialize the SDK

```swift
// In your AppDelegate or initialization code
Task {
    // Basic initialization
    let config = DLNConfig(
        apiKey: "your-api-key",
        enableLogs: true,  // Optional: Enable debug logging
        baseUrl: nil,      // Optional: Custom API endpoint
        timeout: nil,      // Optional: Custom timeout
        retryAttempts: nil // Optional: Number of retry attempts
    )
    await DeepLinkNow.initialize(config: config)
}
```

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
}
```

### Find Deferred User

The SDK provides a powerful deferred deep linking system that can match users across installations:

```swift
Task {
    if let response = await DeepLinkNow.findDeferredUser() {
        if let deepLink = response.match.deeplink {
            // Access deep link properties
            print("Deep Link ID:", deepLink.id)
            print("Target URL:", deepLink.targetUrl)
            print("Campaign ID:", deepLink.campaignId ?? "None")
            print("Metadata:", deepLink.metadata)
            print("Matched At:", deepLink.matchedAt)
            print("Expires At:", deepLink.expiresAt)
        }

        // Access match details
        if let details = response.match.matchDetails {
            print("IP Match:", details.ipMatch.matched)
            print("Device Match:", details.deviceMatch.matched)
            print("Locale Match:", details.localeMatch.matched)
        }

        // Access match confidence and TTL
        print("Confidence Score:", response.match.confidenceScore)
        print("TTL Seconds:", response.match.ttlSeconds)

        // Access attribution data if available
        if let attribution = response.attribution {
            print("Campaign:", attribution.campaign ?? "None")
            print("Source:", attribution.source ?? "None")
            print("Medium:", attribution.medium ?? "None")
        }
    }
}
```

### Create Deep Links

```swift
// Create deep link with custom parameters
let customParams = DLNCustomParameters([
    "referrer": "social_share",
    "campaign": "summer_sale",
    "is_promo": true,
    "discount": 20
])

if let url = DeepLinkNow.createDeepLink(
    path: "/product/123",
    customParameters: customParams
) {
    // Use the generated deep link
    print("Generated URL:", url)
}
```

### Parse Deep Links

```swift
if let (path, parameters) = DeepLinkNow.parseDeepLink(url) {
    // Handle the deep link components
    print("Path:", path)
    print("Parameters:", parameters)
}
```

### Handle Universal Links

In your `AppDelegate`:

```swift
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            handleDeepLink(url)
            return true
        }
        return false
    }

    private func handleDeepLink(_ url: URL) {
        // For SwiftUI apps, use NotificationCenter to communicate with your views
        NotificationCenter.default.post(name: .init("DeepLinkReceived"), object: url)
    }
}
```

### Domain Validation

The SDK automatically validates deep links against:

- deeplinknow.com
- deeplink.now
- Your app's verified custom domains (configured in the dashboard)

These domains are automatically loaded during SDK initialization.

### Rate Limits and Account Status

The SDK includes built-in rate limiting and account status monitoring:

- Matches per second limit
- Matches per day limit
- Account status tracking (active/suspended/expired)
- Remaining credits monitoring

## Documentation

For detailed documentation, visit [docs.deeplinknow.com](https://docs.deeplinknow.com)

## Support

- 📧 Email: support@deeplinknow.com
- 💬 Discord: [Join our community](https://discord.gg/deeplinknow)

## License

DeepLinkNow is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
