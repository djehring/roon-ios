import SwiftUI

/// Regular-width shell: a sidebar of destinations with a mini player pinned
/// beneath it, and a navigation stack for whatever the sidebar selects.
///
/// Only ever installed at regular width. `RootView` falls back to `MainTabs` in
/// compact, which covers the iPhone as well as an iPad in Slide Over or a narrow
/// Stage Manager window.
struct RegularRootView: View {
  @Environment(MockStore.self) private var store
  // Optional because that is the shape a sidebar `List(selection:)` binds to.
  @State private var selection: SidebarItem? = .nowPlaying
  @State private var path = NavigationPath()
  @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

  var body: some View {
    GeometryReader { geometry in
      NavigationSplitView(columnVisibility: $columnVisibility) {
        sidebar
          .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 320)
      } detail: {
        NavigationStack(path: $path) {
          detail
        }
        // Applied to the detail column so the queue reflows it rather than
        // covering it. Presented from Now Playing's header button it would sit
        // inside the content and hide that button, leaving no way to close it.
        .inspector(isPresented: queueInspectorPresented) {
          QueueList(embedded: true) {
            store.showQueue = false
          }
          .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
        }
      }
      .navigationSplitViewStyle(.prominentDetail)
      .playbackSheets()
      .onAppear {
        adaptColumns(to: geometry.size.width)
      }
      .onChange(of: geometry.size.width) { _, width in
        adaptColumns(to: width)
      }
      .onChange(of: selection) { _, item in
        // Each destination is its own root, so a drill-down does not survive a
        // jump to a different category.
        path = NavigationPath()
        guard let item else { return }
        store.selectedTab = item.tab
        if case let .search(segment) = item {
          store.searchSegment = segment
        }
      }
      .onChange(of: store.selectedTab) { _, tab in
        syncSelection(to: tab)
      }
      .onChange(of: store.libraryLaunchHierarchy) { _, hierarchy in
        guard let hierarchy else { return }
        selection = .libraryRow(forHierarchy: hierarchy, in: store.library)
        store.libraryLaunchHierarchy = nil
      }
    }
  }

  private var queueInspectorPresented: Binding<Bool> {
    Binding(
      get: { store.showQueue },
      set: { store.showQueue = $0 }
    )
  }

  private func adaptColumns(to width: CGFloat) {
    columnVisibility = RegularShellLayout.prefersPersistentSidebar(containerWidth: width)
      ? .all
      : .detailOnly
  }

  private var sidebar: some View {
    List(selection: $selection) {
      ForEach(SidebarSection.all(library: store.library)) { section in
        if let title = section.title {
          Section(title) { rows(section) }
        } else {
          Section { rows(section) }
        }
      }
    }
    .listStyle(.sidebar)
    .scrollContentBackground(.hidden)
    .background(Palette.background)
    .navigationTitle("Roon")
    .safeAreaInset(edge: .bottom, spacing: 0) {
      miniPlayer
    }
  }

  private func rows(_ section: SidebarSection) -> some View {
    ForEach(section.rows) { row in
      Label(row.title, systemImage: row.symbol)
        .foregroundStyle(Palette.primary)
        .tag(row.item)
    }
  }

  @ViewBuilder
  private var detail: some View {
    switch selection {
    case .nowPlaying:
      RegularNowPlayingView(columnVisibility: $columnVisibility)
    case .rooms:
      RegularRoomsView()
    case .library:
      if let entry = libraryEntry {
        RegularBrowseView(hierarchy: entry.hierarchy, title: entry.title)
          .id(entry.id)
      }
    case .search(.ai):
      AISearchView(regularWidth: true)
        .background(Palette.background)
        .navigationTitle("AI Search")
    case .search(.camera):
      CameraSearchView(regularWidth: true)
        .background(Palette.background)
        .navigationTitle("Cover Camera")
    case .settings:
      SettingsList()
    case .none:
      ContentUnavailableView("Roon", systemImage: "hifispeaker.2")
        .background(Palette.background)
    }
  }

  /// A recorded custom action can name a hierarchy that has no sidebar row, so
  /// an unknown id still resolves to something openable.
  private var libraryEntry: LibraryEntry? {
    guard case let .library(id)? = selection else { return nil }
    return store.library.first { $0.id == id }
      ?? LibraryEntry(id: id, title: id, symbol: "music.note", hierarchy: id)
  }

  private func syncSelection(to tab: AppTab) {
    guard let next = SidebarItem.selection(
      for: tab,
      current: selection,
      library: store.library,
      searchSegment: store.searchSegment,
      pendingLibraryHierarchy: store.libraryLaunchHierarchy
    ) else { return }
    selection = next
  }

  private var miniPlayer: some View {
    VStack(spacing: 0) {
      Divider()
        .background(Palette.hairline)
      HStack(spacing: 10) {
        Button {
          selection = .nowPlaying
        } label: {
          HStack(spacing: 10) {
            CoverArt(
              title: store.currentTrack?.album ?? "empty",
              image: store.imageData(for: store.currentTrack?.imageKey),
              corner: 6
            )
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
              Text(store.currentTrack?.title ?? "Nothing playing")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.primary)
                .lineLimit(1)
              Text(store.selectedZone.name)
                .font(.caption)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
          }
        }
        .buttonStyle(.plain)

        Button {
          store.togglePlay()
        } label: {
          Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
            .font(.footnote)
            .frame(width: 30, height: 30)
            .background(Palette.accent)
            .foregroundStyle(Palette.onAccent)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)

        Button {
          store.showVolume = true
        } label: {
          Image(systemName: "speaker.wave.2.fill")
            .font(.footnote)
            .foregroundStyle(Palette.primary)
            .frame(width: 30, height: 30)
            .background(Palette.surface)
            .clipShape(Circle())
            .overlay { Circle().stroke(Palette.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
    .background(Palette.surface)
  }
}
