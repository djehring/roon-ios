import SwiftUI

struct HistoryView: View {
  @Environment(MockStore.self) private var store
  @Environment(\.scenePhase) private var scenePhase
  @State private var history = HistoryStore()
  @State private var kind: HistoryKind = .albums
  @State private var room = ""
  @State private var visible = false
  @State private var choosingRoom = false

  private var connection: String {
    "\(store.client.host):\(store.client.port)|\(store.client.storedClientId ?? "")|\(store.historyConnectionRevision)"
  }
  private var taskKey: String { "\(connection)|\(kind.rawValue)|\(room)|\(scenePhase)|\(visible)" }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        #if os(tvOS)
        Text("Recently played").font(.title2).foregroundStyle(Palette.primary)
        #endif
        controls
        Text("Listening recorded by your bridge, kept for up to 14 days.")
          .font(.footnote).foregroundStyle(Palette.secondary)
        if let failure = history.failure {
          VStack(alignment: .leading, spacing: 8) {
            Text(history.unsupported ? "Bridge update required" : "Couldn’t refresh history").font(.headline)
            Text(failure).font(.subheadline)
            if !history.items.isEmpty { Text("These entries may be out of date.").font(.caption) }
            Button("Try Again") { Task { await load() } }
          }.foregroundStyle(Palette.secondary).accessibilityIdentifier("history-error")
        }
        if let status = history.status { Text(status).font(.footnote).foregroundStyle(Palette.secondary) }
        if history.loading && history.items.isEmpty {
          ProgressView("Loading history…").frame(maxWidth: .infinity)
        } else if history.items.isEmpty && history.failure == nil {
          ContentUnavailableView("No recent listening yet", systemImage: "clock",
            description: Text("Music will appear here as it plays while your bridge is connected to Roon."))
            .accessibilityIdentifier("history-empty")
        } else if kind == .albums {
          albumGrid
        } else {
          tracks
        }
        if history.nextCursor != nil {
          Button(history.loading ? "Loading…" : "Load more") { Task { await load(more: true) } }
            .disabled(history.loading).accessibilityIdentifier("history-more")
        }
      }.padding(24)
    }
    .background(Palette.background)
    .navigationTitle("Recently played")
    #if os(tvOS)
    .toolbar(.hidden, for: .navigationBar)
    #endif
    .accessibilityIdentifier("history-screen")
    .onAppear { visible = true }
    .onDisappear { visible = false }
    .task(id: taskKey) {
      guard visible, scenePhase == .active else { return }
      await load()
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(30)) } catch { return }
        guard !Task.isCancelled else { return }
        await load()
      }
    }
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 14) {
      #if os(tvOS)
      HStack(spacing: 20) {
        ForEach(HistoryKind.allCases, id: \.self) { option in
          Button { kind = option } label: {
            HistoryTVControlLabel(title: option.title, symbol: kind == option ? "checkmark.circle.fill" : "circle")
          }.tvUnplated().accessibilityIdentifier("history-kind-\(option.rawValue)")
        }
      }.focusSection()
      #else
      Picker("History view", selection: $kind) {
        ForEach(HistoryKind.allCases, id: \.self) { Text($0.title).tag($0) }
      }.pickerStyle(.segmented).accessibilityIdentifier("history-kind")
      #endif
      HStack {
        #if os(tvOS)
        Button { choosingRoom = true } label: {
          HistoryTVControlLabel(title: history.rooms.first(where: { $0.id == room })?.name ?? (room.isEmpty ? "All rooms" : "Previous room"), symbol: "line.3.horizontal.decrease")
        }.tvUnplated()
          .confirmationDialog("Filter by room", isPresented: $choosingRoom) {
            Button("All rooms") { room = "" }
            ForEach(history.rooms) { candidate in
              Button(candidate.name) { room = candidate.id }
            }
          }
        #else
        Picker("Room", selection: $room) {
          Text("All rooms").tag("")
          ForEach(history.rooms) { Text($0.name).tag($0.id) }
          if !room.isEmpty && !history.rooms.contains(where: { $0.id == room }) {
            Text("Previous room").tag(room)
          }
        }.accessibilityIdentifier("history-room")
        #endif
        Spacer()
        #if os(tvOS)
        Button { Task { await load() } } label: {
          HistoryTVControlLabel(title: "Refresh", symbol: "arrow.clockwise")
        }.tvUnplated().disabled(history.loading).accessibilityIdentifier("history-refresh")
        #else
        Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
          .disabled(history.loading).accessibilityIdentifier("history-refresh")
        #endif
      }
    }
  }

  private var albumGrid: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: albumWidth), spacing: 20)], spacing: 24) {
      ForEach(history.items, id: \.albumId) { entry in
        NavigationLink {
          HistorySelectionView(entry: entry, kind: .albums)
        } label: {
          VStack(alignment: .leading, spacing: 8) {
            CoverArt(title: entry.album, image: store.imageData(for: entry.imageKey, pixels: ArtworkCache.gridPixels), corner: 12)
              .aspectRatio(1, contentMode: .fit)
            Text(entry.album).font(.headline).lineLimit(2)
            Text(entry.artist).font(.subheadline).foregroundStyle(Palette.secondary).lineLimit(2)
            Text(entry.observedAt, style: .relative).font(.caption).foregroundStyle(Palette.secondary)
          }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }.buttonStyle(.plain)
          .accessibilityIdentifier("history-album-\(entry.id)")
      }
    }
  }

  private var albumWidth: CGFloat {
    #if os(tvOS)
    240
    #else
    145
    #endif
  }

  private var days: [Date] {
    Array(Set(history.items.map { Calendar.current.startOfDay(for: $0.observedAt) })).sorted(by: >)
  }

  private var tracks: some View {
    LazyVStack(alignment: .leading, spacing: 12) {
      ForEach(days, id: \.self) { day in
        Text(day, format: .dateTime.weekday(.wide).month().day()).font(.headline).padding(.top, 8)
        ForEach(history.items.filter { Calendar.current.isDate($0.observedAt, inSameDayAs: day) }) { entry in
          NavigationLink { HistorySelectionView(entry: entry, kind: .tracks) } label: {
            HStack(spacing: 14) {
              CoverArt(title: entry.title, image: store.imageData(for: entry.imageKey), corner: 6)
                .frame(width: 56, height: 56)
              VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.headline)
                Text([entry.artist, entry.album].filter { !$0.isEmpty }.joined(separator: " · "))
                  .font(.subheadline).foregroundStyle(Palette.secondary)
                Text("\(entry.room) · \(entry.observedAt.formatted(date: .omitted, time: .shortened))")
                  .font(.caption).foregroundStyle(Palette.secondary)
              }
              Spacer(minLength: 0)
              Image(systemName: "chevron.right").foregroundStyle(Palette.secondary)
            }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
          }.buttonStyle(.plain).accessibilityIdentifier("history-track-\(entry.id)")
        }
      }
    }
  }

  private func load(more: Bool = false) async {
    #if DEBUG
    if MockStore.wantsDemoContent {
      await history.load(client: HistoryDemoClient(), connection: connection, kind: kind, room: room, more: more)
      return
    }
    #endif
    await history.load(client: store.client, connection: connection, kind: kind, room: room, more: more)
  }
}

