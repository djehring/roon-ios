import SwiftUI

@MainActor @Observable
final class CinemaMusicBasket {
  struct Selection { let path: CinemaMusicPath; let tracks: [CapsuleTrack] }
  var selections: [Selection] = []
  var loading = false
  var failure: String?
  var tracks: [CapsuleTrack] { selections.flatMap(\.tracks) }
  func contains(_ path: CinemaMusicPath) -> Bool { selections.contains { $0.path == path } }

  func toggle(_ path: CinemaMusicPath, store: MockStore) async {
    guard !loading else { return }
    if contains(path) { selections.removeAll { $0.path == path }; return }
    loading = true; failure = nil
    defer { loading = false }
    do {
      let tracks = try await store.cinemaImport(path)
      guard !Task.isCancelled else { return }
      selections.append(Selection(path: path, tracks: tracks))
    } catch is CancellationError { }
    catch { failure = error.localizedDescription }
  }
}

struct CinemaMusicPicker: View {
  let draft: CinemaMusicDraft
  let title: String
  @Environment(MockStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var basket = CinemaMusicBasket()
  @State private var navigation: [CinemaMusicPath] = []
  @State private var query = ""

  var body: some View {
    NavigationStack(path: $navigation) {
      List {
        Section {
          HStack {
            TextField("Search Roon", text: $query).onSubmit(search)
              .accessibilityIdentifier("cinema-music-search")
            Button("Search", action: search).disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
        Section("Browse") {
          NavigationLink("Albums", value: CinemaMusicPath(hierarchy: "albums"))
            .accessibilityIdentifier("cinema-browse-albums")
          NavigationLink("Playlists", value: CinemaMusicPath(hierarchy: "playlists"))
            .accessibilityIdentifier("cinema-browse-playlists")
          Button("Current queue · \(store.selectedZone.name)") {
            Task {
              guard !basket.loading else { return }
              basket.loading = true; basket.failure = nil
              defer { basket.loading = false }
              do {
                let queue = try await store.cinemaQueue()
                let path = CinemaMusicPath(hierarchy: "queue", query: store.selectedZoneId)
                basket.selections.removeAll { $0.path == path }
                basket.selections.append(.init(path: path, tracks: queue.tracks))
              } catch { basket.failure = error.localizedDescription }
            }
          }
        }
        .listRowBackground(Palette.surface)
      }
      .navigationTitle("Add music")
      .navigationDestination(for: CinemaMusicPath.self) { path in
        CinemaMusicBrowser(path: path, basket: basket, existing: draft.tracks, open: { navigation.append($0) })
      }
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
      #if os(iOS)
      .scrollContentBackground(.hidden)
      #endif
      .background(Palette.background)
    }
    .safeAreaInset(edge: .bottom) { footer }
    .tint(Palette.accent).preferredColorScheme(.dark)
  }

  private var footer: some View {
    VStack(spacing: 8) {
      if basket.loading { ProgressView("Loading music…") }
      if let failure = basket.failure { Text(failure).font(.footnote).foregroundStyle(.red) }
      Text("Add to \(title)").font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
      Button("Add \(basket.tracks.count) tracks") {
        do { try draft.append(basket.tracks); dismiss() }
        catch { basket.failure = error.localizedDescription }
      }
      .buttonStyle(CinemaButtonStyle(prominent: true))
      .disabled(basket.tracks.isEmpty || basket.loading)
      .accessibilityIdentifier("cinema-confirm-add")
    }.padding(CinemaLayout.inset).background(Palette.background)
  }

  private func search() {
    let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }
    navigation.append(CinemaMusicPath(hierarchy: "search", query: value))
  }
}

private struct CinemaMusicBrowser: View {
  let path: CinemaMusicPath
  let basket: CinemaMusicBasket
  let existing: [CapsuleTrack]
  let open: (CinemaMusicPath) -> Void
  @Environment(MockStore.self) private var store
  @State private var page: CinemaMusicPage?
  @State private var failure: String?
  @State private var loading = true
  @State private var query = ""

  var body: some View {
    List {
      if loading { ProgressView("Loading music…") }
      if let failure {
        Text(failure).foregroundStyle(.red)
        Button("Retry") { Task { await load() } }
      }
      if let page {
        if page.canImport {
          Button {
            Task { await basket.toggle(path, store: store) }
          } label: {
            Label(basket.contains(path) ? "Selected \(page.kind)" : "Add \(page.kind)",
              systemImage: basket.contains(path) ? "checkmark.circle.fill" : "plus.circle")
          }
          .disabled(basket.loading).accessibilityIdentifier("cinema-add-collection")
        }
        ForEach(page.items) { item in
          if item.kind == "track" {
            Button {
              Task {
                await basket.toggle(item.path, store: store)
                if basket.failure?.contains("Choose a recording") == true {
                  basket.failure = nil
                  open(item.path)
                }
              }
            } label: {
              HStack {
                label(item)
                Spacer()
                Image(systemName: basket.contains(item.path) ? "checkmark.circle.fill" : "plus.circle")
                  .foregroundStyle(Palette.accent)
              }
            }.disabled(basket.loading)
          } else if item.kind == "search" {
            HStack {
              TextField(item.title, text: $query)
              NavigationLink("Search", value: searchPath(item.path)).disabled(query.isEmpty)
            }
          } else {
            NavigationLink(value: item.path) { label(item) }
          }
        }.listRowBackground(Palette.surface)
        if page.items.isEmpty && !page.canImport { Text("No matching music found.").foregroundStyle(Palette.secondary) }
      }
    }
    #if os(iOS)
    .scrollContentBackground(.hidden)
    #endif
    .background(Palette.background)
    .navigationTitle(page?.title ?? "Music")
    .task(id: path) { await load() }
  }

  private func label(_ item: CinemaMusicItem) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(item.title).foregroundStyle(Palette.primary).lineLimit(2)
      if let subtitle = item.subtitle { Text(subtitle).font(.caption).foregroundStyle(Palette.secondary).lineLimit(2) }
      if item.kind == "track", existing.contains(where: { $0.roonPath == item.path }) {
        Text("Already included · select to add again").font(.caption).foregroundStyle(Palette.accent)
      }
    }.frame(minHeight: CinemaLayout.controlHeight, alignment: .leading)
  }

  private func searchPath(_ path: CinemaMusicPath) -> CinemaMusicPath {
    var path = path
    if let last = path.steps.indices.last { path.steps[last].input = query }
    return path
  }

  private func load() async {
    loading = true; failure = nil
    defer { loading = false }
    do {
      let result = try await store.cinemaBrowse(path)
      guard !Task.isCancelled else { return }
      page = result
    } catch is CancellationError { }
    catch { failure = error.localizedDescription }
  }
}
