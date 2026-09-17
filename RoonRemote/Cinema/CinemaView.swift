import SwiftUI
import UIKit

struct CinemaView: View {
  let capsule: TimeCapsule
  @Environment(MockStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
  @State private var playback = MontagePlayback()
  @State private var controlsVisible = true
  @State private var showingSources = false
  @State private var interaction = 0
  @State private var previousIdleTimerSetting = false
  @State private var failedPhotos: Set<String> = []
  @State private var loadedPhoto: String?
  @State private var imageLoader = MontageImageLoader()

  private var frames: [MontageFrame] {
    capsule.montageFrames.filter { !failedPhotos.contains($0.id) }
  }
  private var frame: MontageFrame? {
    frames.isEmpty ? nil : frames[playback.index % frames.count]
  }
  private var running: Bool { !showingSources }
  private var awaitingMontage: Bool { store.cinema.preparation?.placeholder.id == capsule.id }
  private var playbackMessage: String? {
    let cinema = store.cinema
    guard cinema.playbackCapsuleId == capsule.id
      || (cinema.preparation?.result?.id == capsule.id && cinema.playbackCapsuleId == cinema.preparation?.placeholder.id)
      else { return nil }
    return cinema.playbackMessage
  }
  private var sourceScene: CapsuleScene? {
    guard let frame else { return nil }
    var scene = frame.scene
    scene.image = frame.image
    return scene
  }

  var body: some View {
    GeometryReader { geometry in
      let compact = geometry.size.width < 600
      ZStack {
        Color.black
        if let frame {
          MontagePhotograph(image: frame.image, client: store.client, loader: imageLoader, moving: running,
            reduceMotion: reduceMotion,
            loaded: { loadedPhoto = frame.id },
            failed: { failedPhotos.insert(frame.id) })
            .id(frame.id)
            .transition(.opacity)
          LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.85)],
            startPoint: .top, endPoint: .bottom)
        }
        VStack(alignment: .leading, spacing: 18) {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
              Text("TIME CAPSULE").font(.caption.weight(.semibold)).tracking(5).foregroundStyle(Palette.accent)
              Text(capsule.contextLabel).font(compact ? .subheadline : .title3)
            }
            Spacer()
            if controlsVisible {
              Button {
                store.cinema.libraryAfterViewer = true
                dismiss()
              } label: { Image(systemName: "rectangle.stack").padding(10) }
                .buttonStyle(.bordered).accessibilityLabel("Saved Time Capsules")
              Button { dismiss() } label: { Image(systemName: "xmark").padding(10) }
                .buttonStyle(.bordered).accessibilityLabel("Close montage")
            }
          }
          Spacer()
          if let frame {
            VStack(alignment: .leading, spacing: 10) {
              Text([frame.scene.scope, frame.scene.dateLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
              Text(frame.scene.title)
                .font(.system(size: compact ? 30 : 48, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
              if frames.count < 3 {
                Text("Only \(frames.count) photograph(s) available · rebuild this montage for more pictures")
                  .font(.caption).foregroundStyle(Palette.accent)
              }
              if let message = playbackMessage {
                HStack(spacing: 8) {
                  if store.cinema.playing { ProgressView().tint(.white) }
                  Text(message).font(.caption)
                }
              }
              Text("\(frame.image.credit) · \(frame.image.license) · Photo: \(frame.image.date)")
                .font(.caption2).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
            }
            .frame(maxWidth: 1000, alignment: .leading)
          } else if awaitingMontage {
            VStack(alignment: .leading, spacing: 16) {
              if let error = store.cinema.preparationError {
                Label("Montage could not be prepared", systemImage: "exclamationmark.triangle")
                  .font(.title2.weight(.semibold))
                Text(error).foregroundStyle(.secondary)
              } else {
                ProgressView().tint(Palette.accent)
                Text("Preparing Time Capsule").font(.title2.weight(.semibold))
                Text(store.cinema.preparationMessage).foregroundStyle(.secondary)
              }
              if let message = playbackMessage { Text(message).font(.subheadline) }
            }
            .frame(maxWidth: 650, alignment: .leading)
            Spacer()
          } else {
            ContentUnavailableView("This montage needs photographs", systemImage: "photo.on.rectangle.angled",
              description: Text(failedPhotos.isEmpty
                ? "Rebuild this capsule from Time Capsules to prepare a photo montage."
                : "The archive pictures could not be loaded. Check the bridge connection, then reopen the montage."))
          }
          if controlsVisible { controls(compact: compact) }
        }
        .padding(compact ? 24 : 48)
      }
      .clipped()
      .contentShape(Rectangle())
      .onTapGesture { revealControls() }
      .accessibilityAction(named: "Show montage controls") { revealControls() }
    }
    .background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
    #if os(iOS)
    .statusBarHidden()
    #endif
    .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: frame?.id)
    .animation(.easeInOut(duration: 0.2), value: controlsVisible)
    .sheet(isPresented: $showingSources) {
      if let scene = sourceScene { CinemaSourcesView(scene: scene, query: capsule.request.query) }
    }
    .task(id: frame?.id) {
      guard frames.count > 1 else { return }
      let next = frames[(playback.index + 1) % frames.count].image
      _ = try? await imageLoader.load(next, client: store.client)
    }
    .task(id: running) {
      guard running else { return }
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        // Start each eight-second hold only once the photograph has loaded.
        playback.advance(seconds: 1, playing: loadedPhoto == frame?.id, count: frames.count)
      }
    }
    .task(id: interaction) {
      guard !voiceOver, !awaitingMontage else { return }
      do { try await Task.sleep(for: .seconds(6)) } catch { return }
      guard !showingSources else { return }
      controlsVisible = false
    }
    .onChange(of: voiceOver) { _, enabled in if enabled { revealControls() } }
    .onAppear {
      playback = store.cinema.playbackMemory.resume(capsuleId: capsule.id, revision: capsule.createdAt)
      previousIdleTimerSetting = UIApplication.shared.isIdleTimerDisabled
      UIApplication.shared.isIdleTimerDisabled = true
    }
    .onDisappear {
      store.cinema.playbackMemory.remember(playback, capsuleId: capsule.id, revision: capsule.createdAt)
      UIApplication.shared.isIdleTimerDisabled = previousIdleTimerSetting
    }
    #if os(tvOS)
    .onPlayPauseCommand { store.togglePlay(); revealControls() }
    .onMoveCommand { _ in revealControls() }
    .onExitCommand { dismiss() }
    .focusable(!controlsVisible)
    #endif
  }

  private func controls(compact: Bool) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Divider().overlay(.white.opacity(0.2))
      HStack(spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text(store.currentTrack?.title ?? "Nothing playing").font(.headline).lineLimit(1)
          Text(store.currentTrack?.artist ?? store.selectedZone.name)
            .font(.subheadline).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
        }
        Spacer(minLength: 0)
        if !compact { Text(store.selectedZone.name).font(.subheadline) }
      }
      HStack(spacing: 16) {
        Group {
          Button { store.previous(); revealControls() } label: {
            Image(systemName: "backward.end.fill").frame(width: 28, height: 28)
          }
          .accessibilityLabel("Previous track")
          Button { store.togglePlay(); revealControls() } label: {
            Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").frame(width: 28, height: 28)
          }
          .accessibilityLabel(store.isPlaying ? "Pause music" : "Play music")
          Button { store.skip(); revealControls() } label: {
            Image(systemName: "forward.end.fill").frame(width: 28, height: 28)
          }
          .accessibilityLabel("Next track")
        }
        .disabled(store.currentTrack == nil)
        Spacer(minLength: 0)
        if frame != nil {
          Button { showingSources = true; revealControls() } label: {
            Image(systemName: "info.circle").frame(width: 28, height: 28)
          }
          .accessibilityLabel("Photo and headline sources")
        }
      }
      .buttonStyle(.bordered)
    }
  }

  private func revealControls() { controlsVisible = true; interaction += 1 }
}

