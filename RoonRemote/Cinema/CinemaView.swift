import SwiftUI
import UIKit

struct CinemaView: View {
  let capsule: TimeCapsule
  @Environment(MockStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
  @State private var browsingIndex: Int?
  @State private var controlsVisible = true
  @State private var showingSources = false
  @State private var interaction = 0
  @State private var previousIdleTimerSetting = false

  private var liveIndex: Int? { capsule.sceneIndex(for: store.currentTrack) }
  private var index: Int { browsingIndex ?? liveIndex ?? 0 }
  private var scene: CapsuleScene? { capsule.scenes.indices.contains(index) ? capsule.scenes[index] : nil }
  private var displayedScene: CapsuleScene? {
    guard var scene else { return nil }
    scene.image = scene.image ?? capsule.contextImage
    return scene
  }

  var body: some View {
    GeometryReader { geometry in
      let portrait = geometry.size.width < geometry.size.height && geometry.size.width < 600
      let inset: CGFloat = portrait ? 24 : max(36, geometry.size.width * 0.05)
      ZStack {
        Color.black
        if let scene = displayedScene {
          CinemaBackdrop(scene: scene, client: store.client, artwork: artwork,
            playing: store.isPlaying && browsingIndex == nil, reduceMotion: reduceMotion)
            .id(scene.id)
            .transition(.opacity)
            .frame(width: geometry.size.width, height: portrait ? geometry.size.height * 0.57 : geometry.size.height)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(portrait ? 1 : 0.88)],
          startPoint: .top, endPoint: .bottom)
        if !controlsVisible {
          Button { revealControls() } label: {
            Color.clear.contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Show Cinema controls")
        }
        ScrollView(.vertical) {
          VStack(alignment: .leading, spacing: portrait ? 18 : 26) {
            header(portrait: portrait)
            Spacer(minLength: portrait ? 60 : 35)
            if let scene {
              caption(scene, portrait: portrait)
            } else {
              Text("No stories are available for this programme.").font(.title2)
            }
            if controlsVisible {
              controls(portrait: portrait)
                .transition(.opacity)
            }
            if let image = displayedScene?.image {
              Text("\(scene?.image == nil ? "Context photograph · " : "")\(image.credit) · \(image.license) · \(image.date)")
                .font(portrait ? .caption2 : .caption)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(3)
            }
          }
          .frame(minHeight: max(0, geometry.size.height - (portrait ? 48 : 88)))
          .padding(.horizontal, inset)
          .padding(.vertical, portrait ? 24 : 44)
        }
        .scrollDisabled(!portrait)
      }
      .clipped()
      .contentShape(Rectangle())
      .onTapGesture { revealControls() }
    }
    .background(.black)
    .foregroundStyle(.white)
    .preferredColorScheme(.dark)
    #if os(iOS)
    .statusBarHidden()
    #endif
    .animation(reduceMotion ? nil : .easeInOut(duration: 1.4), value: scene?.id)
    .animation(.easeInOut(duration: 0.25), value: controlsVisible)
    .sheet(isPresented: $showingSources) {
      if let scene = displayedScene { CinemaSourcesView(scene: scene, query: capsule.request.query) }
    }
    .task(id: interaction) {
      guard !voiceOver else { return }
      try? await Task.sleep(for: .seconds(8))
      guard !Task.isCancelled, !showingSources else { return }
      controlsVisible = false
    }
    .onChange(of: store.currentTrack?.id) { _, _ in revealControls() }
    .onChange(of: voiceOver) { _, enabled in if enabled { revealControls() } }
    .onAppear {
      previousIdleTimerSetting = UIApplication.shared.isIdleTimerDisabled
      UIApplication.shared.isIdleTimerDisabled = true
    }
    .onDisappear { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerSetting }
    #if os(tvOS)
    .onPlayPauseCommand { store.togglePlay(); revealControls() }
    .onMoveCommand { _ in revealControls() }
    .onExitCommand { dismiss() }
    .focusable(!controlsVisible)
    #endif
  }

  private var artwork: Data? {
    store.imageData(for: store.currentTrack?.imageKey, pixels: ArtworkCache.heroPixels)
  }

  private func header(portrait: Bool) -> some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 8) {
        Text("TIME CAPSULE").font(.caption.weight(.semibold)).tracking(5).foregroundStyle(Palette.accent)
        Text(capsule.contextLabel)
          .font(portrait ? .subheadline : .title3)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 20)
      if controlsVisible {
        Button { dismiss() } label: { Image(systemName: "xmark").padding(12) }
          .buttonStyle(.bordered)
          .accessibilityLabel("Close Cinema")
      }
    }
  }

  private func caption(_ scene: CapsuleScene, portrait: Bool) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text([scene.scope, scene.dateLabel].filter { !$0.isEmpty }.joined(separator: " · "))
        .font(.caption.weight(.medium)).foregroundStyle(Palette.accent)
      Text(scene.title)
        .font(.system(size: portrait ? 32 : 52, weight: .medium))
        .fixedSize(horizontal: false, vertical: true)
      Text(scene.body)
        .font(portrait ? .body : .title3)
        .foregroundStyle(.white.opacity(0.9))
        .fixedSize(horizontal: false, vertical: true)
      if browsingIndex != nil || liveIndex == nil {
        Text(browsingIndex != nil ? "Exploring stories · music continues" : "Play this capsule’s tracks to follow the music")
          .font(.caption).foregroundStyle(.white.opacity(0.65))
      }
    }
    .frame(maxWidth: 920, alignment: .leading)
  }

  private func controls(portrait: Bool) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) { storyControls }
        VStack(alignment: .leading, spacing: 12) { storyControls }
      }
      Divider().overlay(.white.opacity(0.2))
      HStack(spacing: 14) {
        Button { store.togglePlay(); revealControls() } label: {
          Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.bordered)
        .disabled(store.currentTrack == nil)
        .accessibilityLabel(store.isPlaying ? "Pause music" : "Play music")
        VStack(alignment: .leading, spacing: 4) {
          Text(store.currentTrack?.title ?? "Nothing playing").font(.headline).lineLimit(1)
          Text(store.currentTrack?.artist ?? "Choose a track in Roon").font(.subheadline).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
        }
        Spacer(minLength: 0)
        if !portrait {
          Label(store.selectedZone.name, systemImage: "hifispeaker.fill")
            .font(.subheadline).foregroundStyle(.white.opacity(0.7))
        }
      }
      if let track = store.currentTrack {
        ProgressView(value: min(1, max(0, track.progress)))
          .tint(Palette.accent)
          .accessibilityLabel("Music progress")
      }
    }
  }

  @ViewBuilder private var storyControls: some View {
    HStack(spacing: 12) {
      Button { browse(-1) } label: { Image(systemName: "chevron.left") }
        .accessibilityLabel("Previous story")
      Text("\(capsule.scenes.isEmpty ? 0 : index + 1) / \(capsule.scenes.count)").font(.caption.monospacedDigit())
      Button { browse(1) } label: { Image(systemName: "chevron.right") }
        .accessibilityLabel("Next story")
    }
    .buttonStyle(.bordered)
    .disabled(capsule.scenes.isEmpty)
    Button {
      browsingIndex = index
      showingSources = true
      revealControls()
    } label: { Label("Explore this story", systemImage: "text.book.closed") }
      .buttonStyle(.borderedProminent)
      .tint(Palette.accent)
      .foregroundStyle(Palette.onAccent)
      .disabled(scene == nil)
    if browsingIndex != nil && liveIndex != nil {
      Button("Return to live") { browsingIndex = nil; revealControls() }
        .buttonStyle(.bordered)
    }
  }

  private func browse(_ direction: Int) {
    guard !capsule.scenes.isEmpty else { return }
    browsingIndex = (index + direction + capsule.scenes.count) % capsule.scenes.count
    revealControls()
  }
  private func revealControls() { controlsVisible = true; interaction += 1 }
}

