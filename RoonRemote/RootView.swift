import SwiftUI

struct RootView: View {
  @Environment(MockStore.self) private var store
  @Environment(\.horizontalSizeClass) private var hSize

  var body: some View {
    ZStack {
      HardwareVolumeHUDSuppressor()
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
      Palette.background.ignoresSafeArea()
      switch store.session {
      case .onboarding(_):
        OnboardingFlow()
          .disabled(store.showsFindingServer)
      case .main:
        // Size class, not idiom: an iPad in Slide Over or a narrow Stage Manager
        // window is compact, and belongs in the tab layout.
        if hSize == .regular {
          RegularRootView()
            .disabled(store.showsFindingServer)
        } else {
          MainTabs()
            .disabled(store.showsFindingServer)
        }
      }

      if let hud = store.volumeHUD {
        VolumeHUDOverlay(hud: hud)
          .transition(.opacity.combined(with: .scale(scale: 0.92)))
          .allowsHitTesting(false)
      }
    }
    .tint(Palette.accent)
    .modifier(BrowsePlaybackPresentation())
    .modifier(CinemaPresentation())
    .animation(Motion.sheet, value: store.sessionLabel)
    .animation(.easeOut(duration: 0.18), value: store.volumeHUD)
    .onChange(of: hSize) {
      for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
      }
    }
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
      ForEach(AppTab.compactOrder, id: \.self) { tab in
        Tab(tab.title, systemImage: tab.symbol, value: tab) {
          destination(tab)
        }
      }
    }
    .toolbarBackground(.visible, for: .tabBar)
    .toolbarBackground(Palette.surface, for: .tabBar)
    .background(Palette.background)
  }

  @ViewBuilder
  private func destination(_ tab: AppTab) -> some View {
    switch tab {
    case .nowPlaying:
      NowPlayingView()
    case .rooms:
      NavigationStack {
        RegularRoomsView()
      }
    case .library:
      LibraryRootView()
    case .search:
      SearchTabView()
    case .settings:
      SettingsView()
    }
  }
}

/// Destinations for the trailing edge of the navigation bar. On the iPhone
/// Duo in landscape, iOS moves that edge into the column beside the sensor
/// housing, so these fill the strip that otherwise held only the clock.
/// Elsewhere they sit at the top trailing corner as usual. Only the regular
/// layout uses them: the compact layout's tabs already list every destination.
struct StripControls: ToolbarContent {
  let store: MockStore

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarTrailing) {
      ForEach(StripControls.destinations, id: \.self) { tab in
        Button(tab.title, systemImage: tab.symbol) {
          store.selectedTab = tab
        }
      }
    }
  }

  /// Search first, then the remaining Navigate menu entries.
  static let destinations: [AppTab] = [.search, .nowPlaying, .rooms, .library, .settings]
}

extension View {
  func stripControls() -> some View {
    modifier(StripControlsModifier())
  }
}

private struct StripControlsModifier: ViewModifier {
  @Environment(MockStore.self) private var store

  func body(content: Content) -> some View {
    content.toolbar {
      StripControls(store: store)
    }
  }
}