/// Keep only a few decoded photographs in memory, including the next frame.
@MainActor
private final class MontageImageLoader {
  private let cache = NSCache<NSString, UIImage>()

  init() {
    cache.countLimit = 3
    cache.totalCostLimit = 64 * 1024 * 1024
  }

  func load(_ image: CapsuleImage, client: RoonAPIClient) async throws -> UIImage {
    if let cached = cache.object(forKey: image.file as NSString) { return cached }
    guard let url = client.timeCapsuleImageURL(image.file) else { throw URLError(.badURL) }
    var request = URLRequest(url: url)
    request.timeoutInterval = 12
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
          let result = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 2560, height: 2560)) else {
      throw URLError(.cannotDecodeContentData)
    }
    try Task.checkCancellation()
    let cost = (result.cgImage?.bytesPerRow ?? 0) * (result.cgImage?.height ?? 0)
    cache.setObject(result, forKey: image.file as NSString, cost: cost)
    return result
  }
}

private struct MontagePhotograph: View {
  let image: CapsuleImage
  let client: RoonAPIClient
  let loader: MontageImageLoader
  let moving: Bool
  let reduceMotion: Bool
  let loaded: () -> Void
  let failed: () -> Void
  @State private var photograph: UIImage?
  @State private var motionSeconds = 0

