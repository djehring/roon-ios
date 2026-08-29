import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct SearchTabView: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    @Bindable var store = store
    NavigationStack {
      VStack(spacing: 0) {
        Picker("Search", selection: $store.searchSegment) {
          Text("AI").tag(SearchSegment.ai)
          Text("Camera").tag(SearchSegment.camera)
          Text("Story").tag(SearchSegment.story)
        }
        .pickerStyle(.segmented)
        .padding(16)
        Group {
          switch store.searchSegment {
          case .ai: AISearchView()
          case .camera: CameraSearchView()
          case .story: TrackStoryView()
          }
        }
      }
      .background(Palette.background)
      .navigationTitle("Search")
    }
  }
}

struct AISearchView: View {
  @Environment(MockStore.self) private var store
  @State private var recorder = VoiceRecorder()
  @FocusState private var queryFocused: Bool

  var body: some View {
    @Bindable var store = store
    VStack(spacing: 12) {
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
      }
      .padding(.horizontal, 16)

      if let error = store.aiError {
        Text(error)
          .font(.footnote)
          .foregroundStyle(.red.opacity(0.85))
          .padding(.horizontal, 16)
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
            }
            .listRowBackground(Palette.surface)
          }
          .onDelete { store.aiResults.remove(atOffsets: $0) }
          .onMove { store.aiResults.move(fromOffsets: $0, toOffset: $1) }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
      }
    }
    .safeAreaInset(edge: .bottom) {
      if !store.aiLoading {
        Button("Play selected tracks") {
          queryFocused = false
          store.playAIResults()
        }
        .buttonStyle(GoldFillButton())
        .padding(16)
        .disabled(store.aiResults.isEmpty)
      }
    }
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
private final class VoiceRecorder {
  var isRecording = false
  private var recorder: AVAudioRecorder?
  private var fileURL: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("roon-ai.m4a")
  }

  func toggle() async throws -> Data? {
    if isRecording {
      recorder?.stop()
      isRecording = false
      try AVAudioSession.sharedInstance().setActive(false)
      return try Data(contentsOf: fileURL)
    }
    let granted = await AVAudioApplication.requestRecordPermission()
    guard granted else {
      throw RoonAPIError.httpStatus(403, "Microphone permission is off.")
    }
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
  @Environment(MockStore.self) private var store
  @State private var pickerItem: PhotosPickerItem?
  @State private var showCamera = false
  @State private var pickedImage: Data?

  var body: some View {
    @Bindable var store = store
    VStack(spacing: 16) {
      Menu {
        Button("Take photo") { showCamera = true }
        PhotosPicker(selection: $pickerItem, matching: .images) {
          Text("Choose from library")
        }
      } label: {
        ZStack {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Palette.surface)
            .frame(height: 220)
          if let pickedImage {
            CoverArt(title: "cover", image: pickedImage, corner: 12)
              .padding(24)
          } else {
            VStack(spacing: 8) {
              Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(Palette.accent)
              Text("Take or choose a cover")
                .foregroundStyle(Palette.secondary)
            }
          }
        }
      }
      .padding(.horizontal, 16)
      .onChange(of: pickerItem) { _, item in
        guard let item else { return }
        Task {
          if let data = try? await item.loadTransferable(type: Data.self) {
            pickedImage = data
            store.hasPhoto = true
            store.recognizeAlbum(image: data, mimeType: "image/jpeg")
          }
        }
      }

      TextField("Album description (optional)", text: $store.cameraHint)
        .padding(12)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)

      if let error = store.aiError, store.searchSegment == .camera {
        Text(error)
          .font(.footnote)
          .foregroundStyle(.red.opacity(0.85))
          .padding(.horizontal, 16)
      }

      if store.recognizedAlbums.isEmpty {
        Button("Recognize album") {
          store.recognizeAlbum(image: pickedImage, mimeType: pickedImage == nil ? nil : "image/jpeg")
        }
        .buttonStyle(GoldFillButton())
        .padding(.horizontal, 16)
        .disabled(pickedImage == nil && store.cameraHint.isEmpty)
      } else {
        List(store.recognizedAlbums) { album in
          Button {
            store.playRecognized(album)
          } label: {
            HStack {
              CoverArt(
                title: album.title,
                image: store.imageData(for: album.imageKey),
                corner: 6
              )
              .frame(width: 48, height: 48)
              VStack(alignment: .leading) {
                Text(album.title)
                  .foregroundStyle(Palette.primary)
                Text(album.subtitle ?? "")
                  .font(.footnote)
                  .foregroundStyle(Palette.secondary)
              }
              Spacer()
              Image(systemName: "play.circle.fill")
                .foregroundStyle(Palette.accent)
                .font(.title2)
            }
          }
          .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        Button("Search again") {
          store.hasPhoto = false
          store.recognizedAlbums = []
          pickedImage = nil
          pickerItem = nil
        }
        .foregroundStyle(Palette.accent)
      }
      Spacer()
    }
    .sheet(isPresented: $showCamera) {
      CameraPicker { data in
        pickedImage = data
        store.hasPhoto = true
        store.recognizeAlbum(image: data, mimeType: "image/jpeg")
      }
      .ignoresSafeArea()
    }
  }
}

struct TrackStoryView: View {
  @Environment(MockStore.self) private var store

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
        VStack(alignment: .leading, spacing: 16) {
          Text("\(track.artist) — \(track.title)")
            .font(.title2.weight(.semibold))
          Text(store.storyTitle)
            .font(.headline)
            .foregroundStyle(Palette.accent)
          StoryMarkdown(source: store.storyBody)
        }
        .padding(20)
        .padding(.bottom, 28)
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
          description: Text("The bridge will write one when OpenAI is configured.")
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
            .lineSpacing(5)
        case let .bullet(text):
          HStack(alignment: .top, spacing: 10) {
            Text("•")
              .foregroundStyle(Palette.accent)
            Text(Self.inline(text))
              .foregroundStyle(Palette.secondary)
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
    return line.hasPrefix("#") || (line.hasPrefix("**") && line.hasSuffix("**") && line.count > 4)
  }

  private static func stripHeadingMarks(_ text: String) -> String {
    var line = text.trimmingCharacters(in: .whitespaces)
    while line.hasPrefix("#") { line.removeFirst() }
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
