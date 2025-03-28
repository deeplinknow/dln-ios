import SwiftUI
import DeepLinkNow

public struct Match: Identifiable {
    public let id = UUID()
    public let confidenceScore: Double
    public let matchDetails: MatchDetails?
    public let deeplink: DeeplinkInfo?
    
    public struct MatchDetails {
        public let ipMatch: MatchComponent
        public let deviceMatch: MatchComponent
        public let localeMatch: MatchComponent
        
        public struct MatchComponent {
            public let matched: Bool
            public let score: Double
            
            public init(matched: Bool, score: Double) {
                self.matched = matched
                self.score = score
            }
        }
        
        public init(ipMatch: MatchComponent, deviceMatch: MatchComponent, localeMatch: MatchComponent) {
            self.ipMatch = ipMatch
            self.deviceMatch = deviceMatch
            self.localeMatch = localeMatch
        }
    }
    
    public struct DeeplinkInfo {
        public let targetUrl: String
        public let campaignId: String?
        public let matchedAt: Date
        public let expiresAt: Date
        
        public init(targetUrl: String, campaignId: String?, matchedAt: Date, expiresAt: Date) {
            self.targetUrl = targetUrl
            self.campaignId = campaignId
            self.matchedAt = matchedAt
            self.expiresAt = expiresAt
        }
    }
    
    public init(confidenceScore: Double, matchDetails: MatchDetails?, deeplink: DeeplinkInfo?) {
        self.confidenceScore = confidenceScore
        self.matchDetails = matchDetails
        self.deeplink = deeplink
    }
}

struct ContentView: View {
    @State private var isInitialized = false
    @State private var matches: [Match]? = nil
    @State private var lastReceivedDeepLink: URL? = nil
    
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
            isInitialized = true
            
            // Check for deferred deep links
            if let response = await DeepLinkNow.findDeferredUser() {
                // Convert response to matches
                // This is a placeholder - implement based on your SDK's response format
                print(response)
            }
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
                let convertedMatches = response.matches.map { apiMatch -> Match in
                    // Convert match details
                    let matchDetails = Match.MatchDetails(
                        ipMatch: Match.MatchDetails.MatchComponent(
                            matched: apiMatch.matchDetails.ipMatch.matched,
                            score: apiMatch.matchDetails.ipMatch.score
                        ),
                        deviceMatch: Match.MatchDetails.MatchComponent(
                            matched: apiMatch.matchDetails.deviceMatch.matched,
                            score: apiMatch.matchDetails.deviceMatch.score
                        ),
                        localeMatch: Match.MatchDetails.MatchComponent(
                            matched: apiMatch.matchDetails.localeMatch.matched,
                            score: apiMatch.matchDetails.localeMatch.score
                        )
                    )
                    
                    // Convert deeplink info if present
                    let deeplinkInfo: Match.DeeplinkInfo?
                    if let apiDeeplink = apiMatch.deeplink {
                        let dateFormatter = ISO8601DateFormatter()
                        deeplinkInfo = Match.DeeplinkInfo(
                            targetUrl: apiDeeplink.targetUrl,
                            campaignId: apiDeeplink.campaignId,
                            matchedAt: dateFormatter.date(from: apiDeeplink.matchedAt) ?? Date(),
                            expiresAt: dateFormatter.date(from: apiDeeplink.expiresAt) ?? Date()
                        )
                    } else {
                        deeplinkInfo = nil
                    }
                    
                    return Match(
                        confidenceScore: apiMatch.confidenceScore,
                        matchDetails: matchDetails,
                        deeplink: deeplinkInfo
                    )
                }
                
                // Update the UI on the main thread
                await MainActor.run {
                    self.matches = convertedMatches
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
            
            if let details = match.matchDetails {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Match Details")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(.darkText))
                    
                    MatchDetailRow(
                        label: "IP Match",
                        matched: details.ipMatch.matched,
                        score: details.ipMatch.score
                    )
                    
                    MatchDetailRow(
                        label: "Device Match",
                        matched: details.deviceMatch.matched,
                        score: details.deviceMatch.score
                    )
                    
                    MatchDetailRow(
                        label: "Locale Match",
                        matched: details.localeMatch.matched,
                        score: details.localeMatch.score
                    )
                }
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
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