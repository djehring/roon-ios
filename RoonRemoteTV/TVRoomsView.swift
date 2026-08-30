import SwiftUI

struct TVRoomsView: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    HStack(alignment: .top, spacing: 48) {
      VStack(alignment: .leading, spacing: 16) {
        Text("Playing On")
          .font(.system(size: 44, weight: .bold))
        Text("Select a room to control, or transfer playback.")
          .font(.title3)
          .foregroundStyle(Palette.secondary)
          .frame(maxWidth: 420, alignment: .leading)

        if let track = store.currentTrack {
          HStack(spacing: 16) {
            CoverArt(
              title: track.album,
              image: store.imageData(for: track.imageKey),
              corner: 10
            )
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
              Text(track.title)
                .font(.headline)
                .lineLimit(1)
              Text(track.artist)
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
            }
          }
          .padding(.top, 24)
        }
        Spacer()
      }
      .frame(width: 420, alignment: .leading)
      .padding(.leading, 48)
      .padding(.top, 48)

      ScrollView {
        LazyVStack(spacing: 16) {
          if store.zones.isEmpty {
            ProgressView()
              .tint(Palette.accent)
              .padding(.top, 80)
          } else {
            ForEach(store.zones) { zone in
              roomRow(zone)
            }
          }
        }
        .padding(.vertical, 48)
        .padding(.trailing, 48)
      }
    }
    .background(Palette.background)
  }

  private func roomRow(_ zone: Zone) -> some View {
    let selected = zone.id == store.selectedZoneId
    return VStack(alignment: .leading, spacing: 16) {
      Button {
        if !selected {
          if store.currentTrack != nil {
            store.transfer(to: zone.id)
          } else {
            store.selectZone(zone.id)
          }
        }
      } label: {
        HStack(spacing: 20) {
          Image(systemName: "hifispeaker.fill")
            .font(.title)
            .foregroundStyle(selected ? Palette.accent : Palette.secondary)
            .frame(width: 44)
          VStack(alignment: .leading, spacing: 6) {
            Text(zone.name)
              .font(.title2.weight(.semibold))
            Text(statusText(for: zone))
              .font(.body)
              .foregroundStyle(Palette.secondary)
          }
          Spacer()
          if selected {
            Image(systemName: "checkmark.circle.fill")
              .font(.title)
              .foregroundStyle(Palette.accent)
          }
        }
        .padding(28)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(selected ? Palette.accent.opacity(0.55) : Palette.hairline, lineWidth: 2)
        }
      }
      .buttonStyle(.plain)

      if selected, let output = store.outputs.first(where: { !$0.isFixed }) {
        volumeSlider(output)
      }
    }
  }

  private func volumeSlider(_ output: Output) -> some View {
    let step = max(1, (output.max - output.min) / 20)
    return HStack(spacing: 24) {
      Button {
        store.setVolume(output, value: max(output.min, output.volume - step))
      } label: {
        Image(systemName: "speaker.fill")
          .font(.title2)
          .frame(width: 64, height: 64)
      }
      .buttonStyle(.plain)

      Text("\(Int(output.volume))")
        .font(.title.weight(.semibold).monospacedDigit())
        .frame(minWidth: 80)

      Button {
        store.setVolume(output, value: min(output.max, output.volume + step))
      } label: {
        Image(systemName: "speaker.wave.3.fill")
          .font(.title2)
          .frame(width: 64, height: 64)
      }
      .buttonStyle(.plain)

      Button {
        store.toggleMute(output)
      } label: {
        Text(output.muted ? "Unmute" : "Mute")
          .font(.title3.weight(.medium))
          .padding(.horizontal, 20)
          .padding(.vertical, 14)
          .background(Palette.surface)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 16)
    .background(Palette.surface.opacity(0.7))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private func statusText(for zone: Zone) -> String {
    if zone.id == store.selectedZoneId {
      switch zone.state {
      case .playing: return zone.track.map { "Playing · \($0.title)" } ?? "Playing"
      case .paused: return "Paused"
      case .loading: return "Loading…"
      case .stopped: return "Idle"
      }
    }
    if let track = zone.track {
      return "\(zone.state == .playing ? "Playing" : "Idle") · \(track.title)"
    }
    return "Idle"
  }
}
