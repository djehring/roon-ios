import SwiftUI

struct CinemaPresentation: ViewModifier {
  @Environment(MockStore.self) private var store
  @State private var viewer: TimeCapsule?
  @State private var libraryIsActive = false

  func body(content: Content) -> some View {
    @Bindable var cinema = store.cinema
    content
      .sheet(item: $cinema.setup, onDismiss: { cinema.finishSetup(client: store.client) }) { setup in
        CapsuleSetupView(setup: setup)
      }
      .fullScreenCover(isPresented: $cinema.showingLibrary, onDismiss: {
        libraryIsActive = false
        viewer = cinema.presented
      }) {
        CinemaLibraryView().onAppear { libraryIsActive = true }
      }
      .fullScreenCover(item: $viewer, onDismiss: {
        cinema.presented = nil
        if cinema.libraryAfterViewer {
          cinema.libraryAfterViewer = false
          cinema.showingLibrary = true
        }
      }) { capsule in
        let resolved = cinema.preparation?.resolve(capsule) ?? capsule
        CinemaView(capsule: resolved).id(resolved.id + resolved.createdAt)
          .screenStaysAwake()
      }
      .onAppear { viewer = cinema.presented }
      .onChange(of: cinema.presented?.id) { _, _ in
        if !libraryIsActive && !cinema.showingLibrary { viewer = cinema.presented }
      }
  }
}

struct CinemaLibraryView: View {
  @Environment(MockStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var editing: CapsuleSetup?
  @State private var deleting: TimeCapsule?
  @State private var collapsed = false

  private var items: [TimeCapsule] { store.cinema.items }
  private var selected: TimeCapsule? {
    items.first { $0.id == store.cinema.selectedId } ?? items.first
  }

  var body: some View {
    GeometryReader { geometry in
      let wide = CinemaLayout.isTV || geometry.size.width >= 760
      VStack(spacing: 0) {
        header(wide: wide)
        Divider()
        if items.isEmpty {
          if store.cinema.loading { ProgressView("Loading playlists…").frame(maxWidth: .infinity, maxHeight: .infinity) }
          else {
            ContentUnavailableView("Your playlists, with pictures", systemImage: "photo.on.rectangle.angled",
              description: Text("Search for music, then choose Set up Cinema to save a playlist with pictures."))
          }
        } else if wide {
          HStack(spacing: 0) {
            playlistList(wide: true)
              .frame(width: min(CinemaLayout.isTV ? 430 : 380, geometry.size.width * 0.35))
            Divider()
            if let selected {
              ScrollView {
                CinemaPlaylistDetail(capsule: selected, edit: { edit(selected) }, delete: { deleting = selected })
                  .padding(.horizontal, CinemaLayout.isTV ? 40 : CinemaLayout.inset)
                  .padding(.vertical, CinemaLayout.isTV ? 24 : CinemaLayout.inset)
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .cinemaFocusSection()
            }
          }
        } else {
          playlistList(wide: false)
          Divider()
          CinemaRoomButton().padding(.horizontal, 20)
        }
        if let error = store.cinema.error {
          HStack {
            Image(systemName: "exclamationmark.triangle")
            Text(error).font(.footnote).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Retry") { Task { await store.cinema.load(client: store.client) } }
          }
          .foregroundStyle(Palette.accent).padding(16)
        }
      }
    }
    .background(Palette.background).foregroundStyle(Palette.primary).preferredColorScheme(.dark)
    .tint(Palette.accent)
    .fullScreenCover(item: $editing, onDismiss: { store.cinema.finishSetup(client: store.client) }) { setup in
      CapsuleSetupView(setup: setup)
    }
    .alert("Delete Cinema item?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      presenting: deleting) { capsule in
      Button("Delete", role: .destructive) {
        Task { _ = await store.cinema.remove(capsule, client: store.client) }
      }
      Button("Cancel", role: .cancel) { }
    } message: { capsule in
      Text("Delete “\(capsule.title)” and its saved playlist and pictures? Your original music and photos will remain.")
    }
    .task { await store.cinema.load(client: store.client) }
    .onChange(of: store.cinema.selectedId) { _, _ in collapsed = false }
    #if os(tvOS)
    .onExitCommand { dismiss() }
    #endif
  }

  private func header(wide: Bool) -> some View {
    HStack(alignment: .center, spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Cinema").font(.system(size: CinemaLayout.isTV ? 48 : 34, weight: .bold))
          .accessibilityAddTraits(.isHeader).foregroundStyle(Palette.primary)
        Text("Your playlists, with pictures").font(CinemaLayout.isTV ? .title3 : .subheadline)
          .foregroundStyle(Palette.secondary)
      }
      Spacer(minLength: 8)
      if wide { CinemaRoomButton() }
      Button { Task { await store.cinema.load(client: store.client) } } label: {
        Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44)
      }
      .accessibilityLabel("Refresh playlists").disabled(store.cinema.loading)
      Button("Done") { dismiss() }.frame(minHeight: 44)
    }
    .buttonStyle(.plain)
    .foregroundStyle(Palette.accent)
    .padding(.horizontal, CinemaLayout.isTV ? 56 : 20)
    .padding(.vertical, CinemaLayout.isTV ? 24 : 16)
  }

