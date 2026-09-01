import SwiftUI

@main
struct RoonRemoteTVApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @State private var store: MockStore?

  var body: some Scene {
    WindowGroup {
      ZStack {
        if let store {
          TVRootView()
            .environment(store)
            .preferredColorScheme(.dark)
            .onAppear {
              TVHardwareVolumeBridge.shared.attach(store: store)
              TVHardwareVolumeBridge.shared.setActive(true)
            }
            .onChange(of: scenePhase) { _, phase in
              TVHardwareVolumeBridge.shared.setActive(phase == .active)
              if phase == .active {
                store.resumeSync()
              }
            }
        }
        if store?.showsFindingServer ?? true {
          FindingServerOverlay()
        }
      }
      .task {
        await Task.yield()
        if store == nil {
          store = MockStore()
        }
      }
    }
  }
}
