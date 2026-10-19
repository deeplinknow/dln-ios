# DeepLinkNow iOS SDK

[![Version](https://img.shields.io/cocoapods/v/DeepLinkNow.svg?style=flat)](https://cocoapods.org/pods/DeepLinkNow)
[![License](https://img.shields.io/cocoapods/l/DeepLinkNow.svg?style=flat)](https://cocoapods.org/pods/DeepLinkNow)
[![Platform](https://img.shields.io/cocoapods/p/DeepLinkNow.svg?style=flat)](https://cocoapods.org/pods/DeepLinkNow)

DeepLinkNow (DLN) does one thing: it gets a new user to the place in your app they tapped before installing (deferred deep linking). It has no analytics, no attribution and no advertising identifiers, and it never shows the ATT prompt.

On iOS the SDK reads the link the DLN landing page copied to the pasteboard (exact), and uses fingerprint matching as a scored backup.

## Requirements

- iOS 13.0+
- Swift 5.5+ (async/await)
- Xcode 13.2+

## Installation

### CocoaPods

```ruby
pod 'DeepLinkNow', '~> 1.2'
```

### Swift Package Manager

```swift
.package(url: "https://github.com/deeplinknow/dln-ios.git", from: "1.2.0")
```

No `Info.plist` keys are needed.

### Universal Links

1. In the DLN dashboard, set your app's **Team ID / App ID prefix** and **Bundle ID**. DLN serves `apple-app-site-association` for your link domains from those values.
2. In Xcode, **Signing & Capabilities → Associated Domains**, add `applinks:<your-alias>.deeplinknow.com`, plus `applinks:<your-custom-domain>` if you have one.

## Usage

### 1. Initialize

```swift
import DeepLinkNow

do {
    let app = try await DeepLinkNow.initializeThrowing(config: DLNConfig(apiKey: "your-public-api-key"))
    print("Link domains:", app.linkDomains)
} catch let error as DeepLinkNowError {
    // .invalidApiKey, .accountInactive, .noCredits, .rateLimited, .network, .server,
    // .invalidResponse, .invalidConfiguration
    print("DeepLinkNow init failed:", error.code)
}
```

`DLNConfig(apiKey:enableLogs:baseUrl:timeout:retryAttempts:)`:

| Option | Default | |
|---|---|---|
| `enableLogs` | `false` | Debug logs prefixed `[DeepLinkNow]`. The API key is never logged. |
| `baseUrl` | `https://deeplinknow.com` | A trailing `/` is fine. Must be https (http only for localhost). |
| `timeout` | `10` s | Per request. |
| `retryAttempts` | `2` | Retries transport errors, timeouts, 5xx and 429 with backoff (at most 5 retries, each delay at most 5 s). 4xx is never retried. |

`await DeepLinkNow.initialize(config:)` never throws. It logs failures instead; check `DeepLinkNow.isInitialized` and `DeepLinkNow.initializationError` (or `DeepLinkNow.lastError`).

### 2. Get the deferred deep link (first launch)

```swift
if let link = await DeepLinkNow.checkDeferredDeepLink() {
    // link.path        "/products/123"           (not decoded)
    // link.queryParams ["ref": .string("newsletter")]
    // link.fullPath    "/products/123?ref=newsletter"
    // link.url         "https://myapp.deeplinknow.com/products/123?ref=newsletter"
    // link.source      .clipboard or .fingerprint
    // link.confidenceScore / link.matchQuality (100 / .high for the clipboard)
    router.open(path: link.path, query: link.queryParams)
}
// No link? Carry on to your normal start screen.
```

`checkDeferredDeepLink` never throws. `nil` means there was no link, or the check failed (not initialized, offline, invalid key…). A failure is logged as a warning and kept in `DeepLinkNow.lastError` (a `DeepLinkNowError`) until the next successful check, and it does not consume the first launch, so a later call tries again. If you want the error thrown, use `try await DeepLinkNow.checkDeferredDeepLinkThrowing()`.

What it does:

1. **Pasteboard** (`useClipboard`, default `true`): if the pasteboard holds a link on one of your link domains, that link is returned (`source: .clipboard`) and no match request is made. On iOS 16+ the system may ask the user to allow pasting from Safari; "Don't Allow" just moves on to step 2. A pattern check that does not show the prompt runs first, so there is no prompt when the pasteboard has no web URL.
2. **Fingerprint** (`POST /api/v1/sdk/match`): the first server candidate (sorted by confidence) that has a deep link is returned (`source: .fingerprint`) with the server's `confidenceScore` and `matchQuality` (HIGH ≥ 75, MEDIUM ≥ 50, LOW ≥ 30).

Options (`DLNDeferredOptions`):

```swift
await DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(
    minConfidence: 50,   // default nil = accept every candidate; you choose the threshold
    useClipboard: false, // skip the pasteboard (no paste prompt; fingerprint only)
    force: false         // ignore the first-launch flag
))
```

**First launch only.** After a definitive answer (a link, or definitely nothing) the SDK sets a flag in `UserDefaults` (`com.deeplinknow.deferredCheckCompleted`), and later calls return `nil` without network or pasteboard access. Errors do not set the flag. The pasteboard is read at most once per install. Call `DeepLinkNow.resetDeferredDeepLink()` to clear this state while testing. Concurrent calls share one run.

### 3. Universal Links that open the installed app

```swift
// SwiftUI
.onOpenURL { url in
    if let link = DeepLinkNow.parseLink(url) { router.open(path: link.path, query: link.queryParams) }
}

// UIKit
func application(_ application: UIApplication, continue userActivity: NSUserActivity,
                 restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL,
          let link = DeepLinkNow.parseLink(url) else { return false }
    router.open(path: link.path, query: link.queryParams)
    return true
}
```

`parseLink` returns `DLNParsedLink` (`path`, `queryParams`, `fullPath`, `url`), the same shape and rules as `checkDeferredDeepLink`, so deferred and direct opens route identically. `parseDeepLink(_:)` returns the same data as a `(path, parameters)` tuple, with `String`, `true` or `[String]` values.

Query parameters follow `URLSearchParams`: `+` is a space, `?flag` and `?flag=` become `.flag`, and a repeated key becomes `.list([...])`. `DLNQueryValue` has `stringValue`, `stringValues` and `anyValue`.

### Link domains

After initialization, a link is accepted only when its host exactly equals (ignoring case) one of your app's link domains:

- `<your-alias>.deeplinknow.com`
- your verified custom domain(s)

Other `*.deeplinknow.com` subdomains, the apex `deeplinknow.com` and lookalike hosts are rejected. Before initialization has finished, `parseLink` / `isValidDomain` provisionally accept any `<alias>.deeplinknow.com` (but not custom domains), so a cold-start Universal Link is not lost.

### Other APIs

| API | |
|---|---|
| `DeepLinkNow.findDeferredUserThrowing() async throws -> MatchResponse` | All fingerprint candidates, unfiltered, with `matchQuality`, `deeplink.queryParams`, `deeplink.fullPath`. |
| `DeepLinkNow.findDeferredUser() async -> MatchResponse?` | Same, `nil` on any error. |
| `DeepLinkNow.checkClipboard() -> String?` | The pasteboard text if it is exactly one link on your domains. Reads the pasteboard (may prompt). |
| `DeepLinkNow.hasDeepLinkToken() -> Bool` | Cheap hint (`hasURLs`/`hasStrings`), never reads the content, never prompts. |
| `DeepLinkNow.hasDeepLinkTokenAsync() async -> Bool` | Same, using `detectPatterns(for: [.probableWebURL])` on iOS 14+. |
| `DeepLinkNow.isValidDomain(_ host:) -> Bool` | The link-domain rule above. |
| `DeepLinkNow.createDeepLink(path:customParameters:) -> URL?` | An https link on your primary link domain (custom domain if verified) that `parseLink` round-trips. `nil` before init. |
| `DeepLinkNow.isInitialized`, `initializationError`, `appInfo` | Init state. |

Deprecated: `handleUniversalLink(_:)` (use `parseLink(_:)`; it now returns the parsed link) and `handleCustomScheme(_:)` (custom URL schemes are not supported; it does nothing).

## Privacy

The SDK ships a `PrivacyInfo.xcprivacy`:

- `NSPrivacyTracking = false`, no tracking domains.
- Collected: Device ID (the `identifierForVendor`, IDFV) for App Functionality, not linked to identity, not used for tracking. The server uses it to claim a click for this install.
- Required-reason API: `UserDefaults` (`CA92.1`) for the first-launch state.

The match request sends: a Safari-style user agent, `ios`, OS version, device class (`iPhone`/`iPad`), locale, time zone, screen size in points and scale, CPU core count, and the IDFV. It never reads the IDFA, never links AdSupport or AppTrackingTransparency, and never sends an IP address (the server sees the connection). Nothing is stored on the device except the first-launch state and a copy of the last `/init` result (your public key, link domains and app info, no device data), which lets a launch within 24 hours skip the network call.

## Documentation

Full reference: [DOCS.md](DOCS.md) and [deeplinknow.com/docs/ios](https://deeplinknow.com/docs/ios).

## Support

- Email: support@deeplinknow.com

## License

DeepLinkNow is available under the MIT license. See [LICENSE.txt](LICENSE.txt).
