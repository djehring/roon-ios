import SwiftUI

struct RegularBrowseView: View {
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
  @State private var jump: Character?

  private static let indexedTitles = [
    "Albums", "Artists", "Composers", "My Live Radio", "Playlists", "Tags", "Radios",
  ]
  private let columns = [
    GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 22),
  ]

  var body: some View {
    ZStack(alignment: .trailing) {
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
          ScrollViewReader { proxy in
            ScrollView {
              LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                ForEach(page.items) { child in
                  cell(child)
                    .id(child.id)
                }
              }
              .padding(28)
              .padding(.trailing, showsIndex ? 18 : 0)
            }
            .onChange(of: jump) { _, letter in
              guard let letter else { return }
              if let target = LibraryIndex.jumpTarget(for: letter, in: page.items) {
                withAnimation(Motion.sheet) {
                  proxy.scrollTo(target, anchor: .top)
                }
              }
              jump = nil
            }
          }
        }
      }

      if showsIndex, !page.items.isEmpty {
        indexBar
      }
    }
    .background(Palette.background)
    .navigationTitle(page.title.isEmpty ? title : page.title)
    .navigationDestination(for: BrowseNode.self) { child in
      RegularBrowseView(
        hierarchy: child.hierarchy ?? hierarchy,
        itemKey: child.itemKey,
        title: child.title,
        path: $path
      )
    }
    .task(id: "\(hierarchy)|\(itemKey ?? "")|\(input ?? "")|\(openChild ?? "")") {
      await reload()
    }
    .safeAreaInset(edge: .bottom) {
      if store.isRecordingAction {
        recordingBar
      }
    }
  }

  private var showsIndex: Bool {
    Self.indexedTitles.contains(page.title.isEmpty ? title : page.title)
  }

  @ViewBuilder
  private func cell(_ child: BrowseNode) -> some View {
    if child.isPrompt {
      promptCell(child)
    } else if child.hint == "action" {
      Button {
        run(child, title: child.title)
      } label: {
        coverLabel(child, playIndicator: true)
      }
      .buttonStyle(.plain)
    } else if child.itemKey != nil, isPlaylistContents {
      Button {
        playFromTrack(child)
      } label: {
        coverLabel(child, playIndicator: true)
      }
      .buttonStyle(.plain)
      .contextMenu {
        Button("Play From Here") { playFromTrack(child) }
        ForEach(["Play Now", "Queue", "Play Next"], id: \.self) { action in
          Button(action) { run(child, title: action) }
        }
        NavigationLink(value: child) {
          Text("Open")
        }
      }
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
        if let action = child.actions.first {
          run(child, title: action)
        }
      } label: {
        coverLabel(child, playIndicator: !child.actions.isEmpty)
      }
      .buttonStyle(.plain)
      .disabled(child.actions.isEmpty)
      .contextMenu {
        ForEach(child.actions, id: \.self) { action in
          Button(action) { run(child, title: action) }
        }
      }
    }
  }

  @ViewBuilder
  private func coverLabel(_ child: BrowseNode, playIndicator: Bool = false) -> some View {
    let content = VStack(alignment: .leading, spacing: 10) {
      CoverArt(
        title: child.title,
        image: store.imageData(
          for: child.imageKey,
          pixels: ArtworkCache.gridPixels
        ),
        corner: 12
      )
      .aspectRatio(1, contentMode: .fit)
      .overlay(alignment: .bottomTrailing) {
        if playIndicator {
          Image(systemName: "play.fill")
            .font(.caption.weight(.bold))
            .frame(width: 34, height: 34)
            .background(Palette.accent)
            .foregroundStyle(Palette.onAccent)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            .padding(10)
        }
      }

      Text(child.title)
        .font(.headline)
        .foregroundStyle(Palette.primary)
        .lineLimit(2)
      if let subtitle = child.subtitle, !subtitle.isEmpty {
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(Palette.secondary)
          .lineLimit(2)
      }
    }
    .contentShape(Rectangle())
    .hoverEffect(.lift)

    if let itemKey = child.itemKey {
      content.draggable(
        LibraryDragItem(
          hierarchy: child.hierarchy ?? hierarchy,
          itemKey: itemKey,
          title: child.title,
          hint: child.hint
        )
      )
    } else {
      content
    }
  }

  private func promptCell(_ child: BrowseNode) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(child.title, systemImage: "magnifyingglass")
        .font(.headline)
      TextField(child.title, text: $prompt)
        .textFieldStyle(.roundedBorder)
        .textInputAutocapitalization(.never)
        .submitLabel(.search)
        .onSubmit { submitSearch(child) }
      Button {
        submitSearch(child)
      } label: {
        Text(child.actions.first ?? "Search")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(GoldFillButton(minHeight: 42))
      .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .padding(18)
    .background(Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Palette.hairline, lineWidth: 1)
    }
  }

  private var isPlaylistContents: Bool {
    hierarchy == "playlists" && itemKey != nil
  }

  private func submitSearch(_ child: BrowseNode) {
    guard let query = BrowseSearch.submitted(
      hierarchy: hierarchy,
      child: child,
      prompt: prompt
    ) else { return }
    path.append(query)
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

  private var indexBar: some View {
    VStack(spacing: 1) {
      ForEach(LibraryIndex.letters, id: \.self) { letter in
        Button {
          jump = letter
        } label: {
          Text(String(letter))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.secondary)
            .frame(width: 22, height: 17)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, 6)
    .background(Palette.surface.opacity(0.86))
    .clipShape(Capsule())
    .padding(.trailing, 6)
  }

  private var recordingBar: some View {
    HStack {
      Button("Cancel") { store.cancelRecording() }
      Spacer()
      Label("Recording", systemImage: "record.circle")
        .font(.caption.weight(.semibold))
        .foregroundStyle(Palette.accent)
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
    page = await store.loadLibrary(
      hierarchy: hierarchy,
      itemKey: itemKey,
      input: input,
      childTitled: openChild
    )
  }
}