#if os(tvOS)
private struct HistoryTVControlLabel: View {
  let title: String
  let symbol: String
  @Environment(\.isFocused) private var isFocused
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Label(title, systemImage: symbol)
      .font(.system(size: 24, weight: .semibold))
      .padding(.horizontal, 24).frame(minHeight: 60)
      .foregroundStyle(Palette.onAccent)
      .background(isFocused ? Color.white : Palette.accent)
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .opacity(isEnabled ? 1 : 0.5)
  }
}
#endif

struct HistorySelectionView: View {
  let entry: HistoryEntry
  let kind: HistoryKind
  @Environment(MockStore.self) private var store
  @State private var resolution: HistoryResolution?
  @State private var failure: String?

  var body: some View {
    List {
      #if os(tvOS)
      Text(kind == .albums ? entry.album : entry.title).font(.title2).foregroundStyle(Palette.primary)
      #endif
      if let failure {
        Text(failure)
        Button("Try Again") { Task { await resolve() } }
      } else if let resolution {
        Text(resolution.message).foregroundStyle(Palette.secondary)
        ForEach(Array(resolution.choices.enumerated()), id: \.element.id) { index, choice in
          NavigationLink { HistoryMusicView(path: choice.path, title: choice.title) } label: {
            VStack(alignment: .leading, spacing: 6) {
              Text(RoonDisplayText.format(choice.title))
              if let subtitle = choice.subtitle { Text(RoonDisplayText.format(subtitle)).font(.subheadline).foregroundStyle(Palette.secondary) }
            }
          }.accessibilityIdentifier("history-choice-\(index)")
        }
      } else { ProgressView("Finding music in Roon…") }
    }
    .navigationTitle(kind == .albums ? entry.album : entry.title)
    #if os(tvOS)
    .toolbar(.hidden, for: .navigationBar)
    #endif
    .task { await resolve() }
  }