  var body: some View {
    GeometryReader { geometry in
      Group {
        if let photograph {
          Image(uiImage: photograph).resizable().scaledToFit()
        } else { ProgressView("Loading photograph…").tint(.white) }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .scaleEffect(reduceMotion ? 1 : 1 + Double(motionSeconds) * 0.002)
      .clipped()
    }
    .accessibilityHidden(true)
    .task(id: image.file) {
      do {
        let result = try await loader.load(image, client: client)
        guard !Task.isCancelled else { return }
        photograph = result
        loaded()
      } catch {
        guard !Task.isCancelled else { return }
        failed()
      }
    }
    .task(id: moving && !reduceMotion) {
      guard moving, !reduceMotion else { return }
      while motionSeconds < 15 {
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        withAnimation(.linear(duration: 1)) { motionSeconds += 1 }
      }
    }
  }
}

private struct CinemaSourcesView: View {
  let scene: CapsuleScene
  let query: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text(scene.title).font(.title.bold())
          Text(scene.body).font(.title3)
          Text([scene.scope, scene.dateLabel].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(.secondary)
          Text("Sources").font(.headline)
          ForEach(scene.sources, id: \.self) { source in sourceLink(source.title, url: source.url) }
          if let image = scene.image {
            Divider()
            Text("Photograph").font(.headline)
            Text(image.description)
            Text("\(image.credit) · \(image.date)")
            sourceLink("View original · \(image.license)", url: image.sourceUrl)
            if let license = URL(string: image.licenseUrl), license.scheme == "https" {
              sourceLink("Image licence", url: license)
            }
          }
          Divider()
          Text("Original search").font(.headline)
          Text(query).foregroundStyle(.secondary)
          Text("AI-written summary based on the linked sources.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 850, alignment: .leading)
        .padding(32)
        .frame(maxWidth: .infinity)
      }
      .navigationTitle("Story & sources")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    .tint(Palette.accent)
  }

  @ViewBuilder private func sourceLink(_ title: String, url: URL) -> some View {
    #if os(tvOS)
    VStack(alignment: .leading, spacing: 6) {
      Text(title).foregroundStyle(Palette.accent)
      Text(url.absoluteString).font(.caption).foregroundStyle(.secondary)
    }
    #else
    Link(title, destination: url)
    #endif
  }
}
