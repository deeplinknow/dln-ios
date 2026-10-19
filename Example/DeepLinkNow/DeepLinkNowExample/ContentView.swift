import DeepLinkNow
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: DeepLinkModel

    private let minConfidenceOptions: [Double?] = [nil, 30, 50, 75]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("1. Initialize")) {
                    if let error = model.initError {
                        Text("Init failed: \(error)").foregroundColor(.red)
                    } else {
                        Text(model.isInitialized ? "Initialized" : "Initializing…")
                    }
                }

                Section(header: Text("2. Deferred deep link (first launch)")) {
                    if let error = model.deferredError {
                        Text(error).foregroundColor(.red)
                    }
                    switch model.deferredLink {
                    case .none:
                        Text("Not checked yet")
                    case .some(.none):
                        Text("No deferred deep link")
                    case .some(.some(let link)):
                        Row(label: "path", value: link.path)
                        Row(label: "queryParams", value: describe(link.queryParams))
                        Row(label: "fullPath", value: link.fullPath)
                        Row(label: "source", value: link.source.rawValue)
                        Row(label: "confidenceScore", value: String(format: "%.0f", link.confidenceScore))
                        Row(label: "matchQuality", value: link.matchQuality.rawValue)
                    }

                    Picker("minConfidence", selection: $model.minConfidence) {
                        ForEach(minConfidenceOptions, id: \.self) { value in
                            Text(value.map { String(format: "%.0f", $0) } ?? "Off").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button("Check again (force)") {
                        Task { await model.checkDeferredDeepLink(force: true) }
                    }
                    .disabled(!model.isInitialized)

                    Button("Reset deferred link") { model.resetDeferredDeepLink() }
                        .disabled(!model.isInitialized)
                }

                Section(header: Text("3. Opened by a Universal Link")) {
                    if let link = model.openedLink {
                        Row(label: "path", value: link.path)
                        Row(label: "queryParams", value: describe(link.queryParams))
                        Row(label: "fullPath", value: link.fullPath)
                    } else {
                        Text(model.openedLinkError ?? "Open a link on your DeepLinkNow domain to see it here")
                    }
                }
            }
            .navigationTitle("DeepLinkNow")
        }
    }
}

private struct Row: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).fontWeight(.semibold)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced)).multilineTextAlignment(.trailing)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(model: DeepLinkModel())
    }
}
