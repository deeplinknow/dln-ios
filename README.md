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
    await DeepLinkNow.initialize(apiKey: "your-api-key", config: [
        "enableLogs": true  // Optional: Enable debug logging
    ])
}
```

### Find Deferred User

```swift
Task {
    if let match = await DeepLinkNow.findDeferredUser() {
        if let deepLink = match.deepLink {
            // Handle the deep link
            print("Found deep link:", deepLink)
        }
        if let attribution = match.attribution {
            // Handle attribution data
            print("Attribution:", attribution)
        }
    }
}
```

### Parse Deep Links

```swift
if let (path, parameters) = DeepLinkNow.parseDeepLink(url) {
    // Handle the deep link
    print("Path:", path)
    print("Parameters:", parameters)
}
```

### Domain Validation

The SDK automatically validates deep links against:

- deeplinknow.com
- deeplink.now
- Your app's verified custom domains (configured in the dashboard)

## Documentation

For detailed documentation, visit [docs.deeplinknow.com](https://docs.deeplinknow.com)

## Support

- 📧 Email: support@deeplinknow.com
- 💬 Discord: [Join our community](https://discord.gg/deeplinknow)

## License

DeepLinkNow is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
