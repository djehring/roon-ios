import SwiftUI

/// The playback sheets, presented by whichever root owns them. The compact root
/// leaves them on Now Playing; the regular root hoists them above the split view
/// so the sidebar's mini player can open them from any destination.
struct PlaybackSheets: ViewModifier {
  @Environment(MockStore.self) private var store

  func body(content: Content) -> some View {
    @Bindable var store = store
    content
      .sheet(isPresented: $store.showZonePicker) {
        ZonePickerSheet()
          .presentationDetents([.medium, .large])
      }
      .sheet(isPresented: $store.showVolume) {
        VolumeSheet()
          .presentationDetents([.medium, .large])
      }
      .sheet(isPresented: $store.showQueue) {
        QueueSheet()
          .presentationDetents([.large])
      }
      .sheet(isPresented: $store.showStory) {
        StorySheet()
          .presentationDetents([.large])
      }
  }
}

extension View {
  /// `enabled` is fixed per call site rather than reactive, so this never
  /// changes a view's identity mid-flight.
  @ViewBuilder
  func playbackSheets(enabled: Bool = true) -> some View {
    if enabled {
      modifier(PlaybackSheets())
    } else {
      self
    }
  }
}

struct ZonePickerSheet: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    NavigationStack {
      List(store.zones) { zone in
        Button {
          store.selectZone(zone.id)
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(zone.name)
                .foregroundStyle(Palette.primary)
              Text(zone.track?.title ?? "Nothing playing")
                .font(.footnote)
                .foregroundStyle(Palette.secondary)
            }
            Spacer()
            if zone.id == store.selectedZoneId {
              Image(systemName: "checkmark")
                .foregroundStyle(Palette.accent)
            }
          }
        }
        .listRowBackground(Palette.surface)
      }
      .scrollContentBackground(.hidden)
      .background(Palette.background)
      .navigationTitle("Rooms")
      .navigationBarTitleDisplayMode(.inline)
    }
    .presentationBackground(Palette.background)
  }
}

struct VolumeSheet: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    @Bindable var store = store
    NavigationStack {
      List {
        Button {
          store.openZonePanel()
        } label: {
          Label("Zones & grouping", systemImage: "hifispeaker.2")
            .foregroundStyle(Palette.accent)
        }
        .listRowBackground(Palette.surface)

        ForEach($store.outputs) { $output in
          Section(output.name) {
            if output.isFixed {
              Text("Volume is fixed")
                .foregroundStyle(Palette.secondary)
            } else {
              HStack {
                Button {
                  store.toggleMute(output)
                } label: {
                  Image(systemName: output.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                Slider(
                  value: Binding(
                    get: { output.volume },
                    set: { store.setVolume(output, value: $0) }
                  ),
                  in: output.min...max(output.max, output.min + 1)
                )
                .tint(Palette.accent)
                Text("\(Int(output.volume))")
                  .foregroundStyle(Palette.secondary)
                  .frame(width: 36, alignment: .trailing)
              }
            }
          }
          .listRowBackground(Palette.surface)
        }
      }
      .scrollContentBackground(.hidden)
      .background(Palette.background)
      .navigationTitle("Volume")
      .navigationBarTitleDisplayMode(.inline)
    }
    .presentationBackground(Palette.background)
    .sheet(isPresented: $store.showZonePanel) {
      ZonePanelSheet()
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }
  }
}

struct ZonePanelSheet: View {
  @Environment(MockStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    @Bindable var store = store
    NavigationStack {
      VStack(spacing: 0) {
        Picker("Panel", selection: $store.zonePanelTab) {
          ForEach(ZonePanelTab.allCases) { tab in
            Text(tab.title).tag(tab)
          }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        switch store.zonePanelTab {
        case .switchZone:
          switchZoneList
        case .group:
          groupList
        }
      }
      .background(Palette.background)
      .navigationTitle("Zones")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") {
            store.showZonePanel = false
            dismiss()
          }
        }
        if store.zonePanelTab == .group {
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              store.saveGrouping()
              dismiss()
            }
          }
        }
      }
    }
    .presentationBackground(Palette.background)
  }

  private var switchZoneList: some View {
    List {
      Section {
        Text("Transfer playback from \(store.selectedZone.name)")
          .font(.footnote)
          .foregroundStyle(Palette.secondary)
          .listRowBackground(Color.clear)
      }

      Section("To zone") {
        ForEach(store.zones.filter { $0.id != store.selectedZoneId }) { zone in
          Button {
            store.transfer(to: zone.id)
            store.showZonePanel = false
            dismiss()
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(zone.name)
                  .foregroundStyle(Palette.primary)
                Text(zone.track?.title ?? "Nothing playing")
                  .font(.footnote)
                  .foregroundStyle(Palette.secondary)
              }
              Spacer()
              Image(systemName: "arrow.right.circle")
                .foregroundStyle(Palette.accent)
            }
          }
          .listRowBackground(Palette.surface)
        }
      }
    }
    .scrollContentBackground(.hidden)
  }

  private var groupList: some View {
    List {
      Section("Currently in group") {
        ForEach(store.outputs) { output in
          Toggle(output.name, isOn: groupBinding(output.id))
            .tint(Palette.accent)
            .disabled(output.id == store.outputs.first?.id)
            .listRowBackground(Palette.surface)
        }
      }
      if !store.groupableHouseOutputs.isEmpty {
        Section("Add to zone") {
          ForEach(store.groupableHouseOutputs, id: \.outputId) { output in
            Toggle(output.displayName, isOn: groupBinding(output.outputId))
              .tint(Palette.accent)
              .listRowBackground(Palette.surface)
          }
        }
      }
    }
    .scrollContentBackground(.hidden)
  }

  private func groupBinding(_ id: String) -> Binding<Bool> {
    Binding(
      get: { store.pendingGroupIds.contains(id) },
      set: { on in
        if on { store.pendingGroupIds.insert(id) }
        else { store.pendingGroupIds.remove(id) }
      }
    )
  }
}

struct QueueSheet: View {
  var body: some View {
    NavigationStack {
      QueueList(embedded: false)
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.inline)
    }
    .presentationBackground(Palette.background)
  }
}

struct StorySheet: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      TrackStoryView()
        .navigationTitle("Story")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }
          }
        }
    }
    .presentationBackground(Palette.background)
  }
}

struct QueueList: View {
  @Environment(MockStore.self) private var store
  var embedded: Bool

  var body: some View {
    Group {
      if store.queue.isEmpty {
        ContentUnavailableView(
          "Queue is empty",
          systemImage: "music.note.list",
          description: Text("Add music from Library or Search.")
        )
      } else {
        List(store.queue) { item in
          Button {
            store.playFromHere(item)
          } label: {
            HStack(spacing: 12) {
              CoverArt(
                title: item.album,
                image: store.imageData(for: item.imageKey),
                corner: 6
              )
              .frame(width: 56, height: 56)
              VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                  .foregroundStyle(Palette.primary)
                Text("\(item.album)  ·  \(item.artist)")
                  .font(.footnote)
                  .foregroundStyle(Palette.secondary)
              }
            }
          }
          .contextMenu {
            Button("Play from here") { store.playFromHere(item) }
          }
          .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
      }
    }
    .background(Palette.background)
    .safeAreaInset(edge: .top, spacing: 0) {
      if embedded {
        Text("Queue")
          .font(.headline)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(16)
      }
    }
  }
}
