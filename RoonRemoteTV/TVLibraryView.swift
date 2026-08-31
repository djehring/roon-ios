import SwiftUI

struct TVLibraryView: View {
  @Environment(MockStore.self) private var store
  @State private var path = NavigationPath()

  var body: some View {
    NavigationStack(path: $path) {
      categoryRoot
        .navigationTitle("Library")
        .navigationDestination(for: LibraryEntry.self) { entry in
          TVBrowsePageView(
            hierarchy: entry.hierarchy,
            title: entry.title,
            openChild: entry.openChild,
            path: $path
          )
        }
        .navigationDestination(for: BrowseNode.self) { node in
          TVBrowsePageView(
            hierarchy: node.hierarchy ?? "browse",
            itemKey: node.itemKey,
            title: node.title,
            path: $path
          )
        }
        .navigationDestination(for: BrowseSearch.self) { query in
          TVBrowsePageView(
            hierarchy: query.hierarchy,
            itemKey: query.itemKey,
            title: query.title,
            input: query.input,
            path: $path
          )
        }
        .onAppear { consumeLaunchHierarchy() }
        .onChange(of: store.libraryLaunchHierarchy) { _, _ in
          consumeLaunchHierarchy()
        }
    }
  }

  private func consumeLaunchHierarchy() {
    guard let hierarchy = store.libraryLaunchHierarchy else { return }
    let entry = LibraryEntry.forLaunchHierarchy(hierarchy, in: store.library)
    path = NavigationPath()
    path.append(entry)
    store.libraryLaunchHierarchy = nil
  }

  private var categoryRoot: some View {
    ScrollView {
      LazyVGrid(
        columns: [
          GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 48),
        ],
        spacing: 48
      ) {
        ForEach(store.library) { entry in
          Button { path.append(entry) } label: {
            TVLibraryCategoryCard(entry: entry)
          }
          .tvUnplated()
        }
      }
      .padding(40)
    }
    .focusSection()
  }
}

struct TVBrowsePageView: View {
  @Environment(MockStore.self) private var store
  let hierarchy: String
  var itemKey: String?
  var title: String
  var input: String?
  var openChild: String?
  @Binding var path: NavigationPath

  @State private var page = BrowsePage(title: "", items: [])
  @State private var loading = true
  @State private var prompt = ""

  private var promptNode: BrowseNode? {
    page.items.first(where: \.isPrompt)
  }

  private var catalog: [BrowseNode] {
    page.items.filter { !$0.isPrompt }
  }

  var body: some View {
    Group {
      if loading {
        ProgressView()
          .tint(Palette.accent)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        VStack(spacing: 0) {
          if let promptNode {
            searchBar(promptNode)
              .focusSection()
          }
          if catalog.isEmpty {
            ContentUnavailableView(
              "Nothing here",
              systemImage: "music.note",
              description: Text("Try another category.")
            )
          } else {
            ScrollView {
              LazyVGrid(
                columns: [
                  GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 48),
                ],
                spacing: 48
              ) {
                ForEach(catalog) { child in
                  cell(child)
                }
              }
              .padding(40)
            }
            .focusSection()
          }
        }
      }
    }
    .navigationTitle(page.title.isEmpty ? title : page.title)
    .task(id: "\(hierarchy)|\(itemKey ?? "")|\(input ?? "")|\(openChild ?? "")") {
      await reload()
    }
    .onAppear {
      if prompt.isEmpty, let input, !input.isEmpty {
        prompt = input
      }
    }
  }

  private var isPlaylistContents: Bool {
    hierarchy == "playlists" && itemKey != nil
  }

  private func searchBar(_ child: BrowseNode) -> some View {
    HStack(spacing: 28) {
      TextField(child.title, text: $prompt)
        .font(.title2)
        .onSubmit { submit(child) }

      TVPrimaryButton(title: child.actions.first ?? "Search", minHeight: 64) {
        submit(child)
      }
      .frame(width: 220)
      .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .padding(.horizontal, 40)
    .padding(.top, 28)
    .padding(.bottom, 12)
  }

  private func submit(_ child: BrowseNode) {
    guard let query = BrowseSearch.submitted(
      hierarchy: hierarchy,
      child: child,
      prompt: prompt
    ) else { return }
    path.append(query)
  }

  @ViewBuilder
  private func cell(_ child: BrowseNode) -> some View {
    if child.hint == "action" {
      Button { run(child, title: child.title) } label: {
        card(child)
      }
      .tvUnplated()
    } else if child.itemKey != nil, isPlaylistContents {
      Button { playFromTrack(child) } label: {
        card(child)
      }
      .tvUnplated()
      .contextMenu {
        Button("Play From Here") { playFromTrack(child) }
        Button("Play Now") { run(child, title: "Play Now") }
        Button("Queue") { run(child, title: "Queue") }
        Button("Play Next") { run(child, title: "Play Next") }
      }
    } else if child.itemKey != nil, child.hint != "action_list" {
      Button { path.append(child) } label: {
        card(child)
      }
      .tvUnplated()
      .contextMenu {
        ForEach(child.actions, id: \.self) { action in
          Button(action) { run(child, title: action) }
        }
      }
    } else {
      Button {
        if let first = child.actions.first {
          run(child, title: first)
        }
      } label: {
        card(child)
      }
      .tvUnplated()
      .contextMenu {
        ForEach(child.actions, id: \.self) { action in
          Button(action) { run(child, title: action) }
        }
      }
    }
  }

  private func card(_ child: BrowseNode) -> some View {
    TVBrowseCard(
      title: child.title,
      subtitle: child.subtitle,
      image: store.imageData(for: child.imageKey)
    )
  }

  private func playFromTrack(_ child: BrowseNode) {
    guard let key = child.itemKey else { return }
    store.playLibraryItem(hierarchy: hierarchy, itemKey: key, hint: child.hint)
  }

  private func run(_ child: BrowseNode, title: String) {
    guard let key = child.itemKey else { return }
    store.runBrowseAction(
      hierarchy: hierarchy,
      itemKey: key,
      title: title,
      hint: child.hint
    )
  }

  private func reload() async {
    loading = true
    defer { loading = false }
    page = await store.loadLibrary(
      hierarchy: hierarchy,
      itemKey: itemKey,
      input: input,
      childTitled: openChild
    )
  }
}

private struct TVLibraryCategoryCard: View {
  let entry: LibraryEntry
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Image(systemName: entry.symbol)
        .font(.system(size: 34, weight: .medium))
        .foregroundStyle(isFocused ? Palette.onAccent : Palette.accent)
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(isFocused ? Color.white : Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      Text(entry.title)
        .font(.headline)
        .foregroundStyle(isFocused ? Palette.primary : Palette.accent)
        .lineLimit(2)
    }
    .padding(6)
  }
}

private struct TVBrowseCard: View {
  let title: String
  var subtitle: String?
  var image: Data?
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      CoverArt(title: title, image: image, corner: 12)
        .aspectRatio(1, contentMode: .fit)
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(isFocused ? Color.white : .clear, lineWidth: 4)
        }
        .scaleEffect(isFocused ? 1.05 : 1)
      Text(title)
        .font(.headline)
        .foregroundStyle(isFocused ? Palette.primary : Palette.accent)
        .lineLimit(2)
      if let subtitle {
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(Palette.secondary)
          .lineLimit(1)
      }
    }
    .padding(6)
  }
}
