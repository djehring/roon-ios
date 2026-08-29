import SwiftUI

@main
struct RoonRemoteApp: App {
  @State private var store = MockStore()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(store)
        .preferredColorScheme(store.colorScheme)
    }
  }
}