  private func playlistList(wide: Bool) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        Text("\(items.count) PLAYLIST\(items.count == 1 ? "" : "S")")
          .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Palette.secondary)
          .padding(.horizontal, 20).padding(.vertical, 20)
        ForEach(items) { capsule in
          let expanded = selected?.id == capsule.id && !collapsed
          VStack(spacing: 0) {
            Button {
              if !wide && selected?.id == capsule.id { collapsed.toggle() }
              else { store.cinema.selectedId = capsule.id; collapsed = false }
            } label: {
              CinemaPlaylistRow(capsule: capsule, selected: selected?.id == capsule.id,
                expanded: expanded, compact: !wide)
            }
            .cinemaPlainButton()
            .accessibilityIdentifier("cinema-item-\(capsule.id)")
            if !wide && expanded {
              CinemaPlaylistActions(capsule: capsule, compact: true,
                edit: { edit(capsule) }, delete: { deleting = capsule })
                .padding(.horizontal, 20).padding(.bottom, 16)
                .background(Palette.surface)
            }
          }
          Divider().padding(.horizontal, 20)
        }
      }
    }
    .cinemaFocusSection()
    .refreshable { await store.cinema.load(client: store.client) }
  }

  private func edit(_ capsule: TimeCapsule) {
    editing = CapsuleSetup(request: capsule.request, original: capsule)
  }
}

private struct CinemaPlaylistRow: View {
  let capsule: TimeCapsule
  let selected: Bool
  let expanded: Bool
  let compact: Bool
  @Environment(MockStore.self) private var store
  @Environment(\.isFocused) private var focused

  var body: some View {
    HStack(spacing: 16) {
      CinemaArtwork(capsule: capsule)
        .frame(width: CinemaLayout.thumbnail, height: CinemaLayout.thumbnail)
        .clipShape(RoundedRectangle(cornerRadius: 6))
      VStack(alignment: .leading, spacing: 6) {
        Text(capsule.title).font(CinemaLayout.isTV ? .system(size: 24, weight: .semibold) : .headline)
          .lineLimit(2).multilineTextAlignment(.leading)
        Text("\(capsule.request.tracks.count) tracks · \(status)")
          .font(CinemaLayout.isTV ? .system(size: 19) : .caption)
          .foregroundStyle(focused ? Color.black.opacity(0.7) : Palette.secondary)
          .lineLimit(2).multilineTextAlignment(.leading)
        if capsule.isPersonal {
          Text("On this device").font(.caption2).foregroundStyle(Palette.secondary)
        }
      }
      Spacer(minLength: 0)
      if store.cinema.isUpdating(capsule) { ProgressView().tint(focused ? .black : Palette.accent) }
      else if compact { Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption) }
    }
    .padding(.horizontal, 20).padding(.vertical, CinemaLayout.isTV ? 20 : 14)
    .foregroundStyle(focused ? .black : Palette.primary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(focused ? .white : selected ? Palette.surface : .clear)
    .overlay(alignment: .leading) { if selected { Rectangle().fill(Palette.accent).frame(width: 4) } }
    .contentShape(Rectangle())
  }

  private var status: String {
    if store.cinema.isUpdating(capsule) { return "Updating pictures…" }
    if store.cinema.failure(for: capsule) != nil { return "Update failed" }
    return "\(capsule.montageFrames.count) pictures"
  }
}

