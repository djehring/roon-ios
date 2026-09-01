import SwiftUI

@main
struct RoonRemoteApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.scenePhase) private var scenePhase
  @State private var store: MockStore?

  var body: some Scene {
    WindowGroup {
      ZStack {
        if let store {
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
              switch phase {
              case .active:
                store.resumeSync()
                NowPlayingBridge.shared.publish()
              case .inactive, .background:
                // Do not refreshEvents here. That tears down the SSE stream and
                // the next zone tick never arrives, so the lock-screen card freezes.
                NowPlayingBridge.shared.publish()
                LiveActivityBridge.shared.publish()
              default:
                break
              }
            }
        }
        if store?.showsFindingServer ?? true {
          FindingServerOverlay()
        }
      }
      .task {
        // First frame is the overlay. Constructing the store (keychain,
        // watch session, reconnect) must not hold the launch screen.
        await Task.yield()
        if store == nil {
          store = MockStore.shared
        }
      }
    }
    .commands {
      if let store {
        RoonCommands(store: store)
      }
    }
  }
}
