import SwiftUI

struct AISearchView: View {
  var regularWidth = false
  @Environment(MockStore.self) private var store
  @State private var recorder = VoiceRecorder()
  @State private var selectedIDs = Set<String>()
  @State private var details: MusicDiscoveryResult?
  @FocusState private var queryFocused: Bool

  var body: some View {
    // Previously saved Siri results remain reviewable until a new search starts.
    if store.discoveryResponse == nil && !store.aiResults.isEmpty {
      LegacyAISearchView(regularWidth: regularWidth)
    } else {
      content
        .sheet(item: $details) { item in
          NavigationStack { MusicDiscoveryDetail(result: item) }
        }
        .onChange(of: store.discoveryResponse?.results.map(\.id), initial: true) { _, _ in
          selectedIDs = Set(results.filter(\.canPlay).map(\.id))
        }
        .toolbar {
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { queryFocused = false }
          }
        }
    }
  }

  private var results: [MusicDiscoveryResult] { store.discoveryResponse?.results ?? [] }

  private var content: some View {
    VStack(spacing: 14) {
      queryControls
      if let error = store.aiError {
        Text(error).font(.callout).foregroundStyle(.red).padding(.horizontal)
          .accessibilityIdentifier("discovery-error")
      }
      if store.aiLoading {
        DiscoverySearching(query: store.aiQuery, cancel: store.cancelAISearch)
      } else if let response = store.discoveryResponse {
        Text(response.message).font(.footnote).foregroundStyle(Palette.secondary)
          .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
        if response.mode == "tracks", results.contains(where: \.canPlay) {
          Button(store.aiPlaying ? "Waiting for Roon…" : "Play selected tracks") {
            store.playDiscoveryResults(results.filter { selectedIDs.contains($0.id) })
          }.buttonStyle(GoldFillButton()).padding(.horizontal)
            .disabled(store.aiPlaying || selectedIDs.isEmpty)
          Button("Create Cinema") {
            store.createDiscoveryCinema(results.filter { selectedIDs.contains($0.id) })
          }.disabled(store.aiPlaying || selectedIDs.isEmpty)
        }
        if results.isEmpty {
          ContentUnavailableView("No verified recordings", systemImage: "music.note.list",
            description: Text("Try a performer or album title, or change the search mode."))
        } else {
          ScrollView {
            LazyVStack(spacing: 16) {
              ForEach(results) { result in
                resultRow(result)
              }
            }.padding(.horizontal).padding(.bottom, 24)
          }.scrollDismissesKeyboard(.interactively)
        }
      } else {
        ContentUnavailableView("Ask for some music", systemImage: "sparkles",
          description: Text("Try “latest recordings of Elgar’s Enigma Variations” or ask for a song, artist or mood."))
      }
    }.padding(.top, 8)
  }

  private var queryControls: some View {
    @Bindable var store = store
    return VStack(spacing: 12) {
      HStack {
        TextField("What would you like to listen to?", text: $store.aiQuery)
          .padding(12).background(Palette.surface)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .focused($queryFocused).submitLabel(.search).onSubmit(search)
          .accessibilityIdentifier("discovery-query")
          .disabled(store.aiPlaying)
        Button {
          queryFocused = false
          Task {
            do { if let audio = try await recorder.toggle() { store.transcribeAI(audio: audio) } }
            catch { store.aiError = error.localizedDescription }
          }
        } label: {
          Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
            .frame(width: 44, height: 44)
        }.disabled(recorder.isChanging || store.aiLoading || store.aiPlaying)
          .accessibilityLabel(recorder.isRecording ? "Stop voice search recording" : "Record voice search")
        Button("Go", action: search).disabled(!store.canSubmitAISearch || store.aiPlaying)
      }
      Picker("Search for", selection: $store.discoveryMode) {
        ForEach(MusicSearchMode.allCases) { mode in Text(mode.title).tag(mode) }
      }.pickerStyle(.segmented).disabled(store.aiLoading || store.aiPlaying)
        .accessibilityIdentifier("discovery-mode")
    }.padding(.horizontal)
  }

  private func resultRow(_ result: MusicDiscoveryResult) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        CoverArt(title: result.album,
          image: store.imageData(for: result.imageKey), corner: 10)
          .frame(width: regularWidth ? 100 : 72, height: regularWidth ? 100 : 72)
        VStack(alignment: .leading, spacing: 5) {
          Text(result.title).font(.headline)
          Text(result.artist).font(.subheadline).foregroundStyle(Palette.secondary)
          if result.isAlbum {
            if let date = result.dateLabel {
              Text(date).font(.caption).foregroundStyle(Palette.secondary)
            }
            Text("\(result.tracks.count) tracks").font(.caption).foregroundStyle(Palette.tertiary)
          } else if !result.album.isEmpty {
            Text(result.album).font(.caption).foregroundStyle(Palette.secondary)
          }
        }
        Spacer(minLength: 0)
        if !result.isAlbum && result.canPlay {
          Button {
            if !selectedIDs.insert(result.id).inserted { selectedIDs.remove(result.id) }
          } label: {
            Image(systemName: selectedIDs.contains(result.id) ? "checkmark.circle.fill" : "circle")
              .font(.title2).foregroundStyle(Palette.accent)
          }.disabled(store.aiPlaying).accessibilityLabel("Select \(result.title)")
        }
      }
      if let reason = result.reason {
        Label(reason, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Palette.secondary)
      }
      if result.isAlbum {
        HStack {
          Button(store.aiPlaying ? "Waiting for Roon…" : "Play album") {
            store.playDiscoveryResults([result])
          }.buttonStyle(.borderedProminent).tint(Palette.accent)
            .disabled(!result.canPlay || store.aiPlaying)
          Button("Details") { details = result }.buttonStyle(.bordered)
        }
        if result.canPlayWork {
          Button("Play \(result.workTitle ?? "work") only") {
            store.playDiscoveryResults([result], workOnly: true)
          }.font(.subheadline).disabled(store.aiPlaying)
        }
        Button("Create Cinema") { store.createDiscoveryCinema([result]) }
          .font(.subheadline).disabled(!result.canPlay || store.aiPlaying)
      }
    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 14))
      .accessibilityIdentifier("discovery-result-\(result.id)")
  }

  private func search() { queryFocused = false; store.runAISearch() }
}

