import SwiftUI

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
        HStack {
          Button {
            store.showVolume = false
            store.showTransfer = true
          } label: {
            Image(systemName: "arrow.left.arrow.right")
          }
          if store.outputs.count > 1 || !store.groupableHouseOutputs.isEmpty {
            Button {
              store.openGrouping()
            } label: {
              Image(systemName: "link")
            }
          }
          Spacer()
        }
        .foregroundStyle(Palette.accent)
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
    .sheet(isPresented: $store.showTransfer) {
      TransferView()
    }
    .sheet(isPresented: $store.showGrouping) {
      GroupingView()
    }
  }
}

struct TransferView: View {
  @Environment(MockStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section("From") {
          Text(store.selectedZone.name)
        }
        Section("To zone") {
          ForEach(store.zones.filter { $0.id != store.selectedZoneId }) { zone in
            Button {
              store.transfer(to: zone.id)
              dismiss()
            } label: {
              Label(zone.name, systemImage: "hifispeaker.fill")
                .foregroundStyle(Palette.primary)
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(Palette.background)
      .navigationTitle("Transfer")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .presentationBackground(Palette.background)
  }
}

struct GroupingView: View {
  @Environment(MockStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    @Bindable var store = store
    NavigationStack {
      List {
        Section("Currently in group") {
          ForEach(store.outputs) { output in
            Toggle(output.name, isOn: bind(output.id))
              .tint(Palette.accent)
              .disabled(output.id == store.outputs.first?.id)
          }
        }
        if !store.groupableHouseOutputs.isEmpty {
          Section("Add to zone") {
            ForEach(store.groupableHouseOutputs, id: \.outputId) { output in
              Toggle(output.displayName, isOn: bind(output.outputId))
                .tint(Palette.accent)
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(Palette.background)
      .navigationTitle("Grouping")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            store.saveGrouping()
            dismiss()
          }
        }
      }
    }
    .presentationBackground(Palette.background)
  }

  private func bind(_ id: String) -> Binding<Bool> {
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
