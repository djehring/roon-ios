import SwiftUI

/// Interactive now-playing scrubber with a Roon-style thumb.
struct ProgressScrubber: View {
  let track: Track
  var onSeek: (Double) -> Void

  @State private var scrubProgress: Double?
  @State private var thumbScale: CGFloat = 1

  private var displayedProgress: Double {
    scrubProgress ?? track.progress
  }

  private var displayedPosition: String {
    if let scrubProgress, let duration = track.durationSeconds {
      return TimeCode.string(from: duration * scrubProgress)
    }
    return track.position
  }

  private var displayedRemaining: String {
    if let duration = track.durationSeconds {
      let progress = scrubProgress ?? track.progress
      return TimeCode.string(from: max(0, duration * (1 - progress)))
    }
    return track.remaining
  }

  var body: some View {
    VStack(spacing: 6) {
      GeometryReader { geo in
        let width = max(geo.size.width, 1)
        let x = width * displayedProgress
        ZStack(alignment: .leading) {
          Capsule()
            .fill(Palette.hairline)
            .frame(height: 4)
          Capsule()
            .fill(Palette.accent)
            .frame(width: max(4, x), height: 4)
          Circle()
            .fill(Color.white)
            .overlay {
              Circle().stroke(Palette.hairline, lineWidth: 0.5)
            }
            .frame(width: 16, height: 16)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .scaleEffect(thumbScale)
            .offset(x: max(0, min(width - 16, x - 8)))
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              guard track.isSeekable else { return }
              scrubProgress = min(1, max(0, value.location.x / width))
              withAnimation(.easeOut(duration: 0.12)) { thumbScale = 1.25 }
            }
            .onEnded { value in
              guard track.isSeekable else { return }
              let progress = min(1, max(0, value.location.x / width))
              scrubProgress = progress
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
              onSeek(progress)
              withAnimation(.easeOut(duration: 0.12)) { thumbScale = 1 }
              Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                if scrubProgress == progress {
                  scrubProgress = nil
                }
              }
            }
        )
      }
      .frame(height: 28)
      .opacity(track.isSeekable ? 1 : 0.55)

      HStack {
        Text(displayedPosition)
        Spacer()
        Text(displayedRemaining)
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(Palette.tertiary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Playback position")
    .accessibilityValue(displayedPosition)
    .accessibilityAdjustableAction { direction in
      guard track.isSeekable else { return }
      let step = direction == .increment ? 0.05 : -0.05
      onSeek(min(1, max(0, track.progress + step)))
    }
  }
}
