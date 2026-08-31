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
  @Namespace private var tabs
  @Namespace private var page

  var body: some View {
    @Bindable var store = store
    VStack(spacing: 0) {
      TVTabBar(selection: $store.selectedTab, focusNamespace: tabs)
        .focusScope(tabs)
        .focusSection()
      Group {
        switch store.selectedTab {
        case .nowPlaying: TVNowPlayingView().prefersDefaultFocus(true, in: page)
        case .library: TVLibraryView()
        case .search: TVSearchView()
        case .rooms: TVRoomsView()
        case .settings: TVSettingsView()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .focusScope(page)
      .focusSection()
    }
  }
}

private struct TVTabBar: View {
  @Binding var selection: AppTab
  var focusNamespace: Namespace.ID

  var body: some View {
    HStack(spacing: 12) {
      ForEach(AppTab.allCases, id: \.self) { tab in
        Button {
          selection = tab
        } label: {
          TVTabBarLabel(tab: tab, selected: selection == tab)
        }
        .tvUnplated()
        .prefersDefaultFocus(tab == selection, in: focusNamespace)
        .frame(maxWidth: .infinity)
      }
    }
    .padding(.horizontal, 56)
    .padding(.top, 32)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity)
  }
}

private struct TVTabBarLabel: View {
  let tab: AppTab
  let selected: Bool
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    Label(tab.title, systemImage: tab.symbol)
      .font(.title3.weight(.medium))
      .labelStyle(.titleAndIcon)
      .foregroundStyle(isFocused || selected ? Palette.onAccent : Palette.primary)
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
      .background(isFocused || selected ? Color.white : Palette.surface)
      .clipShape(Capsule())
      .fixedSize()
  }
}

private extension AppTab {
  var title: String {
    switch self {
    case .nowPlaying: "Now Playing"
    case .library: "Library"
    case .search: "Search"
    case .rooms: "Rooms"
    case .settings: "Settings"
    }
  }

  var symbol: String {
    switch self {
    case .nowPlaying: "play.square.fill"
    case .library: "square.stack.fill"
    case .search: "magnifyingglass"
    case .rooms: "hifispeaker.2.fill"
    case .settings: "gearshape"
    }
  }
}
