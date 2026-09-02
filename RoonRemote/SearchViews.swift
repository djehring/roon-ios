import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SearchTabView: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    @Bindable var store = store
    NavigationStack {
      VStack(spacing: 0) {
        Picker("Search", selection: $store.searchSegment) {
          Text("AI").tag(SearchSegment.ai)
          Text("Camera").tag(SearchSegment.camera)
        }
        .pickerStyle(.segmented)
        .padding(16)
        Group {
          switch store.searchSegment {
          case .ai: AISearchView()
          case .camera: CameraSearchView()
          }
        }
      }
      .background(Palette.background)
      .navigationTitle("Search")
    }
  }
}

struct AISearchView: View {
  var regularWidth = false

  @Environment(MockStore.self) private var store
  @State private var recorder = VoiceRecorder()
  @State private var selectedResultID: SuggestedTrack.ID?
  @FocusState private var queryFocused: Bool

  var body: some View {
    Group {
      if regularWidth {
        HStack(spacing: 0) {
          searchContent
            .frame(maxWidth: 620)
          Divider()
            .background(Palette.hairline)
          resultDetail
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      } else {
        searchContent
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") { queryFocused = false }
      }
    }
    .onChange(of: store.aiResults.map(\.id)) { _, ids in
      selectedResultID = SearchSelection.resolved(
        current: selectedResultID,
        available: ids
      )
    }
  }

  private var searchContent: some View {
    @Bindable var store = store
    return VStack(spacing: 12) {
      HStack {
        TextField("What would you like to listen to?", text: $store.aiQuery)
          .textFieldStyle(.plain)
          .padding(12)
          .background(Palette.surface)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .focused($queryFocused)
          .submitLabel(.search)
          .onSubmit { search() }
        Button {
          queryFocused = false
          Task { await toggleVoice() }
        } label: {
          Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
            .frame(width: 44, height: 44)
            .background(Palette.surface)
            .clipShape(Circle())
            .foregroundStyle(recorder.isRecording ? Color.red : Palette.primary)
        }
        Button("Go") {
          search()
        }
        .foregroundStyle(Palette.accent)
        .padding(.trailing, 4)
        .disabled(!store.canSubmitAISearch)
      }
      .padding(.horizontal, 16)

      if let error = store.aiError {
        Text(error)
          .font(.footnote)
          .foregroundStyle(.red.opacity(0.85))
          .padding(.horizontal, 16)
      }

      if !store.aiLoading {
        Button("Play selected tracks") {
          queryFocused = false
          store.playAIResults()
        }
        .buttonStyle(GoldFillButton())
        .padding(.horizontal, 16)
        .disabled(store.aiResults.isEmpty)
      }

      if store.aiLoading {
        Spacer()
        ProgressView().tint(Palette.accent)
        Spacer()
      } else {
        List {
          ForEach($store.aiResults) { $track in
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: "line.3.horizontal")
                .foregroundStyle(Palette.tertiary)
              VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                Text("\(track.artist)  ·  \(track.album)")
                  .font(.footnote)
                  .foregroundStyle(Palette.secondary)
                if track.corrected {
                  Label("Album was corrected", systemImage: "sparkle")
                    .font(.caption)
                    .foregroundStyle(Palette.accent)
                }
                if let error = track.error {
                  Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.8))
                }
              }
              Spacer(minLength: 0)
              if regularWidth, track.id == resolvedResultID {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(Palette.accent)
              }
            }
            .contentShape(Rectangle())
            .onTapGesture {
              if regularWidth {
                selectedResultID = track.id
              }
            }
            .listRowBackground(
              regularWidth && track.id == resolvedResultID
                ? Palette.accent.opacity(0.12)
                : Palette.surface
            )
          }
          .onDelete { store.aiResults.remove(atOffsets: $0) }
          .onMove { store.aiResults.move(fromOffsets: $0, toOffset: $1) }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
      }
    }
  }

  @ViewBuilder
  private var resultDetail: some View {
    if let track = store.aiResults.first(where: { $0.id == resolvedResultID }) {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          CoverArt(title: track.album, corner: 18)
            .frame(maxWidth: 320)
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(0.28), radius: 24, y: 12)

          VStack(alignment: .leading, spacing: 8) {
            Text(track.title)
              .font(.largeTitle.bold())
            Text(track.artist)
              .font(.title2)
              .foregroundStyle(Palette.secondary)
            Text(track.album)
              .font(.title3)
              .foregroundStyle(Palette.tertiary)
          }

          if track.corrected {
            Label("Album was corrected", systemImage: "sparkles")
              .foregroundStyle(Palette.accent)
          }
          if let error = track.error {
            Label(error, systemImage: "exclamationmark.circle")
              .foregroundStyle(.red.opacity(0.85))
          } else {
            Label("Included in the play selection", systemImage: "checkmark.circle")
              .foregroundStyle(Palette.secondary)
          }
        }
        .frame(maxWidth: 440, alignment: .leading)
        .padding(36)
      }
    } else {
      ContentUnavailableView(
        "Ask for some music",
        systemImage: "sparkles",
        description: Text("Describe a mood, artist, era, or anything else you want to hear.")
      )
    }
  }

  private var resolvedResultID: SuggestedTrack.ID? {
    SearchSelection.resolved(
      current: selectedResultID,
      available: store.aiResults.map(\.id)
    )
  }

  private func search() {
    queryFocused = false
    store.runAISearch()
  }

  private func toggleVoice() async {
    do {
      if let data = try await recorder.toggle() {
        store.transcribeAI(audio: data)
      }
    } catch {
      store.aiError = error.localizedDescription
    }
  }
}

