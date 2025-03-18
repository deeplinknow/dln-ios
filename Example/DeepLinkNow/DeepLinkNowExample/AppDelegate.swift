import UIKit
import DeepLinkNow

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Create and set up window
        window = UIWindow(frame: UIScreen.main.bounds)
        let viewController = ViewController()
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()
        
        // Initialize SDK
        Task {
            let config = DLNConfig(apiKey: "test-api-key", enableLogs: true)
            await DeepLinkNow.initialize(apiKey: <#String#>, config: config)
            
            // Check for deferred deep links
            if let response = await DeepLinkNow.findDeferredUser(),
               let deepLinkString = response.deepLink,
               let deepLinkURL = URL(string: deepLinkString) {
                handleDeepLink(deepLinkURL)
            }
        }
        
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        // Handle incoming deep links
        handleDeepLink(url)
        return true
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Handle universal links
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
            handleDeepLink(url)
            return true
        }
        return false
    }
    
    private func handleDeepLink(_ url: URL) {
        if let viewController = window?.rootViewController as? ViewController {
            viewController.handleDeepLink(url)
        }
    }
} 
