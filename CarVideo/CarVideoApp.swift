import SwiftUI

@main
struct CarVideoApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            // Pick up videos copied in with the Files app or Finder.
            if phase == .active { VideoLibrary.shared.reload() }
        }
    }
}