@MainActor
@Observable
final class VoiceRecorder {
  var isRecording = false
  private var recorder: AVAudioRecorder?
  private var fileURL: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("roon-ai.m4a")
  }

  func toggle() async throws -> Data? {
    if isRecording {
      recorder?.stop()
      isRecording = false
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      HardwareVolumeBridge.shared.setActive(true)
      return try Data(contentsOf: fileURL)
    }
    let granted = await AVAudioApplication.requestRecordPermission()
    guard granted else {
      throw RoonAPIError.httpStatus(403, "Microphone permission is off.")
    }
    HardwareVolumeBridge.shared.setActive(false)
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
    try session.setActive(true)
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
      AVSampleRateKey: 44100,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
    let next = try AVAudioRecorder(url: fileURL, settings: settings)
    next.record()
    recorder = next
    isRecording = true
    return nil
  }
}

struct CameraSearchView: View {
  var regularWidth = false

  @Environment(MockStore.self) private var store
  @State private var pickerItem: PhotosPickerItem?
  @State private var showSourcePicker = false
  @State private var showCamera = false
  @State private var showLibrary = false
  @State private var pickedImage: Data?
  @FocusState private var hintFocused: Bool

  var body: some View {
    Group {
      if regularWidth {
        HStack(spacing: 0) {
          ScrollView {
            capturePanel
              .frame(maxWidth: 520)
              .padding(32)
          }
          .frame(maxWidth: .infinity)

          Divider()
            .background(Palette.hairline)

          ScrollView {
            resultsPanel
              .frame(maxWidth: 520)
              .padding(32)
          }
          .frame(maxWidth: .infinity)
        }
      } else {
        ScrollView {
          VStack(spacing: 20) {
            capturePanel
            if !store.recognizedAlbums.isEmpty {
              resultsPanel
            }
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 24)
        }
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .confirmationDialog("Cover image", isPresented: $showSourcePicker, titleVisibility: .visible) {
      Button("Take photo") { showCamera = true }
      Button("Choose from library") { showLibrary = true }
      Button("Cancel", role: .cancel) {}
    }
    .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images)
    .onChange(of: pickerItem) { _, item in
      guard let item else { return }
      hintFocused = false
      Task { await loadPickedImage(item) }
    }
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") { hintFocused = false }
      }
    }
    .sheet(isPresented: $showCamera) {
      CameraPicker { data in
        applyPickedImage(data)
      }
      .ignoresSafeArea()
    }
  }

  private var capturePanel: some View {
    @Bindable var store = store
    return VStack(spacing: 18) {
      Button {
        hintFocused = false
        showSourcePicker = true
      } label: {
        ZStack {
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Palette.surface)
          if let pickedImage {
            CoverArt(title: "cover", image: pickedImage, corner: 14)
              .padding(28)
          } else {
            VStack(spacing: 12) {
              Image(systemName: "camera.fill")
                .font(.system(size: regularWidth ? 46 : 34))
                .foregroundStyle(Palette.accent)
              Text("Take or choose a cover")
                .font(regularWidth ? .title3 : .body)
                .foregroundStyle(Palette.secondary)
            }
          }
        }
        .aspectRatio(regularWidth ? 1 : nil, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .frame(height: regularWidth ? nil : 220)
      }
      .buttonStyle(.plain)

      TextField("Album description (optional)", text: $store.cameraHint)
        .padding(14)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .focused($hintFocused)
        .submitLabel(.done)
        .onSubmit { hintFocused = false }

      if let error = store.aiError, store.searchSegment == .camera {
        Text(error)
          .font(.footnote)
          .foregroundStyle(.red.opacity(0.85))
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      if store.recognizedAlbums.isEmpty {
        Button {
          hintFocused = false
          store.recognizeAlbum(
            image: pickedImage,
            mimeType: pickedImage == nil ? nil : "image/jpeg"
          )
        } label: {
          if store.recognizeLoading {
            HStack(spacing: 10) {
              ProgressView()
                .progressViewStyle(.circular)
                .tint(Palette.onAccent)
              Text("Recognising…")
            }
          } else {
            Text("Recognize album")
          }
        }
        .buttonStyle(GoldFillButton())
        .disabled(
          store.recognizeLoading || (pickedImage == nil && store.cameraHint.isEmpty)
        )

        if store.recognizeLoading {
          Text("Reading the cover and searching your library. This can take a moment.")
            .font(.footnote)
            .foregroundStyle(Palette.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
      } else {
        Button("Search again") {
          resetSearch()
        }
        .foregroundStyle(Palette.accent)
      }
    }
  }

  @ViewBuilder
  private var resultsPanel: some View {
    if store.recognizeLoading {
      VStack(spacing: 14) {
        ProgressView()
          .tint(Palette.accent)
        Text("Recognising the cover…")
          .foregroundStyle(Palette.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 420)
    } else if store.recognizedAlbums.isEmpty {
      ContentUnavailableView(
        "Recognized albums",
        systemImage: "opticaldisc",
        description: Text("Matches from your library will appear here.")
      )
      .frame(minHeight: 420)
    } else {
      LazyVStack(alignment: .leading, spacing: 14) {
        Text("Recognized albums")
          .font(.title2.bold())
          .frame(maxWidth: .infinity, alignment: .leading)

        ForEach(store.recognizedAlbums) { album in
          Button {
            hintFocused = false
            store.playRecognized(album)
          } label: {
            if regularWidth {
              VStack(alignment: .leading, spacing: 12) {
                CoverArt(
                  title: album.title,
                  image: store.imageData(
                    for: album.imageKey,
                    pixels: ArtworkCache.gridPixels
                  ),
                  corner: 10
                )
                .aspectRatio(1, contentMode: .fit)

                HStack(alignment: .top) {
                  albumText(album)
                  Spacer(minLength: 8)
                  Image(systemName: "play.circle.fill")
                    .foregroundStyle(Palette.accent)
                    .font(.title2)
                }
              }
            } else {
              HStack(spacing: 14) {
                CoverArt(
                  title: album.title,
                  image: store.imageData(for: album.imageKey),
                  corner: 8
                )
                .frame(width: 52, height: 52)
                albumText(album)
                Spacer()
                Image(systemName: "play.circle.fill")
                  .foregroundStyle(Palette.accent)
                  .font(.title2)
              }
            }
          }
          .padding(12)
          .background(Palette.surface)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .buttonStyle(.plain)
        }
      }
    }
  }

  private func albumText(_ album: BrowseNode) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(album.title)
        .font(.headline)
        .foregroundStyle(Palette.primary)
      Text(album.subtitle ?? "")
        .font(.subheadline)
        .foregroundStyle(Palette.secondary)
    }
  }

  private func resetSearch() {
    hintFocused = false
    store.hasPhoto = false
    store.recognizedAlbums = []
    pickedImage = nil
    pickerItem = nil
  }

  private func loadPickedImage(_ item: PhotosPickerItem) async {
    if let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil {
      applyPickedImage(jpegData(from: data))
      return
    }
    if let transfer = try? await item.loadTransferable(type: PickedImageData.self) {
      applyPickedImage(transfer.data)
      return
    }
    store.aiError = "Couldn’t read that photo. Try another image."
  }

  private func applyPickedImage(_ data: Data) {
    hintFocused = false
    pickedImage = data
    store.hasPhoto = true
    store.aiError = nil
    store.recognizeAlbum(image: data, mimeType: "image/jpeg")
  }

  private func jpegData(from data: Data) -> Data {
    guard let image = UIImage(data: data) else { return data }
    return image.jpegData(compressionQuality: 0.85) ?? data
  }
}

private struct PickedImageData: Transferable {
  let data: Data

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(importedContentType: .image) { data in
      let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) ?? data
      return PickedImageData(data: jpeg)
    }
  }
}

