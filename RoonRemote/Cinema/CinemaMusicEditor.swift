import SwiftUI

struct CinemaMusicEditor: View {
  let draft: CinemaMusicDraft
  let title: String
  var currentTrack: CapsuleTrack?
  @State private var adding = false
  @State private var focusedTrack: CapsuleTrack?
  #if os(iOS)
  @State private var editMode: EditMode = .inactive
  #endif

  var body: some View {
    List {
      Section {
        Text(draft.summary).foregroundStyle(Palette.secondary)
        if let currentTrack, let id = currentTrack.entryId {
          Toggle("Include current track", isOn: Binding(
            get: { draft.tracks.contains { $0.entryId == id } },
            set: { include in
              if include { draft.restoreCurrent(currentTrack) }
              else { draft.remove(id) }
            }))
        }
        #if os(iOS)
        Button(editMode.isEditing ? "Finish reordering" : "Reorder tracks") {
          withAnimation { editMode = editMode.isEditing ? .inactive : .active }
        }.accessibilityIdentifier("cinema-reorder")
        #endif
      } footer: {
        Text("Your Cinema copy can be edited separately. Save changes when you’re finished.")
      }
      Section {
        if draft.tracks.isEmpty {
          Text("Add tracks, an album or a playlist to get started.")
            .foregroundStyle(Palette.secondary)
        }
        ForEach(Array(draft.tracks.enumerated()), id: \.element.entryId) { index, track in
          #if os(tvOS)
          Button { focusedTrack = track } label: { trackRow(track, index: index) }
            .cinemaPlainButton()
          #else
          HStack {
            trackRow(track, index: index)
            Menu { moveActions(track) } label: {
              Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Actions for \(track.track)")
            .accessibilityIdentifier("cinema-track-actions-\(index)")
          }
          .accessibilityAction(named: "Move up") { move(track, offset: -1) }
          .accessibilityAction(named: "Move down") { move(track, offset: 1) }
          .accessibilityAction(named: "Remove") { if let id = track.entryId { draft.remove(id) } }
          #endif
        }
        .onMove { draft.move(from: $0, to: $1) }
        #if os(iOS)
        .onDelete { indices in
          for id in indices.compactMap({ draft.tracks[$0].entryId }) { draft.remove(id) }
        }
        #endif
      }
      .listRowBackground(Palette.surface)
    }
    #if os(iOS)
    .environment(\.editMode, $editMode)
    .scrollContentBackground(.hidden)
    #endif
    .background(Palette.background)
    .navigationTitle("Music")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Undo", systemImage: "arrow.uturn.backward") { draft.undo() }
          .disabled(!draft.canUndo).accessibilityIdentifier("cinema-music-undo")
      }
    }
    .safeAreaInset(edge: .bottom) {
      Button { adding = true } label: { Label("Add music", systemImage: "plus") }
        .buttonStyle(CinemaButtonStyle(prominent: true))
        .accessibilityIdentifier("cinema-add-music")
        .padding(CinemaLayout.inset).background(Palette.background)
    }
    .sheet(isPresented: $adding) { CinemaMusicPicker(draft: draft, title: title) }
    .confirmationDialog(focusedTrack?.track ?? "Track", isPresented: Binding(
      get: { focusedTrack != nil }, set: { if !$0 { focusedTrack = nil } }), titleVisibility: .visible) {
      if let track = focusedTrack { moveActions(track) }
    }
  }

  private func trackRow(_ track: CapsuleTrack, index: Int) -> some View {
    HStack(spacing: 12) {
      Text("\(index + 1)").monospacedDigit().foregroundStyle(Palette.secondary).frame(minWidth: 24)
      VStack(alignment: .leading, spacing: 4) {
        Text(track.track).foregroundStyle(Palette.primary).lineLimit(2)
        Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
          .font(.caption).foregroundStyle(Palette.secondary).lineLimit(2)
      }
      Spacer(minLength: 0)
    }
    .frame(minHeight: CinemaLayout.controlHeight)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("cinema-track-\(index)")
  }

  @ViewBuilder private func moveActions(_ track: CapsuleTrack) -> some View {
    let index = draft.tracks.firstIndex { $0.entryId == track.entryId } ?? 0
    Button("Move up") { move(track, offset: -1) }.disabled(index == 0)
    Button("Move down") { move(track, offset: 1) }.disabled(index == draft.tracks.count - 1)
    Button("Move to start") { if let id = track.entryId { draft.move(id, to: 0) } }.disabled(index == 0)
    Button("Move to end") { if let id = track.entryId { draft.move(id, to: draft.tracks.count - 1) } }
      .disabled(index == draft.tracks.count - 1)
    Button("Remove", role: .destructive) { if let id = track.entryId { draft.remove(id) } }
  }

  private func move(_ track: CapsuleTrack, offset: Int) {
    guard let id = track.entryId, let index = draft.tracks.firstIndex(where: { $0.entryId == id }) else { return }
    draft.move(id, to: index + offset)
  }
}
