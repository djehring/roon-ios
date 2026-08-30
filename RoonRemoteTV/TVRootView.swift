import SwiftUI

struct TVRootView: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    ZStack {
      Palette.background.ignoresSafeArea()
      switch store.session {
      case .onboarding:
        TVOnboardingFlow()
      case .main:
        TVMainTabs()
      }
    }
    .tint(Palette.accent)
    .animation(Motion.sheet, value: store.sessionLabel)
  }
}

private extension MockStore {
  var sessionLabel: String {
    switch session {
    case .main: "main"
    case let .onboarding(step): "onboarding-\(step.rawValue)"
    }
  }
}

struct TVMainTabs: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    @Bindable var store = store
    TabView(selection: $store.selectedTab) {
      TVNowPlayingView()
        .tabItem { Label("Now Playing", systemImage: "play.square.fill") }
        .tag(AppTab.nowPlaying)
      TVLibraryView()
        .tabItem { Label("Library", systemImage: "square.stack.fill") }
        .tag(AppTab.library)
      TVSearchView()
        .tabItem { Label("Search", systemImage: "magnifyingglass") }
        .tag(AppTab.search)
      TVRoomsView()
        .tabItem { Label("Rooms", systemImage: "hifispeaker.2.fill") }
        .tag(AppTab.rooms)
      TVSettingsView()
        .tabItem { Label("Settings", systemImage: "gearshape") }
        .tag(AppTab.settings)
    }
  }
}
