import SwiftUI

struct RegularRoomsView: View {
  @Environment(MockStore.self) private var store
  @State private var groupingExpanded = false

  private let columns = [
    GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 20),
  ]

  var body: some View {
    ScrollView {
      if store.zones.isEmpty {
        ContentUnavailableView(
          "No rooms found",
          systemImage: "hifispeaker.2",
          description: Text("Rooms appear when the bridge finishes syncing.")
        )
        .frame(maxWidth: .infinity, minHeight: 500)
      } else {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
          ForEach(store.zones) { zone in
            roomCard(zone)
          }
        }

        if groupingExpanded {
          groupingPanel
            .padding(.top, 24)
        }
      }
    }
    .padding(28)
    .background(Palette.background)
    .navigationTitle("Rooms")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          if !groupingExpanded {
            store.prepareGrouping()
          }
          withAnimation(Motion.sheet) {
            groupingExpanded.toggle()
          }
        } label: {
          Label(
            groupingExpanded ? "Hide Grouping" : "Group Rooms",
            systemImage: "hifispeaker.2"
          )
        }
      }
    }
  }

  private func roomCard(_ zone: Zone) -> some View {
    let selected = zone.id == store.selectedZoneId

    return VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 14) {
        CoverArt(
          title: zone.track?.album ?? zone.name,
          image: store.imageData(for: zone.track?.imageKey),
          corner: 10
        )
        .frame(width: 76, height: 76)

        VStack(alignment: .leading, spacing: 5) {
          HStack {
            Text(zone.name)
              .font(.title3.weight(.semibold))
            if selected {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.accent)
            }
          }
          Text(statusText(for: zone))
            .font(.subheadline)
            .foregroundStyle(Palette.secondary)
            .lineLimit(2)
        }
        Spacer(minLength: 0)
      }

      if selected {
        ForEach(store.outputs) { output in
          outputControl(output)
        }
      }

      HStack(spacing: 10) {
        if !selected {
          Button("Control") {
            store.selectZone(zone.id)
          }
          .buttonStyle(.bordered)
        }
        if !selected, store.currentTrack != nil {
          Button("Move playback") {
            store.transfer(to: zone.id)
          }
          .buttonStyle(.borderedProminent)
          .tint(Palette.accent)
          .foregroundStyle(Palette.onAccent)
        }
        if selected {
          Button {
            store.togglePlay()
          } label: {
            Label(
              store.isPlaying ? "Pause" : "Play",
              systemImage: store.isPlaying ? "pause.fill" : "play.fill"
            )
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .background(Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(selected ? Palette.accent.opacity(0.65) : Palette.hairline, lineWidth: selected ? 2 : 1)
    }
  }

  @ViewBuilder
  private func outputControl(_ output: Output) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(output.name)
          .font(.caption.weight(.semibold))
          .foregroundStyle(Palette.secondary)
        Spacer()
        if output.isFixed {
          Text("Fixed")
            .font(.caption)
            .foregroundStyle(Palette.tertiary)
        } else {
          Text("\(Int(output.volume))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(Palette.secondary)
        }
      }

      if !output.isFixed {
        HStack(spacing: 12) {
          Button {
            store.toggleMute(output)
          } label: {
            Image(systemName: output.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
              .frame(width: 30, height: 30)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(output.muted ? "Unmute" : "Mute")

          Slider(
            value: Binding(
              get: { output.volume },
              set: { store.setVolume(output, value: $0) }
            ),
            in: output.min...max(output.max, output.min + 1)
          )
          .tint(Palette.accent)
        }
      }
    }
    .padding(12)
    .background(Palette.background.opacity(0.48))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var groupingPanel: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Group \(store.selectedZone.name)")
            .font(.title2.weight(.semibold))
          Text("Choose the outputs that should play together.")
            .foregroundStyle(Palette.secondary)
        }
        Spacer()
        Button("Save") {
          store.saveGrouping()
          withAnimation(Motion.sheet) {
            groupingExpanded = false
          }
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.accent)
        .foregroundStyle(Palette.onAccent)
      }

      Divider()

      ForEach(store.outputs) { output in
        Toggle(output.name, isOn: groupBinding(output.id))
          .tint(Palette.accent)
          .disabled(output.id == store.outputs.first?.id)
      }

      ForEach(store.groupableHouseOutputs, id: \.outputId) { output in
        Toggle(output.displayName, isOn: groupBinding(output.outputId))
          .tint(Palette.accent)
      }
    }
    .padding(24)
    .background(Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Palette.hairline, lineWidth: 1)
    }
  }

  private func groupBinding(_ id: String) -> Binding<Bool> {
    Binding(
      get: { store.pendingGroupIds.contains(id) },
      set: { enabled in
        if enabled {
          store.pendingGroupIds.insert(id)
        } else {
          store.pendingGroupIds.remove(id)
        }
      }
    )
  }

  private func statusText(for zone: Zone) -> String {
    guard let track = zone.track else {
      return zone.state == .loading ? "Loading…" : "Nothing playing"
    }
    switch zone.state {
    case .playing: return "Playing · \(track.title)"
    case .paused: return "Paused · \(track.title)"
    case .loading: return "Loading · \(track.title)"
    case .stopped: return track.title
    }
  }
}
