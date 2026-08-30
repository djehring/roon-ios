import SwiftUI

@main
struct RoonRemoteApp: App {
  @State private var store = MockStore.shared
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(store)
        .preferredColorScheme(store.colorScheme)
        .onAppear {
          HardwareVolumeBridge.shared.attach(store: store)
          HardwareVolumeBridge.shared.setActive(true)
          NowPlayingBridge.shared.attach(store: store)
          NowPlayingBridge.shared.publish()
        }
        .onChange(of: scenePhase) { _, phase in
          HardwareVolumeBridge.shared.setActive(phase == .active)
          if phase == .active {
            store.resumeSync()
          }
        }
    }
    .commands {
      RoonCommands(store: store)
    }
  }
}
