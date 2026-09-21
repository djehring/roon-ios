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
  @State private var photosHeld = false
  @State private var interaction = 0
  @State private var failedPhotos: Set<String> = []
  @State private var loadedPhoto: String?
  @State private var imageLoader = MontageImageLoader()

  private var frames: [MontageFrame] {
    capsule.montageFrames.filter { !failedPhotos.contains($0.id) }
  }
  private var frame: MontageFrame? {
    frames.isEmpty ? nil : frames[playback.index % frames.count]
  }
  private var running: Bool { !showingSources && !photosHeld }
  private var captions: CapsuleCaptions { capsule.request.options?.captions ?? .brief }
  private var motion: CapsuleMotion { capsule.request.options?.motion ?? .gentle }
  private var showsTrackTitle: Bool { capsule.request.options?.showsTrackTitle ?? false }
  private var secondsPerPhoto: Double { capsule.request.options?.pace.seconds ?? 8 }
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
    Group {
      if awaitingMontage { CinemaPreparationView(capsule: capsule) }
      else { montage }
    }
    .background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
    #if os(iOS)
    .statusBarHidden()
    #endif
  }

  private var montage: some View {
    GeometryReader { geometry in
      let compact = geometry.size.width < 600
      ZStack {
        Color.black
        if let frame {
          MontagePhotograph(image: frame.image, client: store.client, loader: imageLoader, moving: running,
            reduceMotion: reduceMotion,
            motion: motion, duration: secondsPerPhoto,
            loaded: { loadedPhoto = frame.id },
            failed: { failedPhotos.insert(frame.id) })
            .id(frame.id)
            .transition(.opacity)
          LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.85)],
            startPoint: .top, endPoint: .bottom)
        }
        VStack(alignment: .leading, spacing: 18) {
          HStack(alignment: .top) {
            if captions != .none || controlsVisible {
              VStack(alignment: .leading, spacing: 8) {
              Text(capsule.request.options?.mode == .period || capsule.request.options == nil ? "TIME CAPSULE" : "CINEMA").font(.caption.weight(.semibold)).tracking(5).foregroundStyle(Palette.accent)
              Text(capsule.contextLabel).font(compact ? .subheadline : .title3)
              }
            }
            Spacer()
            if controlsVisible {
              Button {
                store.cinema.libraryAfterViewer = true
                dismiss()
              } label: { Image(systemName: "rectangle.stack").padding(10) }
                .buttonStyle(.bordered).accessibilityLabel("Cinema playlists")
              Button { dismiss() } label: { Image(systemName: "xmark").padding(10) }
                .buttonStyle(.bordered).accessibilityLabel("Close montage")
            }
          }
          Spacer()
          if let frame {
            VStack(alignment: .leading, spacing: 10) {
              if captions != .none {
              Text([frame.scene.scope, frame.scene.dateLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
              Text(frame.scene.title)
                .font(.system(size: compact ? 30 : 48, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
              if captions == .detailed && !frame.scene.body.isEmpty {
                Text(frame.scene.body).font(compact ? .subheadline : .title3).lineLimit(4)
              }
              }
              if frames.count < capsule.minimumPictures {
                Text("Only \(frames.count) photograph(s) available · rebuild this montage for more pictures")
                  .font(.caption).foregroundStyle(Palette.accent)
              }
              if photosHeld {
                Label("Photograph held · the music continues", systemImage: "pause.fill")
                  .font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
              }
              if let message = playbackMessage {
                HStack(spacing: 8) {
                  if store.cinema.playing { ProgressView().tint(.white) }
                  Text(message).font(.caption)
                }
              }
              if !capsule.isPersonal {
                Text("\(frame.image.credit) · \(frame.image.license) · Image: \(frame.image.date)")
                  .font(.caption2).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
              }
            }
            .frame(maxWidth: 1000, alignment: .leading)
          } else {
            ContentUnavailableView("This montage needs pictures", systemImage: "photo.on.rectangle.angled",
              description: Text(capsule.isPersonal
                ? "These saved photos could not be loaded. Create a new montage from your Photos library."
                : failedPhotos.isEmpty
                  ? "Rebuild this capsule from Cinema to prepare a montage."
                  : "The archive pictures could not be loaded. Check the bridge connection, then reopen the montage."))
          }
          if controlsVisible || (showsTrackTitle && store.currentTrack != nil) {
            currentMusic(compact: compact)
          }
          if controlsVisible { controls(compact: compact) }
        }
        .padding(compact ? 24 : 48)
      }
      .clipped()
      .contentShape(Rectangle())
      .onTapGesture { revealControls() }
      #if !os(tvOS)
      .gesture(photoSwipe)
      #endif
      .accessibilityAction(named: "Show montage controls") { revealControls() }
      .accessibilityAction(named: "Next photograph") { movePhoto(1) }
      .accessibilityAction(named: "Previous photograph") { movePhoto(-1) }
      .accessibilityAction(named: photosHeld ? "Resume photographs" : "Hold photograph") { togglePhotoHold() }
    }
    .background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
    #if os(iOS)
    .statusBarHidden()
    #endif
    .animation(reduceMotion || motion == .still ? nil : .easeInOut(duration: 1.2), value: frame?.id)
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
        // Give each picture its chosen hold time after it has loaded.
        playback.advance(seconds: 1, playing: loadedPhoto == frame?.id, count: frames.count, secondsPerPhoto: secondsPerPhoto)
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
    }
    .onDisappear {
      store.cinema.playbackMemory.remember(playback, capsuleId: capsule.id, revision: capsule.createdAt)
    }
    #if os(tvOS)
    .onPlayPauseCommand { store.togglePlay(); revealControls() }
    .onMoveCommand { direction in
      switch direction {
      case .left: movePhoto(-1)
      case .right: movePhoto(1)
      default: revealControls()
      }
    }
    .onExitCommand { dismiss() }
    .focusable(!controlsVisible)
    #endif
  }

  private func currentMusic(compact: Bool) -> some View {
    HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text(store.currentTrack?.title ?? "Nothing playing")
          .font(compact ? .headline : .title2.weight(.semibold)).lineLimit(2)
          .accessibilityIdentifier("cinema-track-title")
        Text(store.currentTrack?.artist ?? store.selectedZone.name)
          .font(.subheadline).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
          .accessibilityIdentifier("cinema-track-artist")
      }
      Spacer(minLength: 0)
      if !compact && controlsVisible { Text(store.selectedZone.name).font(.subheadline) }
    }
  }

  private func controls(compact: Bool) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Divider().overlay(.white.opacity(0.2))
      transportRow("MUSIC") {
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
      }
      transportRow("PHOTOGRAPHS") {
        Group {
          Button { movePhoto(-1) } label: {
            Image(systemName: "backward.frame.fill").frame(width: 28, height: 28)
          }
          .accessibilityLabel("Previous photograph")
          .disabled(frames.count < 2)
          Button { togglePhotoHold() } label: {
            Image(systemName: photosHeld ? "play.rectangle.fill" : "pause.rectangle.fill")
              .frame(width: 28, height: 28)
          }
          .accessibilityLabel(photosHeld ? "Resume photographs" : "Hold photograph")
          .disabled(frames.isEmpty)
          Button { movePhoto(1) } label: {
            Image(systemName: "forward.frame.fill").frame(width: 28, height: 28)
          }
          .accessibilityLabel("Next photograph")
          .disabled(frames.count < 2)
        }
        Spacer(minLength: 0)
        if let position = photoPosition {
          Text(position).font(.caption).foregroundStyle(.white.opacity(0.65))
            .accessibilityLabel("Photograph \(position)")
        }
        if frame != nil {
          Button { showingSources = true; revealControls() } label: {
            Image(systemName: "info.circle").frame(width: 28, height: 28)
          }
          .accessibilityLabel("Photo and headline sources")
        }
      }
    }
  }

  private func transportRow(_ title: String, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.caption2.weight(.semibold)).tracking(3).foregroundStyle(.white.opacity(0.5))
      HStack(spacing: 16) { content() }.buttonStyle(.bordered)
    }
  }

  private var photoPosition: String? {
    guard frames.count > 1 else { return nil }
    return "\(playback.index % frames.count + 1) of \(frames.count)"
  }

  #if !os(tvOS)
  private var photoSwipe: some Gesture {
    DragGesture(minimumDistance: 30).onEnded { value in
      guard abs(value.translation.width) > abs(value.translation.height) else { return }
      movePhoto(value.translation.width < 0 ? 1 : -1)
    }
  }
  #endif

  /// Manual navigation gives the chosen photograph a full hold, so a swipe
  /// never lands on a picture that is about to change.
  private func movePhoto(_ offset: Int) {
    guard frames.count > 1 else { return }
    playback.move(offset, count: frames.count)
    revealControls()
  }

  private func togglePhotoHold() {
    photosHeld.toggle()
    revealControls()
  }

  private func revealControls() { controlsVisible = true; interaction += 1 }
}