private struct CinemaBackdrop: View {
  let scene: CapsuleScene
  let client: RoonAPIClient
  let artwork: Data?
  let playing: Bool
  let reduceMotion: Bool
  @State private var motionSeconds = 0

  var body: some View {
    GeometryReader { geometry in
      Group {
        if let asset = scene.image {
          AsyncImage(url: client.timeCapsuleImageURL(asset.file)) { image in
            image.resizable().scaledToFill()
          } placeholder: { fallback }
          .accessibilityLabel(asset.description)
        } else { fallback }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .scaleEffect(reduceMotion ? 1 : 1 + Double(motionSeconds) * 0.0015)
      .clipped()
      .task(id: playing && !reduceMotion) {
        guard !reduceMotion, playing else { return }
        while motionSeconds < 30 && !Task.isCancelled {
          do { try await Task.sleep(for: .seconds(1)) } catch { return }
          withAnimation(.linear(duration: 1)) { motionSeconds += 1 }
        }
      }
    }
    .accessibilityHidden(true)
  }

  @ViewBuilder private var fallback: some View {
    if let artwork, let image = UIImage(data: artwork) {
      Image(uiImage: image).resizable().scaledToFill().blur(radius: 28).opacity(0.5)
    } else { Color(red: 0.075, green: 0.07, blue: 0.06) }
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
