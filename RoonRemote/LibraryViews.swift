import SwiftUI
import UIKit

/// Labels are presentation only: execute the original Roon node and action title.
struct BrowseActionPicker: Identifiable {
  let child: BrowseNode
  let actions: [BrowseNode]
  let tracks: [BrowseNode]
  var id: String { child.id }

  private static let primaryTitles = [["play from here"], ["play now"], ["add next", "play next"], ["queue"]]

  var primaryActions: [BrowseNode] {
    Self.primaryTitles.compactMap { titles in
      if !tracks.isEmpty, titles.contains("play from here") { return nil }
      return actions.first { titles.contains($0.title.lowercased()) }
    }
  }

  var moreActions: [BrowseNode] {
    actions.filter { action in
      !Self.primaryTitles.contains { $0.contains(action.title.lowercased()) }
    }
  }

  func label(for action: BrowseNode) -> String {
    switch action.title.lowercased() {
    case "play now" where child.isCollectionTrack: "Play This Track"
    case "add next", "play next": "Play Next"
    case "queue": "Add to End"
    default: action.listedTitle
    }
  }
}

/// A popover supports a real submenu while keeping the everyday actions visible.
struct BrowseActionsPopover: View {
  @Environment(\.dismiss) private var dismiss
  let selection: BrowseActionPicker
  let playFromHere: () -> Void
  let run: (BrowseNode) -> Void

  var body: some View {
    VStack(spacing: 8) {
      Text(selection.child.listedTitle)
        .font(.headline)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 8)
      if !selection.tracks.isEmpty {
        actionButton("Play From Here", action: playFromHere)
      }
      ForEach(selection.primaryActions) { action in
        actionButton(selection.label(for: action)) { run(action) }
      }
      if !selection.moreActions.isEmpty {
        Menu {
          ForEach(selection.moreActions) { action in
            Button(selection.label(for: action)) {
              dismiss()
              run(action)
            }
          }
        } label: {
          Label("More…", systemImage: "ellipsis")
            .frame(maxWidth: .infinity, minHeight: 32)
        }
      }
    }
    .buttonStyle(.bordered)
    .buttonBorderShape(.capsule)
    .controlSize(.large)
    .tint(Palette.accent)
    .padding(20)
    .frame(width: 300)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button {
      dismiss()
      action()
    } label: {
      Text(title).frame(maxWidth: .infinity, minHeight: 32)
    }
  }
}

struct LibraryRootView: View {
  @Environment(MockStore.self) private var store
  @Environment(\.horizontalSizeClass) private var hSize
  @State private var path = NavigationPath()

  var body: some View {
    NavigationStack(path: $path) {
      ScrollView {
        LazyVGrid(
          columns: Layout.libraryColumns(hSize),
          spacing: Layout.gridSpacing
        ) {
          NavigationLink { HistoryView() } label: {
            VStack(alignment: .leading, spacing: 12) {
              Image(systemName: "clock.arrow.circlepath").font(.system(size: 22, weight: .medium)).foregroundStyle(Palette.accent)
              Text("Recently played").font(.headline).foregroundStyle(Palette.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(16).background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
          }.accessibilityIdentifier("open-history")
          ForEach(store.library) { entry in
            NavigationLink(value: entry) {
              VStack(alignment: .leading, spacing: 12) {
                Image(systemName: entry.symbol)
                  .font(.system(size: 22, weight: .medium))
                  .foregroundStyle(Palette.accent)
                Text(entry.title)
                  .font(.headline)
                  .foregroundStyle(Palette.primary)
              }
              .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
              .padding(16)
              .background(Palette.surface)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .stroke(Palette.hairline, lineWidth: 1)
              }
            }
          }
        }
        .padding(20)
      }
      .background(Palette.background)
      .navigationTitle("Library")
      .navigationDestination(for: LibraryEntry.self) { entry in
        BrowseListView(
          hierarchy: entry.hierarchy,
          title: entry.title,
          openChild: entry.openChild,
          path: $path
        )
      }
      .navigationDestination(for: BrowseNode.self) { child in
        BrowseListView(
          hierarchy: child.hierarchy ?? "browse",
          itemKey: child.itemKey,
          title: child.title,
          path: $path
        )
      }
      .navigationDestination(for: BrowseSearch.self) { query in
        BrowseListView(
          hierarchy: query.hierarchy,
          itemKey: query.itemKey,
          title: query.title,
          input: query.input,
          path: $path
        )
      }
      .navigationDestination(for: ArtistDiscography.self) { artist in
        BrowseListView(
          hierarchy: "search",
          title: artist.name,
          artist: artist,
          path: $path
        )
      }
      // onAppear as well as onChange: TabView may create this tab after
      // runToolbar already wrote libraryLaunchHierarchy, so onChange alone
      // never sees a transition and Playlists would land on the Library grid.
      .onAppear {
        consumeLaunchHierarchy()
        consumeLaunchArtist()
      }
      .onChange(of: store.libraryLaunchHierarchy) { _, _ in
        consumeLaunchHierarchy()
      }
      .onChange(of: store.libraryLaunchArtist) { _, _ in
        consumeLaunchArtist()
      }
      .toolbar {
        if store.isRecordingAction {
          ToolbarItem(placement: .status) {
            Text("Recording")
              .font(.caption.weight(.semibold))
              .foregroundStyle(Palette.onAccent)
              .padding(.horizontal, 10)
              .padding(.vertical, 4)
              .background(Palette.accent)
              .clipShape(Capsule())
          }
        }
      }
    }
  }

  private func consumeLaunchHierarchy() {
    guard let hierarchy = store.libraryLaunchHierarchy else { return }
    // Same stack the grid uses. An item destination rematerializes when the
    // playlists page finishes loading, which drops the playlist just pushed
    // and shows the full list again.
    path = NavigationPath()
    path.append(LibraryEntry.forLaunchHierarchy(hierarchy, in: store.library))
    store.libraryLaunchHierarchy = nil
  }

  private func consumeLaunchArtist() {
    guard let artist = store.libraryLaunchArtist else { return }
    path = NavigationPath([artist])
    store.libraryLaunchArtist = nil
  }
}

struct BrowseListView: View {
  @Environment(MockStore.self) private var store
  let hierarchy: String
  var itemKey: String?
  var title: String
  var input: String?
  var openChild: String?
  var artist: ArtistDiscography?
  @Binding var path: NavigationPath

