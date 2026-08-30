import SwiftUI

struct TVLibraryView: View {
  @Environment(MockStore.self) private var store
  @State private var selected: LibraryEntry?

  var body: some View {
    NavigationSplitView {
      List(store.library, selection: $selected) { entry in
        Label(entry.title, systemImage: entry.symbol)
          .tag(entry)
          .font(.title3)
      }
      .navigationTitle("Library")
      .onAppear {
        if selected == nil {
          selected = store.library.first
        }
      }
      .onChange(of: store.libraryLaunchHierarchy) { _, hierarchy in
        guard let hierarchy else { return }
        selected = store.library.first { $0.hierarchy == hierarchy }
          ?? LibraryEntry(id: hierarchy, title: hierarchy, symbol: "music.note", hierarchy: hierarchy)
        store.libraryLaunchHierarchy = nil
      }
    } detail: {
      NavigationStack {
        Group {
          if let selected {
            TVBrowsePageView(
              hierarchy: selected.hierarchy,
              title: selected.title
            )
            .id(selected.id)
          } else {
            ContentUnavailableView("Library", systemImage: "square.stack")
          }
        }
        .navigationDestination(for: BrowseNode.self) { node in
          TVBrowsePageView(
            hierarchy: node.hierarchy ?? selected?.hierarchy ?? "browse",
            itemKey: node.itemKey,
            title: node.title
          )
        }
      }
    }
    .navigationSplitViewStyle(.balanced)
  }
}

struct TVBrowsePageView: View {
  @Environment(MockStore.self) private var store
  let hierarchy: String
  var itemKey: String?
  var title: String
  var input: String?

  @State private var page = BrowsePage(title: "", items: [])
  @State private var loading = true
  @State private var prompt = ""

  var body: some View {
    Group {
      if loading {
        ProgressView()
          .tint(Palette.accent)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if page.items.isEmpty {
        ContentUnavailableView(
          "Nothing here",
          systemImage: "music.note",
          description: Text("Try another category.")
        )
      } else {
        ScrollView {
          LazyVGrid(
            columns: [
              GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 28),
            ],
            spacing: 28
          ) {
            ForEach(page.items) { child in
              cell(child)
            }
          }
          .padding(40)
        }
      }
    }
    .navigationTitle(page.title.isEmpty ? title : page.title)
    .task(id: "\(hierarchy)|\(itemKey ?? "")|\(input ?? "")") { await reload() }
  }

  @ViewBuilder
  private func cell(_ child: BrowseNode) -> some View {
    if child.isPrompt {
      VStack(alignment: .leading, spacing: 12) {
        TextField(child.title, text: $prompt)
          .font(.title3)
          .padding(16)
          .background(Palette.surface)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        NavigationLink {
          TVBrowsePageView(
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
      .frame(maxWidth: .infinity, alignment: .leading)
    } else if child.hint == "action" {
      Button { run(child, title: child.title) } label: {
        coverLabel(child)
      }
      .buttonStyle(.plain)
    } else if child.itemKey != nil, child.hint != "action_list" {
      NavigationLink(value: child) {
        coverLabel(child)
      }
      .buttonStyle(.plain)
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
        coverLabel(child)
      }
      .buttonStyle(.plain)
      .contextMenu {
        ForEach(child.actions, id: \.self) { action in
          Button(action) { run(child, title: action) }
        }
      }
    }
  }

  private func coverLabel(_ child: BrowseNode) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      CoverArt(
        title: child.title,
        image: store.imageData(for: child.imageKey),
        corner: 12
      )
      .aspectRatio(1, contentMode: .fit)
      Text(child.title)
        .font(.headline)
        .lineLimit(2)
      if let subtitle = child.subtitle {
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(Palette.secondary)
          .lineLimit(1)
      }
    }
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
    page = await store.loadLibrary(hierarchy: hierarchy, itemKey: itemKey, input: input)
  }
}