/// Shown while a search runs, which can take from a few seconds to about a minute.
private struct DiscoverySearching: View {
  let query: String
  let cancel: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var started = Date.now

  var body: some View {
    VStack(spacing: 18) {
      Spacer()
      ZStack {
        if reduceMotion {
          FindingVinyl(size: 96)
        } else {
          TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(started)
            ZStack {
              ForEach(0..<3, id: \.self) { ring in
                // Three rings leave the record a third of a cycle apart and fade as they grow.
                let phase = (elapsed / 2.4 + Double(ring) / 3).truncatingRemainder(dividingBy: 1)
                Circle().stroke(Palette.accent, lineWidth: 2)
                  .scaleEffect(0.5 + 0.5 * phase).opacity(0.8 * (1 - phase))
              }
              FindingVinyl(size: 96)
              // A plain disc shows no rotation, so a pair of highlights turns with it.
              Circle().fill(AngularGradient(
                colors: [.clear, .white.opacity(0.28), .clear, .clear, .white.opacity(0.18), .clear, .clear],
                center: .center))
                .frame(width: 96, height: 96).blendMode(.plusLighter)
                .rotationEffect(.degrees(elapsed * 200))
              Circle().fill(Palette.accent).frame(width: 29, height: 29)
              Circle().fill(Palette.background).frame(width: 8, height: 8)
            }
          }
        }
      }.frame(width: 190, height: 190).accessibilityHidden(true)
      Text("Searching for “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”")
        .font(.headline).multilineTextAlignment(.center).lineLimit(3)
        .accessibilityIdentifier("discovery-loading")
      Text("Finding recordings and checking each one in Roon.")
        .font(.footnote).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
      TimelineView(.periodic(from: started, by: 1)) { context in
        Text("Classical and latest-release searches can take up to a minute.")
          .font(.footnote).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
          .opacity(context.date.timeIntervalSince(started) >= 12 ? 1 : 0)
      }
      Button("Cancel", role: .cancel, action: cancel).buttonStyle(.bordered).controlSize(.large)
        .accessibilityIdentifier("discovery-cancel")
      Spacer()
    }.padding(.horizontal, 24).frame(maxWidth: .infinity)
  }
}

private struct MusicDiscoveryDetail: View {
  let result: MusicDiscoveryResult
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    List {
      Section {
        Text(result.artist)
        if let date = result.dateLabel { Text(date) }
        if let release = result.release {
          if !release.recordingDate.isEmpty { Text("Recorded \(release.recordingDate)") }
          if let url = release.sourceURL { Link("Release information", destination: url) }
        }
      }
      Section("Tracks in album order") {
        ForEach(Array(result.tracks.enumerated()), id: \.offset) { index, track in
          Text("\(index + 1). \(RoonDisplayText.format(track.track))")
        }
      }
    }.navigationTitle(result.title).navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
  }
}