  @State private var page = BrowsePage(title: "", items: [])
  @State private var loading = true
  @State private var prompt = ""
  @State private var jump: Character?
  @State private var actionPicker: BrowseActionPicker?

  private static let titlesWithIndex = [
    "Albums", "Artists", "Composers", "My Live Radio", "Playlists", "Tags", "Radios",
  ]

  var body: some View {
    ZStack(alignment: .trailing) {
      Group {
        if loading {
          ProgressView()
            .tint(Palette.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = page.errorMessage {
          ContentUnavailableView {
            Label("Couldn't load", systemImage: "exclamationmark.circle")
          } description: {
            Text(message)
          } actions: {
            Button("Try Again") { Task { await reload() } }
          }
        } else {
          ScrollViewReader { proxy in
            List {
              ForEach(page.items) { child in
                row(child)
                  .id(child.id)
                  .listRowBackground(Palette.surface)
                  .popover(item: Binding(
                    get: { actionPicker?.id == child.id ? actionPicker : nil },
                    set: { actionPicker = $0 }
                  )) { selection in
                    BrowseActionsPopover(selection: selection) {
                      playTracks(selection.tracks)
                    } run: { action in
                      run(action, title: action.title)
                    }
                    .presentationCompactAdaptation(.popover)
                  }
              }
            }
            .scrollContentBackground(.hidden)
            .onChange(of: jump) { _, letter in
              guard let letter else { return }
              if let target = LibraryIndex.jumpTarget(for: letter, in: page.items) {
                proxy.scrollTo(target, anchor: .top)
              }
              jump = nil
            }
          }
        }
      }
      .background(Palette.background)
      .navigationTitle(page.title.isEmpty ? title : page.title)
      if showsIndex {
        indexBar
      }
    }
    .task(id: "\(hierarchy)|\(itemKey ?? "")|\(input ?? "")|\(artist?.token.uuidString ?? "")") {
      await reload()
    }
    .safeAreaInset(edge: .top) {
      if let source = page.musicSource {
        CreateCinemaFromMusicButton(path: source, title: page.title).padding(12).background(Palette.background)
      }
    }
    .safeAreaInset(edge: .bottom) {
      if store.isRecordingAction {
        recordingBar
      }
    }
  }

  private var showsIndex: Bool {
    Self.titlesWithIndex.contains(page.title.isEmpty ? title : page.title)
  }

  /// True when browsing the tracks inside a playlist (not the playlist list itself).
  private var isPlaylistContents: Bool {
    hierarchy == "playlists" && itemKey != nil
  }

  @ViewBuilder
  private func row(_ child: BrowseNode) -> some View {
    if child.isPrompt {
      promptRow(child)
    } else if child.hint == "action" {
      listButton {
        run(child, title: child.title)
      } label: {
        rowLabel(child)
      }
    } else if child.hint == "action_list" {
      listButton {
        openActionList(child)
      } label: {
        rowLabel(child)
      }
      .contextMenu {
        if !tracksFrom(child).isEmpty {
          Button("Play From Here") { playFromTrack(child) }
        }
        Button("Actions…") { openActionList(child) }
      }
    } else if child.itemKey != nil, isPlaylistContents {
      listButton {
        playFromTrack(child)
      } label: {
        rowLabel(child, showPlay: true)
      }
      .contextMenu {
        Button("Play From Here") { playFromTrack(child) }
        Button("Play This Track") { run(child, title: "Play Now") }
        Button("Play Next") { run(child, title: "Play Next") }
        Button("Add to End") { run(child, title: "Queue") }
        Button("Actions…") { openActionList(child) }
      }
    } else if child.itemKey != nil {
      NavigationLink(value: child) {
        rowLabel(child)
      }
      .contextMenu {
        ForEach(child.actions, id: \.self) { action in
          Button(action) { run(child, title: action) }
        }
      }
    } else {
      rowLabel(child)
    }
  }

  /// List rows swallow default Button taps; borderless + full-row hit target fixes that.
  private func listButton(
    action: @escaping () -> Void,
    @ViewBuilder label: () -> some View
  ) -> some View {
    Button(action: action) {
      label()
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
  }

  private func playFromTrack(_ child: BrowseNode) {
    playTracks(tracksFrom(child))
  }

  private func tracksFrom(_ child: BrowseNode) -> [BrowseNode] {
    page.tracksFrom(child, hierarchy: hierarchy, parentKey: itemKey)
  }

  private func playTracks(_ tracks: [BrowseNode]) {
    guard let child = tracks.first else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    if store.isRecordingAction {
      store.recordBrowseStep(hierarchy: hierarchy, title: child.title)
      store.finishRecording(actionTitle: "Play From Here", actionIndex: 0)
      return
    }
    store.playLibraryTracks(tracks, hierarchy: hierarchy)
  }

  private func openActionList(_ child: BrowseNode) {
    guard let key = child.itemKey else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    Task {
      let actions = await store.loadItemActions(hierarchy: hierarchy, itemKey: key)
      let tracks = tracksFrom(child)
      if actions.isEmpty, tracks.isEmpty {
        // Fall back to playing if Roon didn't expose a menu.
        store.playLibraryItem(hierarchy: hierarchy, itemKey: key, hint: child.hint)
        return
      }
      actionPicker = BrowseActionPicker(child: child, actions: actions, tracks: tracks)
    }
  }

  private func run(_ child: BrowseNode, title: String) {
    guard let key = child.itemKey else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    if store.isRecordingAction {
      store.recordBrowseStep(hierarchy: hierarchy, title: child.title)
      let index = child.actions.firstIndex(of: title) ?? 0
      store.finishRecording(actionTitle: title, actionIndex: index)
      return
    }
    store.runBrowseAction(
      hierarchy: hierarchy,
      itemKey: key,
      title: title,
      hint: child.hint
    )
  }

  private func rowLabel(_ child: BrowseNode, showPlay: Bool = false) -> some View {
    HStack(spacing: 12) {
      CoverArt(
        title: child.title,
        image: store.imageData(for: child.imageKey),
        corner: 6
      )
      .frame(width: 48, height: 48)
      VStack(alignment: .leading, spacing: 2) {
        Text(child.listedTitle)
        if !child.listedSubtitle.isEmpty {
          Text(child.listedSubtitle)
            .font(.footnote)
            .foregroundStyle(Palette.secondary)
        }
      }
      Spacer(minLength: 0)
      if showPlay {
        Image(systemName: "play.circle.fill")
          .foregroundStyle(Palette.accent)
          .font(.title3)
      }
    }
  }

  private func promptRow(_ child: BrowseNode) -> some View {
    HStack {
      TextField(child.title, text: $prompt)
        .textInputAutocapitalization(.never)
        .submitLabel(.search)
        .onSubmit { submitSearch(child) }
      Button(child.actions.first ?? "Search") {
        submitSearch(child)
      }
      .foregroundStyle(Palette.accent)
      .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }

  private func submitSearch(_ child: BrowseNode) {
    guard let query = BrowseSearch.submitted(
      hierarchy: hierarchy,
      child: child,
      prompt: prompt
    ) else { return }
    path.append(query)
  }

  private var indexBar: some View {
    VStack(spacing: 0) {
      ForEach(LibraryIndex.letters, id: \.self) { letter in
        Button {
          jump = letter
        } label: {
          Text(String(letter))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Palette.tertiary)
        }
      }
    }
    .padding(.trailing, 4)
  }

  private var recordingBar: some View {
    HStack {
      Button("Cancel") { store.cancelRecording() }
      Spacer()
      Text(store.recordingPath.joined(separator: " › "))
        .font(.caption)
        .foregroundStyle(Palette.secondary)
        .lineLimit(1)
    }
    .padding()
    .background(Palette.surface)
  }

  private func reload() async {
    loading = true
    defer { loading = false }
    if let artist {
      page = await store.loadArtistDiscography(artist)
      return
    }
    if store.isRecordingAction {
      store.recordBrowseStep(hierarchy: hierarchy, title: title)
    }
    page = await store.loadLibrary(
      hierarchy: hierarchy,
      itemKey: itemKey,
      input: input,
      childTitled: openChild
    )
  }
}
