# DeepLinkNow iOS example

A SwiftUI app that shows the whole DeepLinkNow iOS integration. All SDK calls are in `DeepLinkNowExample/DeepLinkModel.swift`:

1. `DeepLinkNow.initializeThrowing(config:)` at startup. It throws a `DeepLinkNowError`, which the screen shows.
2. `DeepLinkNow.checkDeferredDeepLink(DLNDeferredOptions(minConfidence:))` once, on first launch. The screen shows `path`, `queryParams`, `fullPath`, `source`, `confidenceScore` and `matchQuality`. On iOS the SDK reads the pasteboard first (the landing page copied the link there; iOS 16+ may ask the user to allow pasting), then falls back to fingerprint matching.
3. `DeepLinkNow.parseLink(_:)` for Universal Links that open the installed app (`DeepLinkNowExampleApp.swift`: `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`).

For testing, the screen also has a **minConfidence** picker (Off / 30 / 50 / 75), **Check again (force)** and **Reset deferred link** (`resetDeferredDeepLink()`).

## Requirements

- Xcode 15+ (the project uses Xcode 16 folder-synchronised groups), CocoaPods
- The SDK supports iOS 13+. The example app target is set to a recent iOS version.

## Run

```bash
cd packages/dln-ios/Example/DeepLinkNow
pod install
open DeepLinkNowExample.xcworkspace
```

Or build from the command line:

```bash
xcodebuild build -workspace DeepLinkNowExample.xcworkspace -scheme DeepLinkNowExample \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Replace `apiKey` in `DeepLinkModel.swift` with your app's key. `test_api_key` is DeepLinkNow's demo key and returns sample data.

The project sets `ENABLE_USER_SCRIPT_SANDBOXING = NO`: CocoaPods' "Copy Pods Resources" script (which copies the SDK's privacy manifest bundle) can't run inside Xcode's script sandbox.

### Universal Links

To open the app from your links, add the Associated Domains capability (Signing & Capabilities → + Capability → Associated Domains) with `applinks:{alias}.deeplinknow.com`, plus `applinks:{your custom domain}` if you have one. In the dashboard, set the app's Team ID and Bundle ID so DeepLinkNow serves a matching `apple-app-site-association`. This needs a signed build with your team.

## Local SDK (default) vs published SDK

Until DeepLinkNow 1.1.0 is published, the example builds the SDK from this repository. The `Podfile` has:

```ruby
pod 'DeepLinkNow', :path => '../../'      # local source: packages/dln-ios
```

After 1.1.0 is on CocoaPods trunk, switch to the published pod by replacing that line with:

```ruby
pod 'DeepLinkNow', '~> 1.1.0'
```

then run `pod install` again.
