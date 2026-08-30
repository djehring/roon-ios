import SwiftUI

@main
struct RoonRemoteApp: App {
  @State private var store = MockStore.shared
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(store)
        .preferredColorScheme(store.colorScheme)
        .onChange(of: scenePhase) { _, phase in
          if phase == .active {
            store.resumeSync()
          }
        }
    }
  }
}
