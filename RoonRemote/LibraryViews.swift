import SwiftUI

struct LibraryRootView: View {
  @Environment(MockStore.self) private var store
  @Environment(\.horizontalSizeClass) private var hSize
  @State private var launch: LibraryEntry?

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(
          columns: Layout.libraryColumns(hSize),
          spacing: Layout.gridSpacing
        ) {
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
        BrowseListView(hierarchy: entry.hierarchy, title: entry.title)
      }
      .navigationDestination(item: $launch) { entry in
        BrowseListView(hierarchy: entry.hierarchy, title: entry.title)
      }
      .onChange(of: store.libraryLaunchHierarchy) { _, hierarchy in
        guard let hierarchy else { return }
        launch = store.library.first { $0.hierarchy == hierarchy }
          ?? LibraryEntry(id: hierarchy, title: hierarchy, symbol: "music.note", hierarchy: hierarchy)
        store.libraryLaunchHierarchy = nil
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
}

struct BrowseListView: View {
  @Environment(MockStore.self) private var store
  let hierarchy: String
  var itemKey: String?
  var title: String
  var input: String?

  @State private var page = BrowsePage(title: "", items: [])
  @State private var loading = true
  @State private var prompt = ""
  @State private var jump: Character?

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
        } else {
          ScrollViewReader { proxy in
            List {
              ForEach(page.items) { child in
                row(child)
                  .id(child.id)
                  .listRowBackground(Palette.surface)
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
      .navigationDestination(for: BrowseNode.self) { child in
        BrowseListView(
          hierarchy: child.hierarchy ?? hierarchy,
          itemKey: child.itemKey,
          title: child.title
        )
      }
      if showsIndex {
        indexBar
      }
    }
    .task(id: "\(hierarchy)|\(itemKey ?? "")|\(input ?? "")") {
      await reload()
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

  @ViewBuilder
  private func row(_ child: BrowseNode) -> some View {
    if child.isPrompt {
      promptRow(child)
    } else if child.hint == "action" {
      Button {
        run(child, title: child.title)
      } label: {
        rowLabel(child)
      }
    } else if child.hint == "action_list" {
      rowLabel(child)
        .contextMenu {
          ForEach(child.actions, id: \.self) { action in
            Button(action) { run(child, title: action) }
          }
        }
    } else if child.itemKey != nil, isPlaylistContents {
      Button {
        playFromTrack(child)
      } label: {
        rowLabel(child)
      }
      .contextMenu {
        Button("Play From Here") { playFromTrack(child) }
        ForEach(["Play Now", "Queue", "Play Next"], id: \.self) { action in
          Button(action) { run(child, title: action) }
        }
        NavigationLink(value: child) {
          Text("Open")
        }
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

  /// True when browsing the tracks inside a playlist (not the playlist list itself).
  private var isPlaylistContents: Bool {
    hierarchy == "playlists" && itemKey != nil
  }

  private func playFromTrack(_ child: BrowseNode) {
    guard let key = child.itemKey else { return }
    if store.isRecordingAction {
      store.recordBrowseStep(hierarchy: hierarchy, title: child.title)
      store.finishRecording(actionTitle: "Play From Here", actionIndex: 0)
      return
    }
    store.playLibraryItem(hierarchy: hierarchy, itemKey: key, hint: child.hint)
  }

  private func run(_ child: BrowseNode, title: String) {
    guard let key = child.itemKey else { return }
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

  private func rowLabel(_ child: BrowseNode) -> some View {
    HStack(spacing: 12) {
      CoverArt(
        title: child.title,
        image: store.imageData(for: child.imageKey),
        corner: 6
      )
      .frame(width: 48, height: 48)
      VStack(alignment: .leading, spacing: 2) {
        Text(child.title)
        if let subtitle = child.subtitle {
          Text(subtitle)
            .font(.footnote)
            .foregroundStyle(Palette.secondary)
        }
      }
      if isPlaylistContents, child.hint != "action", child.hint != "action_list" {
        Spacer(minLength: 0)
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
      NavigationLink {
        BrowseListView(
          hierarchy: hierarchy,
          itemKey: child.itemKey,
          title: child.title,
          input: prompt
        )
      } label: {
        Text(child.actions.first ?? "Search")
          .foregroundStyle(Palette.accent)
      }
      .disabled(prompt.isEmpty)
    }
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
    if store.isRecordingAction {
      store.recordBrowseStep(hierarchy: hierarchy, title: title)
    }
    page = await store.loadLibrary(hierarchy: hierarchy, itemKey: itemKey, input: input)
  }
}
