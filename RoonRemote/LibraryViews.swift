import SwiftUI

struct LibraryRootView: View {
  @Environment(MockStore.self) private var store
  @State private var launch: LibraryEntry?

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(
          columns: [GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)],
          spacing: 12
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
  @State private var actionsById: [String: [String]] = [:]
  @State private var jump: String?

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
              if let match = page.items.first(where: { $0.title.uppercased().hasPrefix(letter) }) {
                proxy.scrollTo(match.id, anchor: .top)
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
    .task {
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
          ForEach(actions(for: child), id: \.self) { action in
            Button(action) { run(child, title: action) }
          }
        }
        .task {
          await loadActions(for: child)
        }
    } else if child.itemKey != nil {
      NavigationLink(value: child) {
        rowLabel(child)
      }
      .contextMenu {
        ForEach(actions(for: child), id: \.self) { action in
          Button(action) { run(child, title: action) }
        }
      }
      .task {
        await loadActions(for: child)
      }
    } else {
      rowLabel(child)
    }
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
      ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ#"), id: \.self) { letter in
        Button {
          jump = String(letter)
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

  private func actions(for child: BrowseNode) -> [String] {
    actionsById[child.id] ?? child.actions
  }

  private func loadActions(for child: BrowseNode) async {
    guard let key = child.itemKey, actionsById[child.id] == nil else { return }
    let loaded = await store.loadActions(hierarchy: hierarchy, itemKey: key)
    actionsById[child.id] = loaded
  }

  private func run(_ child: BrowseNode, title: String) {
    guard let key = child.itemKey else { return }
    if store.isRecordingAction {
      store.recordBrowseStep(hierarchy: hierarchy, title: child.title)
      let index = actions(for: child).firstIndex(of: title) ?? 0
      store.finishRecording(actionTitle: title, actionIndex: index)
      return
    }
    store.runBrowseAction(hierarchy: hierarchy, itemKey: key, title: title)
  }

  private func reload() async {
    loading = true
    if store.isRecordingAction {
      store.recordBrowseStep(hierarchy: hierarchy, title: title)
    }
    page = await store.loadLibrary(hierarchy: hierarchy, itemKey: itemKey, input: input)
    loading = false
  }
}
