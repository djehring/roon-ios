import SwiftUI

struct CinemaPresentation: ViewModifier {
  @Environment(MockStore.self) private var store
  @State private var viewer: TimeCapsule?

  func body(content: Content) -> some View {
    @Bindable var cinema = store.cinema
    content
      .sheet(isPresented: $cinema.showingLibrary, onDismiss: {
        viewer = cinema.presented
      }) {
        CinemaLibraryView()
      }
      .fullScreenCover(item: $viewer, onDismiss: { cinema.presented = nil }) { capsule in
        CinemaView(capsule: capsule)
      }
      .onAppear { viewer = cinema.presented }
  }
}

struct CinemaLibraryView: View {
  @Environment(MockStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Text("The world around your music.")
            .font(.title2.weight(.semibold))
          Text("A changing photo montage of the world around your music: news, politics, sport and everyday life from the period you requested.")
            .foregroundStyle(.secondary)

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
          }

          if let error = store.cinema.error {
            Text(error).foregroundStyle(Palette.accent).fixedSize(horizontal: false, vertical: true)
          }

          if !store.selectedZoneId.isEmpty {
            Button {
              Task { await store.cinema.join(zoneId: store.selectedZoneId, client: store.client) }
            } label: {
              Label("Join \(store.selectedZone.name)", systemImage: "tv")
            }
            .buttonStyle(.bordered)
          }

          if store.cinema.loading {
            ProgressView("Loading programmes…")
          } else if store.cinema.capsules.isEmpty && !store.cinema.preparing {
            ContentUnavailableView("Your music, brought to life", systemImage: "sparkles.tv",
              description: Text("Search for music, then choose Create Time Capsule."))
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
      .navigationTitle("Time Capsules")
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
      Text("\(capsule.request.tracks.count) tracks · \(capsule.montageFrames.count) photographs")
        .font(.caption).foregroundStyle(.secondary)
      if capsule.montageFrames.count < 3 {
        Text("This capsule needs more photographs. Rebuild it to create a montage.")
          .font(.subheadline).foregroundStyle(Palette.accent)
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) { playbackButtons(capsule) }
        VStack(alignment: .leading, spacing: 12) { playbackButtons(capsule) }
      }
      Button("Rebuild montage", systemImage: "arrow.clockwise") {
        store.cinema.rebuild(capsule, client: store.client)
      }
      .buttonStyle(.bordered)
      .disabled(store.cinema.preparing)
    }
    .padding(.vertical, 8)
  }

  @ViewBuilder private func playbackButtons(_ capsule: TimeCapsule) -> some View {
    Button {
      Task { await store.cinema.play(capsule, zoneId: store.selectedZoneId, client: store.client) }
    } label: {
      Label("Play with Cinema", systemImage: "play.fill")
    }
    .buttonStyle(.borderedProminent)
    .tint(Palette.accent)
    .foregroundStyle(Palette.onAccent)
    .disabled(store.cinema.playing || store.selectedZoneId.isEmpty || capsule.montageFrames.count < 3)

    Button("Watch montage") { store.cinema.watch(capsule) }
      .buttonStyle(.bordered)
      .disabled(capsule.montageFrames.count < 3)
  }
}

struct CreateTimeCapsuleButton: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    if let context = store.aiSearchContext, !store.aiResults.isEmpty, !store.aiLoading {
      Button {
        store.cinema.create(context: context, tracks: store.aiResults, client: store.client)
      } label: {
        Label(store.cinema.preparing ? "Preparing Time Capsule…" : "Create Time Capsule", systemImage: "sparkles.tv")
      }
      .foregroundStyle(Palette.accent)
      .disabled(store.aiResults.allSatisfy { $0.error != nil })
    }
  }
}
