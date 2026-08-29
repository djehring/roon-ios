import SwiftUI

struct SearchTabView: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    @Bindable var store = store
    NavigationStack {
      VStack(spacing: 0) {
        Picker("Search", selection: $store.searchSegment) {
          Text("AI").tag(SearchSegment.ai)
          Text("Camera").tag(SearchSegment.camera)
          Text("Story").tag(SearchSegment.story)
        }
        .pickerStyle(.segmented)
        .padding(16)
        Group {
          switch store.searchSegment {
          case .ai: AISearchView()
          case .camera: CameraSearchView()
          case .story: TrackStoryView()
          }
        }
      }
      .background(Palette.background)
      .navigationTitle("Search")
    }
  }
}

struct AISearchView: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    @Bindable var store = store
    VStack(spacing: 12) {
      HStack {
        TextField("What would you like to listen to?", text: $store.aiQuery)
          .textFieldStyle(.plain)
          .padding(12)
          .background(Palette.surface)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        Button {
          store.runAISearch()
        } label: {
          Image(systemName: "mic.fill")
            .frame(width: 44, height: 44)
            .background(Palette.surface)
            .clipShape(Circle())
        }
      }
      .padding(.horizontal, 16)

      if store.aiLoading {
        Spacer()
        ProgressView().tint(Palette.accent)
        Spacer()
      } else {
        List {
          ForEach($store.aiResults) { $track in
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: "line.3.horizontal")
                .foregroundStyle(Palette.tertiary)
              VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                Text("\(track.artist)  ·  \(track.album)")
                  .font(.footnote)
                  .foregroundStyle(Palette.secondary)
                if track.corrected {
                  Label("Album was corrected", systemImage: "sparkle")
                    .font(.caption)
                    .foregroundStyle(Palette.accent)
                }
                if let error = track.error {
                  Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.8))
                }
              }
            }
            .listRowBackground(Palette.surface)
          }
          .onDelete { store.aiResults.remove(atOffsets: $0) }
          .onMove { store.aiResults.move(fromOffsets: $0, toOffset: $1) }
        }
        .scrollContentBackground(.hidden)
        Button("Play selected tracks") {}
          .buttonStyle(GoldFillButton())
          .padding(16)
      }
    }
  }
}

struct CameraSearchView: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    @Bindable var store = store
    VStack(spacing: 16) {
      Button {
        store.hasPhoto.toggle()
        if store.hasPhoto {
          store.recognizedAlbums = MockCatalog.recognized
        } else {
          store.recognizedAlbums = []
        }
      } label: {
        ZStack {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Palette.surface)
            .frame(height: 220)
          if store.hasPhoto {
            CoverArt(title: "Kind of Blue", corner: 12)
              .padding(24)
          } else {
            VStack(spacing: 8) {
              Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(Palette.accent)
              Text("Take or choose a cover")
                .foregroundStyle(Palette.secondary)
            }
          }
        }
      }
      .padding(.horizontal, 16)

      TextField("Album description (optional)", text: $store.cameraHint)
        .padding(12)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)

      if store.recognizedAlbums.isEmpty {
        Button("Recognize album") {
          store.hasPhoto = true
          store.recognizedAlbums = MockCatalog.recognized
        }
        .buttonStyle(GoldFillButton())
        .padding(.horizontal, 16)
      } else {
        List(store.recognizedAlbums) { album in
          HStack {
            CoverArt(title: album.title, corner: 6)
              .frame(width: 48, height: 48)
            VStack(alignment: .leading) {
              Text(album.title)
              Text(album.subtitle ?? "")
                .font(.footnote)
                .foregroundStyle(Palette.secondary)
            }
            Spacer()
            Circle()
              .fill(Palette.accent)
              .frame(width: 8, height: 8)
            Image(systemName: "play.circle.fill")
              .foregroundStyle(Palette.accent)
              .font(.title2)
          }
          .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        Button("Search again") {
          store.hasPhoto = false
          store.recognizedAlbums = []
        }
        .foregroundStyle(Palette.accent)
      }
      Spacer()
    }
  }
}

struct TrackStoryView: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    ScrollView {
      if let track = store.currentTrack {
        VStack(alignment: .leading, spacing: 16) {
          Text("\(track.artist) — \(track.title)")
            .font(.title2.weight(.semibold))
          Text("Kind of Blue, 1959")
            .font(.headline)
            .foregroundStyle(Palette.accent)
          Text(
            """
            Recorded in one marathon session, So What opens Kind of Blue \
            with a modal figure that still defines modern jazz. Miles \
            barely states the theme before Cannonball and Coltrane take \
            the room apart.

            This is mock copy for the prototype. The live app asks the \
            bridge for a track story when OPENAI_API_KEY is set.
            """
          )
          .foregroundStyle(Palette.secondary)
          .lineSpacing(4)
        }
        .padding(20)
      } else {
        ContentUnavailableView(
          "Nothing playing",
          systemImage: "text.book.closed",
          description: Text("Start a track to read its story.")
        )
      }
    }
  }
}

struct SharePreviewView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var query = "Kind of Blue Miles Davis"
  private let results = MockCatalog.recognized

  var body: some View {
    NavigationStack {
      List {
        Section("From Gramophone") {
          Text("The 50 best jazz albums")
          Text("https://www.gramophone.co.uk/…")
            .font(.footnote)
            .foregroundStyle(Palette.secondary)
        }
        Section("Search library") {
          TextField("Search query", text: $query)
        }
        Section("Matches") {
          ForEach(results) { album in
            HStack {
              CoverArt(title: album.title, corner: 6)
                .frame(width: 48, height: 48)
              VStack(alignment: .leading) {
                Text(album.title)
                Text(album.subtitle ?? "")
                  .font(.footnote)
                  .foregroundStyle(Palette.secondary)
              }
              Spacer()
              Button("Play") { dismiss() }
                .foregroundStyle(Palette.accent)
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(Palette.background)
      .navigationTitle("Play from Gramophone")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .presentationBackground(Palette.background)
  }
}