/// Keep only a few decoded photographs in memory, including the next frame.
@MainActor
final class MontageImageLoader {
  static let previews = MontageImageLoader(maximumDimension: 800)
  private let maximumDimension: CGFloat
  private let cache = NSCache<NSString, UIImage>()

  init(maximumDimension: CGFloat = 2560) {
    self.maximumDimension = maximumDimension
    cache.countLimit = maximumDimension < 1000 ? 20 : 3
    cache.totalCostLimit = 64 * 1024 * 1024
  }

  func load(_ image: CapsuleImage, client: RoonAPIClient) async throws -> UIImage {
    if let cached = cache.object(forKey: image.file as NSString) { return cached }
    if let local = image.localFile {
      let data = try await PersonalCinemaStore.shared.imageData(local)
      guard let result = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
      cache.setObject(result, forKey: image.file as NSString, cost: (result.cgImage?.bytesPerRow ?? 0) * (result.cgImage?.height ?? 0))
      return result
    }
    guard let url = client.timeCapsuleImageURL(image.file) else { throw URLError(.badURL) }
    var request = URLRequest(url: url)
    request.timeoutInterval = 12
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
          let result = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: maximumDimension, height: maximumDimension)) else {
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
  let motion: CapsuleMotion
  let duration: Double
  let loaded: () -> Void
  let failed: () -> Void
  @State private var photograph: UIImage?
  @State private var motionSeconds: Double = 0
  private var animated: Bool { !reduceMotion && motion != .still }
  // Reverse smoothly and keep moving even when a montage has only one album cover.
  private var fraction: Double {
    let phase = (motionSeconds / max(1, duration)).truncatingRemainder(dividingBy: 2)
    return phase <= 1 ? phase : 2 - phase
  }
  private var direction: Double { image.file.utf8.reduce(0, { $0 + Int($1) }).isMultiple(of: 2) ? 1 : -1 }

  var body: some View {
    GeometryReader { geometry in
      Group {
        if let photograph {
          Image(uiImage: photograph).resizable().scaledToFit()
        } else { ProgressView("Loading photograph…").tint(.white) }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .scaleEffect(!animated ? 1 : 1 + fraction * (motion == .kenBurns ? 0.08 : 0.03))
      .offset(x: animated && motion == .kenBurns ? direction * fraction * geometry.size.width * 0.015 : 0,
        y: animated && motion == .kenBurns ? -direction * fraction * geometry.size.height * 0.01 : 0)
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
    .task(id: moving && animated && photograph != nil) {
      guard moving, animated, photograph != nil else { return }
      while !Task.isCancelled {
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
            if image.localFile == nil { sourceLink("View original · \(image.license)", url: image.sourceUrl) }
            if let license = URL(string: image.licenseUrl), license.scheme == "https" {
              sourceLink("Image licence", url: license)
            }
          }
          Divider()
          Text("Original search").font(.headline)
          Text(query).foregroundStyle(.secondary)
          Text(scene.image?.localFile == nil ? "AI-written summary based on the linked sources." : "Personal photo saved on this device. Not shared with AI or the bridge.").font(.caption).foregroundStyle(.secondary)
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
