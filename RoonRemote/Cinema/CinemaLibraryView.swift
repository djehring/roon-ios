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
      .sheet(isPresented: $cinema.showingLibrary, onDismiss: {
        libraryIsActive = false
        viewer = cinema.presented
      }) {
        CinemaLibraryView()
          .onAppear { libraryIsActive = true }
      }
      .fullScreenCover(item: $viewer, onDismiss: {
        cinema.presented = nil
        if cinema.libraryAfterViewer {
          cinema.libraryAfterViewer = false
          cinema.showingLibrary = true
        }
      }) { capsule in
        let resolved = cinema.preparation?.resolve(capsule) ?? capsule
        CinemaView(capsule: resolved).id(resolved.id)
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

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if store.cinema.preparing {
            HStack(spacing: 14) {
              ProgressView().tint(Palette.accent)
              VStack(alignment: .leading, spacing: 4) {
                Text(store.cinema.preparationMessage).font(.headline)
                Text("You can keep listening while it prepares.").font(.subheadline).foregroundStyle(.secondary)
              }
            }
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)

            Button {
              Task {
                await store.cinema.playPreparation(zoneId: store.selectedZoneId, current: store.currentTrack,
                  queue: store.queue, isPlaying: store.isPlaying, client: store.client)
              }
            } label: {
              Label("Play now", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .foregroundStyle(Palette.onAccent)
            .disabled(store.cinema.playing || store.selectedZoneId.isEmpty)
          }

          if let error = store.cinema.preparationError ?? store.cinema.error {
            Text(error).foregroundStyle(Palette.accent).fixedSize(horizontal: false, vertical: true)
          }

          if !store.selectedZoneId.isEmpty, !store.cinema.preparing,
             CapsuleNowPlaying.select(preparing: false, current: store.currentTrack, queue: store.queue,
               associated: nil, saved: store.cinema.capsules) != nil {
            Button {
              Task { await store.cinema.open(zoneId: store.selectedZoneId, current: store.currentTrack, queue: store.queue, client: store.client) }
            } label: {
              Label("Join \(store.selectedZone.name)", systemImage: "tv")
            }
            .buttonStyle(.bordered)
            .disabled(store.cinema.preparing || store.cinema.opening || store.cinema.preparationError != nil)
          }

          if store.cinema.loading {
            ProgressView("Loading programmes…")
          } else if store.cinema.capsules.isEmpty && !store.cinema.preparing {
            ContentUnavailableView("Your music, brought to life", systemImage: "sparkles.tv",
              description: Text("Search for music, then choose Set up Cinema."))
          }

          ForEach(store.cinema.capsules) { capsule in
            capsuleRow(capsule)
            Divider()
          }
        }
        .frame(maxWidth: 950, alignment: .leading)
        .padding(28)
        .frame(maxWidth: .infinity)
      }
      .background(Palette.background)
      .navigationTitle("Cinema")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .automatic) {
          Button("Refresh", systemImage: "arrow.clockwise") {
            Task { await store.cinema.load(client: store.client) }
          }.disabled(store.cinema.loading)
        }
      }
    }
    .tint(Palette.accent)
    .task { await store.cinema.load(client: store.client) }
  }

  private func capsuleRow(_ capsule: TimeCapsule) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(capsule.title).font(.title3.weight(.semibold))
      Text(capsule.contextLabel).foregroundStyle(.secondary)
      Text("\(capsule.request.tracks.count) tracks · \(capsule.montageFrames.count) images")
        .font(.caption).foregroundStyle(.secondary)
      if let options = capsule.request.options { Text(options.summary).font(.caption).foregroundStyle(.secondary) }
      ForEach(capsule.notices ?? [], id: \.self) { notice in Text(notice).font(.footnote).foregroundStyle(.secondary) }
      if !capsule.canWatch {
        Text("This capsule needs more photographs. Rebuild it to create a montage.")
          .font(.subheadline).foregroundStyle(Palette.accent)
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) { playbackButtons(capsule) }
        VStack(alignment: .leading, spacing: 12) { playbackButtons(capsule) }
      }
      if !capsule.isPersonal {
        Button("Rebuild montage", systemImage: "arrow.clockwise") {
          store.cinema.rebuild(capsule, client: store.client)
        }
        .buttonStyle(.bordered)
        .disabled(store.cinema.preparing)
      }
    }
    .padding(.vertical, 8)
  }

  @ViewBuilder private func playbackButtons(_ capsule: TimeCapsule) -> some View {
    Button {
      Task { await store.cinema.play(capsule, zoneId: store.selectedZoneId, client: store.client) }
    } label: {
      Label("Play music & montage", systemImage: "play.fill")
    }
    .buttonStyle(.borderedProminent)
    .tint(Palette.accent)
    .foregroundStyle(Palette.onAccent)
    .disabled(store.cinema.playing || store.selectedZoneId.isEmpty || !capsule.canWatch)

    Button("Watch pictures", systemImage: "photo.on.rectangle") { store.cinema.watch(capsule) }
      .buttonStyle(.bordered)
      .disabled(!capsule.canWatch)
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
