import SwiftUI

@main
struct RoonRemoteTVApp: App {
  @State private var store = MockStore()

  var body: some Scene {
    WindowGroup {
      TVRootView()
        .environment(store)
        .preferredColorScheme(.dark)
    }
  }
}
