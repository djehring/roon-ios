import SwiftUI

extension MockStore {
  func cinemaBrowse(_ path: CinemaMusicPath) async throws -> CinemaMusicPage {
    #if DEBUG
    if let fixture = CinemaMusicFixture.current { return fixture.browse(path) }
    #endif
    try await client.requireCinemaMusicSupport()
    return try await client.browseCinemaMusic(path, zoneId: selectedZoneId)
  }

  func cinemaImport(_ path: CinemaMusicPath) async throws -> [CapsuleTrack] {
    #if DEBUG
    if let fixture = CinemaMusicFixture.current { return fixture.tracks(for: path) }
    #endif
    try await client.requireCinemaMusicSupport()
    return try await client.importCinemaMusic(path, zoneId: selectedZoneId)
  }

  func cinemaQueue() async throws -> CinemaQueueSnapshot {
    #if DEBUG
    if Self.wantsDemoContent {
      let tracks = queue.map { CapsuleTrack(artist: $0.artist, track: $0.title, album: $0.album,
        entryId: UUID().uuidString, imageKey: $0.imageKey) }
      return CinemaQueueSnapshot(title: "\(selectedZone.name) queue", sourceLabel: "From \(selectedZone.name) queue",
        tracks: tracks, includesCurrent: tracks.first?.track == currentTrack?.title)
    }
    #endif
    try await client.requireCinemaMusicSupport()
    return try await client.captureCinemaQueue(zoneId: selectedZoneId)
  }
}

struct CreateCinemaFromMusicButton: View {
  var path: CinemaMusicPath?
  var title: String = "Queue"
  @Environment(MockStore.self) private var store
  @State private var setup: CapsuleSetup?
  @State private var importing = false
  @State private var failure: String?

  var body: some View {
    Button {
      Task { await create() }
    } label: {
      HStack {
        if importing { ProgressView() }
        Label(importing ? "Loading music…" : "Create Cinema", systemImage: "sparkles.tv")
      }.frame(minHeight: CinemaLayout.controlHeight)
    }
    .cinemaPlainButton().foregroundStyle(Palette.accent).disabled(importing)
    .accessibilityIdentifier("cinema-create-from-music")
    .sheet(item: $setup, onDismiss: { store.cinema.finishSetup(client: store.client) }) { setup in
      CapsuleSetupView(setup: setup).id(setup.id)
    }
    .alert("Could not load music", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
      Button("Retry") { Task { await create() } }
      Button("Cancel", role: .cancel) { }
    } message: { Text(failure ?? "") }
  }

  private func create() async {
    importing = true
    defer { importing = false }
    do {
      if let path {
        let tracks = try await store.cinemaImport(path)
        setup = CapsuleSetup(request: CapsuleRequest(title: title, tracks: tracks, sourceLabel: "From \(title)"))
      } else if store.currentTrack == nil && store.queue.isEmpty {
        setup = CapsuleSetup(request: CapsuleRequest(title: "New Cinema", tracks: [], sourceLabel: "Your music"))
      } else {
        let snapshot = try await store.cinemaQueue()
        let tracks = CinemaMusicDraft.identify(snapshot.tracks)
        setup = CapsuleSetup(request: CapsuleRequest(title: snapshot.title, tracks: tracks, sourceLabel: snapshot.sourceLabel),
          currentTrackId: snapshot.includesCurrent ? tracks.first?.entryId : nil)
      }
    } catch { failure = error.localizedDescription }
  }
}

#if DEBUG
/// External UI-test input; this never contacts a paired bridge or modifies real music.
@MainActor struct CinemaMusicFixture: Decodable {
  var tracks: [CapsuleTrack]
  static var current: Self? {
    guard MockStore.wantsDemoContent,
      let data = ProcessInfo.processInfo.environment["ROON_CINEMA_MUSIC_JSON"]?.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(Self.self, from: data)
  }

  func tracks(for path: CinemaMusicPath) -> [CapsuleTrack] {
    if let last = path.steps.last, tracks.contains(where: { $0.track == last.title }) {
      return tracks.filter { $0.track == last.title }
    }
    if path.hierarchy == "search" { return tracks.filter { $0.track.localizedCaseInsensitiveContains(path.query ?? "") } }
    if let album = path.steps.first?.title { return tracks.filter { $0.album == album } }
    return tracks
  }

  func browse(_ path: CinemaMusicPath) -> CinemaMusicPage {
    if path.steps.isEmpty && path.hierarchy != "search" {
      let albums = Array(Set(tracks.map(\.album))).sorted()
      return CinemaMusicPage(title: path.hierarchy == "playlists" ? "Playlists" : "Albums", kind: "list", path: path,
        items: albums.enumerated().map { index, title in
          var child = path; child.steps = [CinemaMusicStep(title: title, index: index)]
          return CinemaMusicItem(title: title, kind: "list", path: child)
        })
    }
    let selection = tracks(for: path)
    return CinemaMusicPage(title: path.steps.last?.title ?? "Search results",
      kind: path.hierarchy == "search" ? "list" : path.hierarchy == "playlists" ? "playlist" : "album", path: path,
      items: selection.enumerated().map { index, track in
        var child = path; child.steps.append(CinemaMusicStep(title: track.track, subtitle: track.artist, index: index))
        return CinemaMusicItem(title: track.track, subtitle: track.artist, kind: "track", path: child)
      })
  }
}
#endif
