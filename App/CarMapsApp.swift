import SwiftUI
import GoogleMaps

@main
struct CarMapsApp: App {
    @StateObject private var keyStore = KeyStore()

    var body: some Scene {
        WindowGroup {
            if keyStore.ready {
                ContentView(apiKey: keyStore.key)
            } else {
                KeySetupView(keyStore: keyStore)
            }
        }
    }
}

/// The Google API key is typed into the app once (never stored in GitHub).
final class KeyStore: ObservableObject {
    @Published var ready = false
    private(set) var key = ""

    init() {
        if let saved = UserDefaults.standard.string(forKey: "googleKey"), !saved.isEmpty { use(saved) }
    }

    func use(_ k: String) {
        let k = k.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        UserDefaults.standard.set(k, forKey: "googleKey")
        key = k
        GMSServices.provideAPIKey(k)
        ready = true
    }
}

struct KeySetupView: View {
    @ObservedObject var keyStore: KeyStore
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Car Maps 🚗").font(.largeTitle.bold())
            Text("Paste your Google Maps API key. You only do this once.")
            TextField("AIza...", text: $text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Save") { keyStore.use(text) }
                .buttonStyle(.borderedProminent)
            Text("The key needs: Maps SDK for iOS, Routes API, Places API (New).")
                .font(.footnote).foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }
}