struct TrackStoryView: View {
  @Environment(MockStore.self) private var store
  @Environment(\.horizontalSizeClass) private var hSize

  var body: some View {
    ScrollView {
      if store.storyLoading {
        ProgressView()
          .tint(Palette.accent)
          .frame(maxWidth: .infinity)
          .padding(.top, 48)
      } else if let error = store.storyError {
        ContentUnavailableView(
          "Story unavailable",
          systemImage: "text.book.closed",
          description: Text(error)
        )
      } else if let track = store.currentTrack, !store.storyBody.isEmpty {
        VStack(alignment: .leading, spacing: 18) {
          if hSize == .regular {
            CoverArt(
              title: track.album,
              image: store.imageData(for: track.imageKey, pixels: ArtworkCache.gridPixels),
              corner: 12
            )
            .frame(width: 132, height: 132)
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
          }
          Text("\(track.artist) — \(track.title)")
            .font(.system(size: Layout.storyTitleSize(hSize), weight: .semibold))
          Text(store.storyTitle)
            .font(hSize == .regular ? .title3 : .headline)
            .foregroundStyle(Palette.accent)
          StoryMarkdown(source: store.storyBody)
        }
        .padding(.horizontal, hSize == .regular ? 40 : 20)
        .padding(.top, hSize == .regular ? 28 : 20)
        .padding(.bottom, 40)
        // Prose is held to a readable measure and centred, so a full-screen
        // story on a landscape iPad does not run line-for-line across 1300pt.
        .frame(maxWidth: Layout.readingWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
      } else if store.currentTrack == nil {
        ContentUnavailableView(
          "Nothing playing",
          systemImage: "text.book.closed",
          description: Text("Start a track to read its story.")
        )
      } else {
        ContentUnavailableView(
          "No story yet",
          systemImage: "text.book.closed",
          description: Text("Add your OpenAI API key in the web Settings.")
        )
      }
    }
    .onAppear { store.loadTrackStory() }
    .onChange(of: store.currentTrack?.id) { _, _ in
      store.loadTrackStory()
    }
  }
}

private struct StoryMarkdown: View {
  let source: String

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ForEach(Array(Self.blocks(from: source).enumerated()), id: \.offset) { _, block in
        switch block {
        case let .heading(text):
          Text(Self.inline(text))
            .font(.headline)
            .foregroundStyle(Palette.primary)
            .padding(.top, 4)
        case let .paragraph(text):
          Text(Self.inline(text))
            .foregroundStyle(Palette.secondary)
            .tint(Palette.accent)
            .lineSpacing(5)
        case let .bullet(text):
          HStack(alignment: .top, spacing: 10) {
            Text("•")
              .foregroundStyle(Palette.accent)
            Text(Self.inline(text))
              .foregroundStyle(Palette.secondary)
              .tint(Palette.accent)
              .lineSpacing(4)
          }
        }
      }
    }
  }

  private enum Block {
    case heading(String)
    case paragraph(String)
    case bullet(String)
  }

  private static func inline(_ raw: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace
    )
    return (try? AttributedString(markdown: raw, options: options)) ?? AttributedString(raw)
  }

  private static func blocks(from source: String) -> [Block] {
    var blocks: [Block] = []
    var paragraph: [String] = []
    var bullet: String?

    func flushParagraph() {
      let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      paragraph = []
      guard !text.isEmpty else { return }
      if isHeading(text) {
        blocks.append(.heading(stripHeadingMarks(text)))
      } else {
        blocks.append(.paragraph(text))
      }
    }

    func flushBullet() {
      if let bullet {
        blocks.append(.bullet(bullet.trimmingCharacters(in: .whitespacesAndNewlines)))
      }
      bullet = nil
    }

    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty {
        flushBullet()
        flushParagraph()
        continue
      }
      if trimmed.hasPrefix("#") {
        flushBullet()
        flushParagraph()
        blocks.append(.heading(stripHeadingMarks(trimmed)))
        continue
      }
      if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
        flushBullet()
        flushParagraph()
        bullet = String(trimmed.dropFirst(2))
        continue
      }
      if bullet != nil {
        bullet = "\(bullet ?? "")\n\(trimmed)"
        continue
      }
      paragraph.append(trimmed)
    }
    flushBullet()
    flushParagraph()
    return blocks
  }

  private static func isHeading(_ text: String) -> Bool {
    let lines = text.split(whereSeparator: \.isNewline)
    guard lines.count == 1 else { return false }
    let line = String(lines[0])
    if line.hasPrefix("#") { return true }
    guard line.hasPrefix("**"), line.count > 4 else { return false }
    return line.hasSuffix("**") || line.hasSuffix(":**")
  }

  private static func stripHeadingMarks(_ text: String) -> String {
    var line = text.trimmingCharacters(in: .whitespaces)
    while line.hasPrefix("#") { line.removeFirst() }
    line = line.trimmingCharacters(in: .whitespaces)
    if line.hasSuffix(":") { line.removeLast() }
    line = line.trimmingCharacters(in: .whitespaces)
    if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4 {
      line = String(line.dropFirst(2).dropLast(2))
    }
    return line
  }
}

private struct CameraPicker: UIViewControllerRepresentable {
  var onImage: (Data) -> Void
  @Environment(\.dismiss) private var dismiss

  func makeCoordinator() -> Coordinator {
    Coordinator(onImage: onImage, dismiss: dismiss)
  }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let onImage: (Data) -> Void
    let dismiss: DismissAction

    init(onImage: @escaping (Data) -> Void, dismiss: DismissAction) {
      self.onImage = onImage
      self.dismiss = dismiss
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      dismiss()
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.8) {
        onImage(data)
      }
      dismiss()
    }
  }
}
