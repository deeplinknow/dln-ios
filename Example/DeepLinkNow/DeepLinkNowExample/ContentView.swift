import SwiftUI
import DeepLinkNow

struct ContentView: View {
    @State private var isInitialized = false
    @State private var matches: [Match]? = nil
    @State private var lastReceivedDeepLink: URL? = nil
    @State private var clipboardContent: String? = nil
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("DeepLinkNow")
                    .font(.system(size: 30, weight: .bold))
                    .padding(.top, 60)
                
                if let deepLink = lastReceivedDeepLink {
                    Text("Last Received Deep Link:")
                        .font(.headline)
                    Text(deepLink.absoluteString)
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                        .padding(.bottom, 20)
                }
                
                Button(action: initDln) {
                    Text(!isInitialized ? "Init DLN" : "Initialized!")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(5)
                }
                
                Button(action: checkClipboardForDeepLink) {
                    Text("Check Clipboard")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(5)
                }
                
                if let content = clipboardContent {
                    Text("Clipboard Content:")
                        .font(.headline)
                    Text(content)
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                        .padding(.bottom, 20)
                }
                
                Button(action: visitExternalDeeplinkPage) {
                    Text("Visit External Deeplink Page")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(5)
                }
                
                Button(action: findDeferredUser) {
                    Text("Find Deferred User")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(5)
                }
                
                if let matches = matches, !matches.isEmpty {
                    Text("Match results")
                        .font(.headline)
                        .padding(.top, 20)
                    
                    ForEach(matches) { match in
                        MatchCard(match: match)
                    }
                }
            }
            .padding(.horizontal, 20)
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
            let config = DLNConfig(apiKey: "web-test-api-key", enableLogs: true)
            await DeepLinkNow.initialize(config: config)
            await MainActor.run {
                isInitialized = true
            }
        }
    }
    
    private func checkClipboardForDeepLink() {
        if let content = DeepLinkNow.checkClipboard() {
            clipboardContent = content
        }
    }
    
    private func visitExternalDeeplinkPage() {
        if let url = URL(string: "https://test-app.deeplinknow.com/sample-link?is_test=true&hello=world&otherParams=false") {
            UIApplication.shared.open(url)
        }
    }
    
    private func findDeferredUser() {
        Task {
            if let response = await DeepLinkNow.findDeferredUser() {
                await MainActor.run {
                    self.matches = response.matches
                }
            }
        }
    }
}

struct MatchCard: View {
    let match: Match
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Confidence: \(String(format: "%.1f%%", match.confidenceScore))")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.blue)
            }
            .padding(.bottom, 8)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(.systemGray5)),
                alignment: .bottom
            )
            
            if let deeplink = match.deeplink {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Deeplink Info")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(.darkText))
                    
                    Text("URL: \(deeplink.targetUrl)")
                        .foregroundColor(.blue)
                    
                    if let campaignId = deeplink.campaignId {
                        Text("Campaign: \(campaignId)")
                            .foregroundColor(Color(.systemGray))
                    }
                    
                    Text("Matched: \(formatDate(deeplink.matchedAt))")
                        .font(.system(size: 12))
                        .foregroundColor(Color(.systemGray2))
                    
                    Text("Expires: \(formatDate(deeplink.expiresAt))")
                        .font(.system(size: 12))
                        .foregroundColor(Color(.systemGray2))
                }
                .padding(.bottom, 16)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Match Details")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(.darkText))
                
                MatchDetailRow(
                    label: "IP Match",
                    matched: match.matchDetails.ipMatch.matched,
                    score: match.matchDetails.ipMatch.score
                )
                
                MatchDetailRow(
                    label: "Device Match",
                    matched: match.matchDetails.deviceMatch.matched,
                    score: match.matchDetails.deviceMatch.score
                )
                
                MatchDetailRow(
                    label: "Locale Match",
                    matched: match.matchDetails.localeMatch.matched,
                    score: match.matchDetails.localeMatch.score
                )
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(10)
        .shadow(
            color: Color.black.opacity(0.25),
            radius: 3.84,
            x: 0,
            y: 2
        )
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .medium
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

struct MatchDetailRow: View {
    let label: String
    let matched: Bool
    let score: Double
    
    var body: some View {
        HStack {
            Text("\(label): \(matched ? "✓" : "✗")")
            Spacer()
            Text("Weight: \(String(format: "%.0f", score))")
        }
        .padding(.vertical, 4)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.systemGray5)),
            alignment: .bottom
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
} 