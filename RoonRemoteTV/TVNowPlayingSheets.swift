import SwiftUI

struct TVVolumePanel: View {
  @Environment(MockStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack {
      Palette.background.ignoresSafeArea()
      VStack(alignment: .leading, spacing: 36) {
        HStack(alignment: .firstTextBaseline) {
          Text("Volume")
            .font(.system(size: 44, weight: .bold))
          Spacer()
          Button { dismiss() } label: { TVSheetDoneLabel() }
            .tvUnplated()
        }

        if store.outputs.isEmpty {
          Text("No outputs on this zone.")
            .font(.title2)
            .foregroundStyle(Palette.secondary)
          Spacer()
        } else {
          ScrollView {
            LazyVStack(spacing: 28) {
              ForEach(store.outputs) { output in
                outputCard(output)
              }
            }
          }
        }
      }
      .padding(56)
    }
  }

  @ViewBuilder
  private func outputCard(_ output: Output) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(output.name)
        .font(.title2.weight(.semibold))

      if output.isFixed {
        Text("Volume is fixed on this output")
          .font(.title3)
          .foregroundStyle(Palette.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 28)
      } else {
        let step = max(1, (output.max - output.min) / 20)
        VStack(alignment: .leading, spacing: 28) {
          HStack(spacing: 36) {
            TVIconButton(symbol: "speaker.fill", size: 88, fontSize: 32) {
              store.setVolume(output, value: max(output.min, output.volume - step))
            }

            VStack(spacing: 12) {
              Text(output.muted ? "Muted" : "\(Int(output.volume))")
                .font(.system(size: 56, weight: .bold).monospacedDigit())
                .foregroundStyle(output.muted ? Palette.tertiary : Palette.primary)
              volumeBar(output)
                .frame(height: 10)
            }
            .frame(maxWidth: .infinity)

            TVIconButton(symbol: "speaker.wave.3.fill", size: 88, fontSize: 32) {
              store.setVolume(output, value: min(output.max, output.volume + step))
            }
          }

          TVIconButton(
            symbol: output.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
            size: 72,
            fontSize: 26,
            filled: output.muted
          ) {
            store.toggleMute(output)
          }
        }
        .padding(.vertical, 8)
      }
    }
    .padding(36)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(Palette.hairline, lineWidth: 2)
    }
  }

  private func volumeBar(_ output: Output) -> some View {
    let span = max(output.max - output.min, 1)
    let fraction = output.muted ? 0 : (output.volume - output.min) / span
    return GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(Palette.hairline)
        Capsule()
          .fill(Palette.accent)
          .frame(width: max(4, geo.size.width * fraction))
      }
    }
  }
}

struct TVQueuePanel: View {
  @Environment(MockStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack {
      Palette.background.ignoresSafeArea()
      VStack(alignment: .leading, spacing: 28) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Queue")
              .font(.system(size: 44, weight: .bold))
            if !store.upcomingQueue.isEmpty {
              Text("\(store.upcomingQueue.count) tracks  ·  select to play from here")
                .font(.title3)
                .foregroundStyle(Palette.secondary)
            }
          }
          Spacer()
          Button { dismiss() } label: { TVSheetDoneLabel() }
            .tvUnplated()
        }

        if store.upcomingQueue.isEmpty {
          Spacer()
          VStack(spacing: 16) {
            Image(systemName: "music.note.list")
              .font(.system(size: 56, weight: .light))
              .foregroundStyle(Palette.tertiary)
            Text("Nothing up next")
              .font(.title)
            Text("Add music from Library or Search.")
              .font(.title3)
              .foregroundStyle(Palette.secondary)
          }
          .frame(maxWidth: .infinity)
          Spacer()
        } else {
          ScrollView {
            LazyVStack(spacing: 20) {
              ForEach(Array(store.upcomingQueue.enumerated()), id: \.element.id) { index, item in
                queueRow(item, index: index)
              }
            }
            .padding(.bottom, 40)
          }
        }
      }
      .padding(56)
    }
  }

  private func queueRow(_ item: QueueItem, index: Int) -> some View {
    let isCurrent = store.currentTrack.map {
      $0.title == item.title && $0.artist == item.artist
    } ?? false
    return Button {
      store.playFromHere(item)
      dismiss()
    } label: {
      TVQueueRowLabel(
        item: item,
        index: index,
        isCurrent: isCurrent,
        image: store.imageData(for: item.imageKey)
      )
    }
    .tvUnplated()
  }
}

private struct TVSheetDoneLabel: View {
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    Text("Done")
      .font(.title3.weight(.medium))
      .foregroundStyle(isFocused ? Palette.onAccent : Palette.secondary)
      .padding(.horizontal, 22)
      .padding(.vertical, 12)
      .background(isFocused ? Color.white : Palette.surface)
      .clipShape(Capsule())
  }
}

private struct TVQueueRowLabel: View {
  let item: QueueItem
  let index: Int
  let isCurrent: Bool
  var image: Data?
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    HStack(spacing: 24) {
      Text("\(index + 1)")
        .font(.title3.monospacedDigit())
        .foregroundStyle(isFocused ? Palette.onAccent.opacity(0.55) : Palette.tertiary)
        .frame(width: 44, alignment: .trailing)

      CoverArt(
        title: item.album,
        image: image,
        corner: 10
      )
      .frame(width: 72, height: 72)

      VStack(alignment: .leading, spacing: 6) {
        Text(item.title)
          .font(.title2.weight(.semibold))
          .foregroundStyle(titleColor)
          .lineLimit(1)
        Text("\(item.artist)  ·  \(item.album)")
          .font(.body)
          .foregroundStyle(isFocused ? Palette.onAccent.opacity(0.65) : Palette.secondary)
          .lineLimit(1)
      }

      Spacer()

      if isCurrent {
        Image(systemName: "waveform")
          .font(.title2)
          .foregroundStyle(isFocused ? Palette.onAccent : Palette.accent)
      }
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 18)
    .background(isFocused ? Color.white : Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var titleColor: Color {
    if isFocused { return Palette.onAccent }
    return isCurrent ? Palette.accent : Palette.primary
  }
}
