import SwiftUI

/// First-paint cover while the app finds the Core. A record travels a
/// short route toward the speakers — the wait should feel like arrival,
/// not a spinner.
struct FindingServerOverlay: View {
  var title: String = Self.defaultTitle

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  #if os(iOS)
  @Environment(\.horizontalSizeClass) private var hSize
  #endif

  var body: some View {
    let metrics = currentMetrics
    ZStack {
      Palette.background.ignoresSafeArea()
      VStack(spacing: metrics.copySpacing) {
        FindingServerJourney(reduceMotion: reduceMotion, metrics: metrics)
          .frame(width: metrics.canvas.width, height: metrics.canvas.height)
        VStack(spacing: metrics.subtitleSpacing) {
          Text(title)
            .font(.system(size: metrics.titleSize, weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.primary)
          if metrics.showsSubtitle {
            Text("Looking on your network")
              .font(.system(size: metrics.subtitleSize))
              .foregroundStyle(Palette.secondary)
          }
        }
      }
      .padding(metrics.padding)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
  }

  static var defaultTitle: String {
    #if os(watchOS)
    "Finding your music"
    #else
    "Finding your music server"
    #endif
  }

  private var currentMetrics: FindingServerMetrics {
    #if os(tvOS)
    .tv
    #elseif os(watchOS)
    .watch
    #elseif os(iOS)
    hSize == .regular ? .tablet : .phone
    #else
    .phone
    #endif
  }
}

private struct FindingServerMetrics {
  var canvas: CGSize
  var disc: CGFloat
  var speaker: CGFloat
  var titleSize: CGFloat
  var subtitleSize: CGFloat
  var copySpacing: CGFloat
  var subtitleSpacing: CGFloat
  var padding: CGFloat
  var showsSubtitle: Bool

  static let phone = FindingServerMetrics(
    canvas: CGSize(width: 280, height: 150),
    disc: 36,
    speaker: 34,
    titleSize: 22,
    subtitleSize: 16,
    copySpacing: 28,
    subtitleSpacing: 8,
    padding: 28,
    showsSubtitle: true
  )

  static let tablet = FindingServerMetrics(
    canvas: CGSize(width: 360, height: 190),
    disc: 46,
    speaker: 42,
    titleSize: 28,
    subtitleSize: 17,
    copySpacing: 32,
    subtitleSpacing: 10,
    padding: 36,
    showsSubtitle: true
  )

  static let tv = FindingServerMetrics(
    canvas: CGSize(width: 560, height: 260),
    disc: 68,
    speaker: 64,
    titleSize: 38,
    subtitleSize: 22,
    copySpacing: 40,
    subtitleSpacing: 12,
    padding: 48,
    showsSubtitle: true
  )

  static let watch = FindingServerMetrics(
    canvas: CGSize(width: 130, height: 72),
    disc: 20,
    speaker: 18,
    titleSize: 13,
    subtitleSize: 11,
    copySpacing: 8,
    subtitleSpacing: 4,
    padding: 8,
    showsSubtitle: false
  )
}

private struct FindingServerJourney: View {
  let reduceMotion: Bool
  let metrics: FindingServerMetrics

  var body: some View {
    timeline
  }

  @ViewBuilder
  private var timeline: some View {
    if reduceMotion {
      scene(progress: 0.62, pulse: 0.35)
    } else {
      #if os(watchOS)
      TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { context in
        scene(at: context.date)
      }
      #else
      TimelineView(.animation) { context in
        scene(at: context.date)
      }
      #endif
    }
  }

  private func scene(at date: Date) -> some View {
    let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.2) / 3.2
    let travel = easeInOut(cycle)
    let fade: Double
    if cycle < 0.08 {
      fade = cycle / 0.08
    } else if cycle > 0.9 {
      fade = max(0, (1 - cycle) / 0.1)
    } else {
      fade = 1
    }
    let pulse = 0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate * 2.1)
    return scene(progress: travel, pulse: pulse, discOpacity: fade)
  }

  private func scene(progress: Double, pulse: Double, discOpacity: Double = 1) -> some View {
    let size = metrics.canvas
    let t = CGFloat(progress)
    let discPoint = FindingServerRoute.point(t: t, in: size, speakerInset: metrics.speaker)
    let angle = FindingServerRoute.angle(t: t, in: size, speakerInset: metrics.speaker)
    let destination = FindingServerRoute.destination(in: size, speakerInset: metrics.speaker)

    return ZStack {
      rings(at: destination, pulse: pulse)
      route(in: size)
      notes(progress: t, in: size)
      FindingVinyl(size: metrics.disc)
        .rotationEffect(angle + .degrees(progress * 540))
        .position(discPoint)
        .opacity(discOpacity)
      Image(systemName: "hifispeaker.2.fill")
        .font(.system(size: metrics.speaker, weight: .light))
        .foregroundStyle(Palette.accent)
        .scaleEffect(1 + 0.04 * pulse)
        .position(destination)
    }
  }