  private func resolve() async {
    failure = nil
    do {
      #if DEBUG
      if MockStore.wantsDemoContent { resolution = HistoryDemoClient.resolution(entry: entry, kind: kind); return }
      #endif
      let result = try await store.client.resolveHistory(entry, kind: kind, zoneId: store.selectedZoneId)
      guard !Task.isCancelled else { return }
      resolution = result
    } catch is CancellationError { }
    catch { if !Task.isCancelled { failure = error.localizedDescription } }
  }
}

struct HistoryMusicView: View {
  let path: CinemaMusicPath
  let title: String
  @Environment(MockStore.self) private var store
  @State private var page: CinemaMusicPage?
  @State private var failure: String?

  var body: some View {
    List {
      #if os(tvOS)
      Text(RoonDisplayText.format(title)).font(.title2).foregroundStyle(Palette.primary)
      #endif
      if let failure {
        Text(failure)
        Button("Try Again") { Task { await load() } }
      }
      if let page {
        if page.canImport {
          Section {
            ForEach(["Play Now", "Play Next", "Queue"], id: \.self) { action in
              Button(action) { store.playHistory(path: path, action: action) }
                .disabled(store.selectedZoneId.isEmpty)
                .accessibilityIdentifier("history-\(action)")
            }
          } header: {
            Text("Play in \(store.selectedZone.name)").foregroundStyle(Palette.secondary)
          }
        }
        ForEach(page.items.filter { $0.kind != "search" }) { child in
          NavigationLink { HistoryMusicView(path: child.path, title: child.title) } label: {
            VStack(alignment: .leading) {
              Text(RoonDisplayText.format(child.title))
              if let subtitle = child.subtitle { Text(RoonDisplayText.format(subtitle)).font(.subheadline).foregroundStyle(Palette.secondary) }
            }
          }
        }
      } else if failure == nil { ProgressView("Loading music…") }
    }
    .navigationTitle(RoonDisplayText.format(title))
    #if os(tvOS)
    .toolbar(.hidden, for: .navigationBar)
    #endif
    .task(id: path) { await load() }
  }

  private func load() async {
    failure = nil
    do {
      #if DEBUG
      if MockStore.wantsDemoContent { page = HistoryDemoClient.browse(path); return }
      #endif
      let result = try await store.client.browseHistoryMusic(path, zoneId: store.selectedZoneId)
      guard !Task.isCancelled else { return }
      page = result
    } catch is CancellationError { }
    catch { if !Task.isCancelled { failure = error.localizedDescription } }
  }
}
