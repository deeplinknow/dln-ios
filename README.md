# DeepLinkNow iOS SDK

[![Version](https://img.shields.io/cocoapods/v/DeepLinkNow.svg?style=flat)](https://cocoapods.org/pods/DeepLinkNow)
[![License](https://img.shields.io/cocoapods/l/DeepLinkNow.svg?style=flat)](https://cocoapods.org/pods/DeepLinkNow)
[![Platform](https://img.shields.io/cocoapods/p/DeepLinkNow.svg?style=flat)](https://cocoapods.org/pods/DeepLinkNow)

DeepLinkNow (DLN) is a lightweight, powerful deep linking and attribution SDK for iOS applications. Handle deep links, deferred deep links, and track user attribution with ease.

## Features

- 🔗 Deep link handling
- 📋 Clipboard deep link detection
- 🔒 Secure API communication
- 🚀 Easy integration
- ⚡️ Lightweight implementation
- 🎯 Custom parameters support

## Requirements

- iOS 13.0+
- Swift 5.0+
- Xcode 13.0+

## Installation

### CocoaPods

Add this to your `Podfile`:

```swift
pod 'DeepLinkNow'
```

Then run:

```bash
pod install
```

## Usage

### Initialize the SDK

```swift
import DeepLinkNow

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    DeepLinkNow.initialize(apiKey: "your-api-key-here")
    return true
}
```

### Custom Parameters

The SDK supports passing and receiving custom parameters through deep links. This enables rich contextual data sharing and advanced routing capabilities.

#### Creating Deep Links with Custom Parameters

```swift
// Create custom parameters
var customParams = DLNCustomParameters()
customParams["referrer"] = "social_share"
customParams["is_promo"] = true
customParams["discount"] = 20

// Create deep link with parameters
let deepLink = DeepLinkNow.createDeepLink(
    path: "/product/123",
    customParameters: customParams
)
// Result: deeplinknow://app/product/123?referrer=social_share&is_promo=true&discount=20
```

#### Handling Deep Links with Custom Parameters

```swift
let router = DLNRouter()

router.register(pattern: "product/:id") { url, params in
    if let parsed = DeepLinkNow.parseDeepLink(url) {
        // Access route parameters
        let productId = params["id"]

        // Access custom parameters
        let referrer = parsed.parameters.string("referrer")
        let isPromo = parsed.parameters.bool("is_promo") ?? false
        let discount = parsed.parameters.int("discount")

        // Handle the deep link
        navigateToProduct(
            id: productId,
            referrer: referrer,
            isPromo: isPromo,
            discount: discount
        )
    }
}
```

#### Type-Safe Parameter Access

DLNCustomParameters provides type-safe access to parameters:

```swift
let parameters = parsed.parameters

// String values
let referrer: String? = parameters.string("referrer")

// Integer values
let discount: Int? = parameters.int("discount")

// Boolean values
let isPromo: Bool? = parameters.bool("is_promo")

// Dictionary values
let metadata: [String: Any]? = parameters.dictionary("metadata")
```

### Required Permissions

Add the following to your `Info.plist`:

```xml
<key>NSPasteboardUsageDescription</key>
<string>We need access to the clipboard to check for deep links</string>
```

## Documentation

For detailed documentation, visit [docs.deeplinknow.com](https://docs.deeplinknow.com)

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

## License

DeepLinkNow is available under the MIT license. See the [LICENSE](LICENSE) file for more info.

## Support

- 📧 Email: support@deeplinknow.com
- 💬 Discord: [Join our community](https://discord.gg/deeplinknow)
- 📚 Documentation: [docs.deeplinknow.com](https://docs.deeplinknow.com)