  private func route(in size: CGSize) -> some View {
    FindingServerRoute.shape(in: size, speakerInset: metrics.speaker)
      .stroke(
        Palette.accent.opacity(0.28),
        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 7])
      )
  }

  private func rings(at center: CGPoint, pulse: Double) -> some View {
    ZStack {
      ForEach(0..<2, id: \.self) { index in
        let spread = 0.7 + Double(index) * 0.35 + pulse * 0.25
        Circle()
          .stroke(Palette.accent.opacity(0.18 - Double(index) * 0.05), lineWidth: 1.5)
          .frame(
            width: metrics.speaker * 2.2 * spread,
            height: metrics.speaker * 2.2 * spread
          )
          .position(center)
      }
    }
  }

  @ViewBuilder
  private func notes(progress: CGFloat, in size: CGSize) -> some View {
    let first = FindingServerRoute.point(
      t: max(0, progress - 0.18),
      in: size,
      speakerInset: metrics.speaker
    )
    let second = FindingServerRoute.point(
      t: max(0, progress - 0.32),
      in: size,
      speakerInset: metrics.speaker
    )
    Image(systemName: "music.note")
      .font(.system(size: metrics.disc * 0.42, weight: .regular))
      .foregroundStyle(Palette.accent.opacity(0.55))
      .offset(y: -metrics.disc * 0.7)
      .position(first)
      .opacity(progress > 0.2 ? 0.85 : 0)
    Image(systemName: "music.note")
      .font(.system(size: metrics.disc * 0.34, weight: .regular))
      .foregroundStyle(Palette.accent.opacity(0.35))
      .offset(y: -metrics.disc * 1.05)
      .position(second)
      .opacity(progress > 0.35 ? 0.7 : 0)
  }

  private func easeInOut(_ t: Double) -> Double {
    t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
  }
}

private enum FindingServerRoute {
  static func start(in size: CGSize) -> CGPoint {
    CGPoint(x: 10, y: size.height * 0.64)
  }

  static func control(in size: CGSize) -> CGPoint {
    CGPoint(x: size.width * 0.46, y: size.height * 0.16)
  }

  static func destination(in size: CGSize, speakerInset: CGFloat) -> CGPoint {
    CGPoint(x: size.width - speakerInset * 0.15, y: size.height * 0.56)
  }

  static func point(t: CGFloat, in size: CGSize, speakerInset: CGFloat) -> CGPoint {
    let p0 = start(in: size)
    let p1 = control(in: size)
    let p2 = destination(in: size, speakerInset: speakerInset)
    let u = 1 - t
    return CGPoint(
      x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
      y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y
    )
  }

  static func angle(t: CGFloat, in size: CGSize, speakerInset: CGFloat) -> Angle {
    let delta: CGFloat = 0.02
    let a = point(t: max(0, t - delta), in: size, speakerInset: speakerInset)
    let b = point(t: min(1, t + delta), in: size, speakerInset: speakerInset)
    return Angle(radians: Double(atan2(b.y - a.y, b.x - a.x)))
  }

  static func shape(in size: CGSize, speakerInset: CGFloat) -> Path {
    var path = Path()
    path.move(to: start(in: size))
    path.addQuadCurve(
      to: destination(in: size, speakerInset: speakerInset),
      control: control(in: size)
    )
    return path
  }
}

private struct FindingVinyl: View {
  var size: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .fill(Color(hex: 0x161618))
      Circle()
        .stroke(Palette.accent.opacity(0.45), lineWidth: max(1.5, size * 0.045))
      Circle()
        .stroke(Palette.accent.opacity(0.16), lineWidth: 1)
        .padding(size * 0.16)
      Circle()
        .stroke(Palette.accent.opacity(0.12), lineWidth: 1)
        .padding(size * 0.26)
      Circle()
        .fill(Palette.accent)
        .frame(width: size * 0.3, height: size * 0.3)
      Circle()
        .fill(Palette.background)
        .frame(width: size * 0.08, height: size * 0.08)
    }
    .frame(width: size, height: size)
    .shadow(color: .black.opacity(0.28), radius: size * 0.12, y: size * 0.08)
  }
}