private struct CinemaPlaylistDetail: View {
  let capsule: TimeCapsule
  let edit: () -> Void
  let delete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      if CinemaLayout.isTV {
        CinemaArtwork(capsule: capsule).frame(height: 300)
          .clipShape(RoundedRectangle(cornerRadius: 8))
      } else {
        CinemaArtwork(capsule: capsule).aspectRatio(2, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      VStack(alignment: .leading, spacing: 8) {
        Text(capsule.title).font(.system(size: CinemaLayout.isTV ? 38 : 30, weight: .bold))
          .lineLimit(CinemaLayout.isTV ? 2 : nil)
          .accessibilityAddTraits(.isHeader)
        Text("\(capsule.request.tracks.count) tracks · \(capsule.montageFrames.count) pictures")
          .foregroundStyle(Palette.secondary)
        if !capsule.contextLabel.isEmpty {
          Text(capsule.contextLabel).font(.subheadline).foregroundStyle(Palette.secondary)
            .lineLimit(CinemaLayout.isTV ? 1 : nil)
        }
      }
      CinemaPlaylistActions(capsule: capsule, compact: false, edit: edit, delete: delete)
      #if !os(tvOS)
      Divider().padding(.top, 8)
      Text("PLAYLIST").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Palette.secondary)
      ForEach(Array(capsule.request.tracks.enumerated()), id: \.offset) { index, track in
        HStack(spacing: 16) {
          Text("\(index + 1)").font(.subheadline.monospacedDigit()).foregroundStyle(Palette.secondary).frame(width: 24)
          VStack(alignment: .leading, spacing: 4) {
            Text(track.track).font(.body)
            Text(track.artist).font(.subheadline).foregroundStyle(Palette.secondary)
          }
          Spacer()
        }.padding(.vertical, 6)
      }
      #endif
    }
  }
}

private struct CinemaPlaylistActions: View {
  let capsule: TimeCapsule
  let compact: Bool
  let edit: () -> Void
  let delete: () -> Void
  @Environment(MockStore.self) private var store

  private var updating: Bool { store.cinema.isUpdating(capsule) }
  private var unsaved: Bool { store.cinema.preparation?.placeholder.id == capsule.id }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let failure = store.cinema.failure(for: capsule) {
        Label(failure, systemImage: "exclamationmark.triangle")
          .font(.subheadline).foregroundStyle(Palette.accent)
        Button("Retry picture update", systemImage: "arrow.clockwise") { store.cinema.retry(client: store.client) }
          .buttonStyle(CinemaButtonStyle()).disabled(store.cinema.preparing)
      }
      if compact { VStack(spacing: 10) { playback } }
      else { ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 16) { playback }
        VStack(spacing: 12) { playback }
      } }
      if updating {
        Text(store.cinema.preparationMessage).font(.subheadline).foregroundStyle(Palette.accent)
      }
      HStack(spacing: 16) {
        Button("Edit", systemImage: "pencil", action: edit)
          .buttonStyle(CinemaButtonStyle()).disabled(store.cinema.preparing || unsaved || store.cinema.deletingId != nil)
          .accessibilityIdentifier("cinema-edit")
        Button("Delete", systemImage: "trash", action: delete)
          .buttonStyle(CinemaButtonStyle(destructive: true))
          .disabled(updating || store.cinema.deletingId != nil)
          .accessibilityIdentifier("cinema-delete")
      }
      if !capsule.canWatch && !updating && !unsaved {
        Text("This item needs more pictures. Edit it to regenerate the montage.")
          .font(.footnote).foregroundStyle(Palette.secondary)
      }
      ForEach(capsule.notices ?? [], id: \.self) { notice in
        Text(notice).font(.footnote).foregroundStyle(Palette.secondary)
      }
    }
  }

  @ViewBuilder private var playback: some View {
    Button {
      Task {
        if updating {
          await store.cinema.playPreparation(zoneId: store.selectedZoneId, current: store.currentTrack,
            queue: store.queue, isPlaying: store.isPlaying, client: store.client)
        } else { await store.cinema.play(capsule, zoneId: store.selectedZoneId, client: store.client, associate: !unsaved) }
      }
    } label: { Label("Play music & pictures", systemImage: "play.fill").fixedSize(horizontal: true, vertical: false) }
    .buttonStyle(CinemaButtonStyle(prominent: true))
    .disabled(store.cinema.playing || store.selectedZoneId.isEmpty || capsule.request.tracks.isEmpty || store.cinema.deletingId == capsule.id)
    .accessibilityIdentifier("cinema-play")
    VStack(spacing: 6) {
      Button("Watch pictures", systemImage: "photo.on.rectangle") { store.cinema.watch(capsule) }
        .buttonStyle(CinemaButtonStyle())
        .disabled((!capsule.canWatch && !updating && !unsaved) || store.cinema.deletingId == capsule.id)
        .accessibilityIdentifier("cinema-watch")
      Text("Leaves your music as it is.").font(.caption).foregroundStyle(Palette.secondary)
    }
  }
}

struct CreateTimeCapsuleButton: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    if let context = store.aiSearchContext, !store.aiResults.isEmpty, !store.aiLoading {
      Button {
        store.cinema.create(context: context, tracks: store.aiResults, client: store.client)
      } label: {
        Label(store.cinema.preparing ? "Preparing Cinema…" : "Set up Cinema", systemImage: "sparkles.tv")
      }
      .foregroundStyle(Palette.accent)
      .disabled(store.aiResults.allSatisfy { $0.error != nil })
    }
  }
}
