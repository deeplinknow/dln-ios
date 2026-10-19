// Sample integration (not compiled into the package). See README.md.
import UIKit
import DeepLinkNow

final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Task {
            do {
                try await DeepLinkNow.initializeThrowing(config: DLNConfig(apiKey: "your-public-api-key"))
                if let link = try await DeepLinkNow.checkDeferredDeepLink() {
                    route(path: link.path, query: link.queryParams)
                }
            } catch {
                print("DeepLinkNow:", error)
            }
        }
        return true
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL,
              let link = DeepLinkNow.parseLink(url) else { return false }
        route(path: link.path, query: link.queryParams)
        return true
    }

    private func route(path: String, query: [String: DLNQueryValue]) {
        // Navigate to `path` with `query` in your app.
    }
}

// Creating a shareable link with custom parameters
func createProductDeepLink(productId: String) -> URL? {
    DeepLinkNow.createDeepLink(
        path: "/product/\(productId)",
        customParameters: DLNCustomParameters(["referrer": "social_share", "discount": 20])
    )
}
