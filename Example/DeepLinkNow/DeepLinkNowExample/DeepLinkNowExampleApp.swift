import SwiftUI

@main
struct DeepLinkNowExampleApp: App {
    @StateObject private var model = DeepLinkModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                // 1 + 2: initialize, then check for a deferred deep link (first launch only).
                .task { await model.start() }
                // 3: Universal Links that open the installed app. SwiftUI delivers them as a
                // browsing-web user activity (and custom schemes through onOpenURL).
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { model.handleOpenedLink(url) }
                }
                .onOpenURL { url in model.handleOpenedLink(url) }
        }
    }
}
