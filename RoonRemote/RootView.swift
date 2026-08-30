import SwiftUI

struct RootView: View {
  @Environment(MockStore.self) private var store
  @Environment(\.horizontalSizeClass) private var hSize

  var body: some View {
    ZStack {
      Palette.background.ignoresSafeArea()
      switch store.session {
      case .onboarding(_):
        OnboardingFlow()
      case .main:
        // Size class, not idiom: an iPad in Slide Over or a narrow Stage Manager
        // window is compact, and belongs in the tab layout.
        if hSize == .regular {
          RegularRootView()
        } else {
          MainTabs()
        }
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

struct MainTabs: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    @Bindable var store = store
    TabView(selection: $store.selectedTab) {
      NowPlayingView()
        .tabItem {
          Label("Now Playing", systemImage: "play.square.fill")
        }
        .tag(AppTab.nowPlaying)
      LibraryRootView()
        .tabItem {
          Label("Library", systemImage: "square.stack.fill")
        }
        .tag(AppTab.library)
      SearchTabView()
        .tabItem {
          Label("Search", systemImage: "magnifyingglass")
        }
        .tag(AppTab.search)
      SettingsView()
        .tabItem {
          Label("Settings", systemImage: "gearshape")
        }
        .tag(AppTab.settings)
    }
    .toolbarBackground(.visible, for: .tabBar)
    .toolbarBackground(Palette.surface, for: .tabBar)
    .background(Palette.background)
  }
}
