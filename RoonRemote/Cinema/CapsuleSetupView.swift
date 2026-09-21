import SwiftUI

struct CapsuleSetupView: View {
  let setup: CapsuleSetup
  @Environment(MockStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var presentationCategory = false
  #if os(tvOS)
  @FocusState private var trackTitleFocused: Bool
  #endif
  @State private var editingMusic = false
  @State private var music: CinemaMusicDraft
  @State private var title: String
  @State private var discardChanges = false
  @State private var mutationId = UUID().uuidString
  @State private var requestId: String
  @State private var conflict = false
  @State private var lastSubmittedRequest: CapsuleRequest?
  @State private var options: CapsuleOptions
  @State private var drafts: [CapsuleMode: CapsuleOptions] = [:]
  @State private var customDates = false
  @State private var startDate: Date
  @State private var endDate: Date
  @State private var saving = false
  @State private var failure: String?
  @State private var creation: Task<Void, Never>?
  #if os(iOS)
  @State private var photos = CinemaPhotoSelection()
  #endif

  init(setup: CapsuleSetup) {
    self.setup = setup
    _music = State(initialValue: CinemaMusicDraft(tracks: setup.request.tracks))
    _title = State(initialValue: setup.original?.title ?? setup.request.title ?? setup.request.query)
    _requestId = State(initialValue: setup.request.clientRequestId ?? UUID().uuidString)
    let chosen = setup.initialOptions
    _options = State(initialValue: chosen)
    let anchor = ISO8601DateFormatter().date(from: setup.request.requestedAt) ?? Date()
    let formatter = Self.dateFormatter
    _startDate = State(initialValue: chosen.periodStart.flatMap(formatter.date(from:)) ?? anchor)
    _endDate = State(initialValue: chosen.periodEnd.flatMap(formatter.date(from:)) ?? anchor)
    _customDates = State(initialValue: chosen.periodStart != nil && chosen.periodEnd != nil)
  }

  var body: some View {
    NavigationStack {
      Group {
        if setup.isEditing { editor }
        else {
          creationForm
            .navigationTitle("Create Cinema")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
              }
            }
        }
      }
      .background(Palette.background)
      .navigationDestination(isPresented: $editingMusic) {
        CinemaMusicEditor(draft: music, title: title,
          currentTrack: setup.request.tracks.first { $0.entryId == setup.currentTrackId })
      }
      #if os(tvOS)
      .onChange(of: presentationCategory) { _, selected in
        if selected { trackTitleFocused = true }
      }
      #endif
    }
    .tint(Palette.accent)
    .preferredColorScheme(.dark)
    .interactiveDismissDisabled(saving || hasChanges)
    .confirmationDialog("Discard changes?", isPresented: $discardChanges, titleVisibility: .visible) {
      Button("Discard changes", role: .destructive) { creation?.cancel(); dismiss() }
      Button("Keep editing", role: .cancel) { }
    }
    #if os(iOS)
    // Present from a stable container, not the Form's changing Section rows.
    .sheet(isPresented: $photos.showingAlbums) {
      CinemaPhotoAlbumPicker(selection: photos)
    }
    #endif
    .task(id: setup.id) {
      store.cinema.warmArtwork(tracks: setup.request.tracks, zoneId: store.selectedZoneId, client: store.client)
    }
    .onDisappear { creation?.cancel() }
  }

  private var creationForm: some View {
    Form {
        Section {
          nameField
          if let source = setup.request.sourceLabel { Text(source).font(.caption).foregroundStyle(.secondary) }
          musicLink
          Text("Your Cinema copy can be edited separately.").font(.footnote).foregroundStyle(.secondary)
        }
        Section("Pictures") {
          Picker("Visual companion", selection: Binding(get: { options.mode }, set: changeMode)) {
            ForEach(availableModes) { mode in Label(mode.title, systemImage: mode.symbol).tag(mode) }
          }
          #if os(iOS)
          .pickerStyle(.menu)
          #endif
          .accessibilityIdentifier("cinema-mode")
        }
        if options.mode == .photos {
          #if os(iOS)
          CinemaPhotoControls(selection: photos)
          #endif
        } else if options.mode == .artwork {
          Section { Text("Covers from your selected music. No picture research needed.").font(.subheadline) }
        } else {
          contextSection
          Section {
            ForEach(options.mode.topics) { topic in
              topicToggle(topic)
            }
            topicToggle(.albumCovers)
            #if os(tvOS)
            NavigationLink("More topics") {
              Form {
                ForEach(additionalTopics) { topic in
                  topicToggle(topic)
                }
              }.navigationTitle("More topics")
            }
            #else
            DisclosureGroup("More topics") {
              ForEach(additionalTopics) { topic in
                topicToggle(topic)
              }
            }
            #endif
          } header: { Text("Include") } footer: {
            Text(options.topics.isEmpty ? "Choose at least one topic."
              : options.topics.contains(.sports)
                ? "We'll use sourced images for your chosen topics. Sports highlights use photographs and captions."
                : "We'll use sourced images for your chosen topics.")
          }
        }
        presentationSection
        Section("Your montage") {
          Text(options.summary).font(.subheadline)
          if let failure { Text(failure).foregroundStyle(.red).accessibilityLabel("Could not create montage. \(failure)") }
          if saving {
            #if os(iOS)
            ProgressView(photos.progress.isEmpty ? "Preparing…" : photos.progress)
            #else
            ProgressView("Preparing…")
            #endif
          }
          Button(saveLabel, action: create)
            .accessibilityIdentifier("cinema-save")
            .buttonStyle(.borderedProminent).tint(Palette.accent).foregroundStyle(Palette.onAccent)
            .disabled(!canCreate || saving)
        }
      }
      .disabled(saving)
      #if os(iOS)
      .scrollContentBackground(.hidden)
      #endif
  }

  private var editor: some View {
    GeometryReader { geometry in
      let wide = CinemaLayout.isTV || geometry.size.width >= 760
      VStack(spacing: 0) {
        HStack {
          Text("Edit Cinema").font(.system(size: CinemaLayout.isTV ? 42 : wide ? 28 : 22, weight: .bold))
          Spacer()
          Button("Cancel", action: cancel)
            #if os(tvOS)
            .buttonStyle(CinemaButtonStyle()).frame(width: 160)
            #else
            .frame(minHeight: 44)
            #endif
        }
        .padding(.horizontal, CinemaLayout.inset).padding(.vertical, 16)
        Divider()
        if wide {
          HStack(alignment: .top, spacing: 0) {
            ScrollView { editorSummary(wide: true).padding(CinemaLayout.inset) }
              .frame(width: geometry.size.width * 0.35)
              .cinemaFocusSection()
            Divider()
            editorOptions(wide: true).cinemaFocusSection()
          }
        } else { editorOptions(wide: false) }
      }
    }
    .foregroundStyle(Palette.primary)
    #if os(tvOS)
    .onExitCommand(perform: cancel)
    #endif
  }

  private func editorSummary(wide: Bool) -> some View {
    VStack(alignment: .leading, spacing: wide ? 20 : 12) {
      if let original = setup.original {
        if wide {
          if CinemaLayout.isTV {
            CinemaArtwork(capsule: original).frame(height: 210)
              .clipShape(RoundedRectangle(cornerRadius: 8))
          } else {
            CinemaArtwork(capsule: original).aspectRatio(1.7, contentMode: .fit)
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          nameField
          Text(music.summary)
            .font(.subheadline).foregroundStyle(Palette.secondary)
        } else {
          HStack(spacing: 14) {
            CinemaArtwork(capsule: original).frame(width: 56, height: 56)
              .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
              nameField
              Text(music.summary)
                .font(.caption).foregroundStyle(Palette.secondary)
            }
          }
        }
      }
      musicLink
      if CinemaLayout.isTV {
        Button { presentationCategory = false } label: {
          CinemaSettingLabel(title: "Pictures")
            .background(!presentationCategory ? Palette.surface : .clear)
        }.cinemaPlainButton()
        Button { presentationCategory = true } label: {
          CinemaSettingLabel(title: "Presentation", detail: "Track title, captions & picture motion")
            .background(presentationCategory ? Palette.surface : .clear)
        }.cinemaPlainButton().accessibilityIdentifier("cinema-presentation")
      }
      if wide {
        Divider()
        Text("Your current pictures stay available until the new montage is ready.")
          .font(.subheadline).foregroundStyle(Palette.secondary)
      }
    }
  }

  private func editorOptions(wide: Bool) -> some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if !wide { editorSummary(wide: false) }
          if !CinemaLayout.isTV || !presentationCategory {
            if options.mode != .photos {
              sectionHeading("Pictures")
              CinemaOptionRow(title: "Visual companion", selection: Binding(get: { options.mode }, set: changeMode),
                choices: availableModes.map { CinemaOption(value: $0, title: $0.title) }, identifier: "cinema-mode")
              Divider()
              if options.mode != .artwork {
                NavigationLink {
                  Form { contextSection }
                    .navigationTitle("Context")
                    .tint(Palette.accent)
                } label: {
                  CinemaSettingLabel(title: "Context", value: options.subject,
                    detail: options.mode == .period ? Locale.current.localizedString(forRegionCode: options.region) : nil)
                }.cinemaPlainButton()
                sectionHeading("Include")
                VStack(spacing: 0) {
                  ForEach(options.mode.topics) { topic in
                    CinemaTopicRow(title: topic.title, selected: topicBinding(topic))
                    Divider()
                  }
                  CinemaTopicRow(title: CapsuleTopic.albumCovers.title, selected: topicBinding(.albumCovers))
                  Divider()
                  NavigationLink {
                    ScrollView {
                      VStack(spacing: 0) {
                        ForEach(additionalTopics) { topic in
                          CinemaTopicRow(title: topic.title, selected: topicBinding(topic))
                          Divider()
                        }
                      }.padding(CinemaLayout.inset)
                    }.navigationTitle("More topics")
                  } label: { CinemaSettingLabel(title: "More topics") }.cinemaPlainButton()
                }
              } else {
                Text("Covers from your selected music. No picture research needed.")
                  .font(.subheadline).foregroundStyle(Palette.secondary)
              }
            } else {
              Label("Your saved photos", systemImage: "photo.on.rectangle")
              Text("Presentation changes use the photos already saved with this playlist.")
                .font(.subheadline).foregroundStyle(Palette.secondary)
            }
          }
          if !CinemaLayout.isTV || presentationCategory || options.mode == .photos {
            sectionHeading("Presentation")
            if wide { editorPresentation }
            else {
              NavigationLink {
                ScrollView { editorPresentation.padding(24) }.navigationTitle("Presentation")
              } label: {
                CinemaSettingLabel(title: "Presentation", detail: options.presentationSummary)
              }.cinemaPlainButton().accessibilityIdentifier("cinema-presentation")
            }
          }
          if !wide {
            Text("Your current pictures stay available until the new montage is ready.")
              .font(.footnote).foregroundStyle(Palette.secondary)
          }
          if let failure { Text(failure).foregroundStyle(.red).font(.subheadline) }
          if conflict {
            Button("Save as new Cinema") { create(copy: true) }
          }
        }
        .padding(CinemaLayout.inset)
        .disabled(saving)
      }
      Divider()
      VStack(spacing: 8) {
        Button(action: create) {
          HStack {
            if saving { ProgressView().tint(Palette.onAccent) }
            else { Image(systemName: "arrow.clockwise") }
            Text(saveLabel)
          }
        }
        .buttonStyle(CinemaButtonStyle(prominent: true))
        .disabled(!canCreate || saving)
        .accessibilityIdentifier("cinema-save")
        Text("Album artwork or a saved picture appears straight away.")
          .font(.caption).foregroundStyle(Palette.secondary)
      }.padding(.horizontal, CinemaLayout.inset).padding(.vertical, 16)
    }
  }

  private var editorPresentation: some View {
    VStack(spacing: 0) {
      trackTitleControl
      Divider()
      CinemaOptionRow(title: "Captions", selection: $options.captions,
        choices: CapsuleCaptions.allCases.filter { options.mode != .photos || $0 != .detailed }.map { CinemaOption(value: $0, title: $0.title) })
      Divider()
      CinemaOptionRow(title: "Picture motion", selection: $options.motion,
        choices: CapsuleMotion.allCases.map { CinemaOption(value: $0, title: $0.title) }, identifier: "cinema-picture-motion")
      Divider()
      CinemaOptionRow(title: "Pace", selection: $options.pace,
        choices: CapsulePace.allCases.map { CinemaOption(value: $0, title: "\(Int($0.seconds)) seconds") })
      Divider()
      CinemaOptionRow(title: "Picture order", selection: $options.order,
        choices: CapsuleOrder.allCases.map { CinemaOption(value: $0, title: $0.title) })
      presentationHelp
    }
  }

  private var trackTitleControl: some View {
    CinemaTopicRow(title: "Show track title", selected: $options.showsTrackTitle)
      .accessibilityIdentifier("cinema-show-track-title")
      #if os(tvOS)
      .focused($trackTitleFocused)
      #endif
  }

  private var presentationHelp: some View {
    Text("Track title and artist stay visible as the music changes. Ken Burns slowly pans and zooms each picture. Reduce Motion keeps pictures still.")
      .font(.footnote).foregroundStyle(Palette.secondary)
      .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
  }

  private func sectionHeading(_ title: String) -> some View {
    Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Palette.secondary)
      .padding(.top, 4)
  }

  private func topicBinding(_ topic: CapsuleTopic) -> Binding<Bool> {
    Binding(get: { options.topics.contains(topic) }, set: { selected in
      options.topics.removeAll { $0 == topic }
      if selected { options.topics.append(topic) }
      options.topics = CapsuleTopic.allCases.filter { options.topics.contains($0) }
    })
  }

  private static var dateFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }

  private var availableModes: [CapsuleMode] {
    if setup.original?.isPersonal == true { return [.photos] }
    if setup.isEditing { return CapsuleMode.allCases.filter { $0 != .photos } }
    #if os(iOS)
    return CapsuleMode.allCases
    #else
    return CapsuleMode.allCases.filter { $0 != .photos }
    #endif
  }

  @ViewBuilder private var contextSection: some View {
    Section {
      TextField(options.mode == .period ? "Period or chart request" : "Subject & setting", text: $options.subject, axis: .vertical)
        .lineLimit(1...4)
      if options.mode == .period {
        Picker("Perspective", selection: $options.region) {
          ForEach(regionCodes, id: \.self) { code in
            Text(Locale.current.localizedString(forRegionCode: code) ?? code).tag(code)
          }
        }
      }
      if options.mode == .work {
        Picker("Focus", selection: $options.workContext) {
          ForEach(CapsuleWorkContext.allCases) { Text($0.title).tag($0) }
        }
        Text("The work's history and the recording's history are different. We'll use the focus you choose.")
          .font(.footnote).foregroundStyle(.secondary)
      } else {
        #if os(iOS)
        Toggle("Choose exact dates", isOn: $customDates)
        if customDates {
          DatePicker("From", selection: $startDate, displayedComponents: .date)
          DatePicker("Through", selection: $endDate, in: startDate..., displayedComponents: .date)
            .onChange(of: startDate) { _, date in if endDate < date { endDate = date } }
        } else {
          Text("Dates come from your request. Relative dates stay anchored to the original search.")
            .font(.footnote).foregroundStyle(.secondary)
        }
        #endif
      }
    } header: { Text("Context") }
  }

  private var presentationSection: some View {
    Section("Presentation") {
      trackTitleControl
      Picker("Captions", selection: $options.captions) {
        ForEach(CapsuleCaptions.allCases.filter { options.mode != .photos || $0 != .detailed }) { Text($0.title).tag($0) }
      }
      Picker("Picture motion", selection: $options.motion) {
        ForEach(CapsuleMotion.allCases) { Text($0.title).tag($0) }
      }
      .accessibilityIdentifier("cinema-picture-motion")
      Picker("Pace", selection: $options.pace) {
        ForEach(CapsulePace.allCases) { Text("\($0.title) · \(Int($0.seconds)) seconds").tag($0) }
      }
      Picker("Picture order", selection: $options.order) {
        ForEach(CapsuleOrder.allCases) { Text($0.title).tag($0) }
      }
      if options.mode == .photos {
        Text("Captions show the photo date when available. Undated photos keep their selected order in a chronological montage.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      presentationHelp
    }
  }

  private func topicToggle(_ topic: CapsuleTopic) -> some View {
    Toggle(topic.title, isOn: Binding(get: { options.topics.contains(topic) }, set: { selected in
      options.topics.removeAll { $0 == topic }
      if selected { options.topics.append(topic) }
      options.topics = CapsuleTopic.allCases.filter { options.topics.contains($0) }
    }))
  }

  private var regionCodes: [String] {
    Array(Set([options.region, "GB", "US", "FR", "DE", "IT", "ES", "AU", "CA", "BR", "JP"]))
      .sorted { (Locale.current.localizedString(forRegionCode: $0) ?? $0) < (Locale.current.localizedString(forRegionCode: $1) ?? $1) }
  }

  private var additionalTopics: [CapsuleTopic] {
    CapsuleTopic.allCases.filter {
      $0 != .albumCovers && !options.mode.topics.contains($0)
    }
  }

  private var canCreate: Bool {
    guard !music.tracks.isEmpty, music.tracks.count <= CinemaMusicDraft.trackLimit,
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    if options.mode == .photos {
      #if os(iOS)
      return setup.original?.isPersonal == true || (photos.count > 0 && photos.count <= 200)
      #else
      return setup.original?.isPersonal == true
      #endif
    }
    return !options.topics.isEmpty && !options.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (!customDates || startDate <= endDate)
  }

  private func changeMode(_ mode: CapsuleMode) {
    drafts[options.mode] = options
    if let draft = drafts[mode] { options = draft }
    else {
      options = CapsuleOptions(
        mode: mode,
        subject: mode.suggestedSubject(query: setup.request.query, tracks: music.tracks),
        locale: setup.request.locale
      )
      options.restorePreferences()
    }
    customDates = false
    failure = nil
  }

  private var nameField: some View {
    TextField("Cinema name", text: $title).font(.headline)
      .accessibilityIdentifier("cinema-name")
  }

  private var musicLink: some View {
    Button { editingMusic = true } label: {
      CinemaSettingLabel(title: "Music", value: music.summary,
        detail: music.tracks.isEmpty ? "Choose music" : "Reorder, add or remove tracks")
    }.cinemaPlainButton().accessibilityIdentifier("cinema-edit-music")
  }

  private var hasChanges: Bool {
    let originalTracks = setup.request.tracks.map { track in var copy = track; copy.entryId = nil; return copy }
    let editedTracks = music.tracks.map { track in var copy = track; copy.entryId = nil; return copy }
    return title != (setup.original?.title ?? setup.request.title ?? setup.request.query)
      || originalTracks != editedTracks || options != setup.initialOptions
      || customDates != (setup.initialOptions.periodStart != nil && setup.initialOptions.periodEnd != nil)
      || (customDates && (Self.dateFormatter.string(from: startDate) != setup.initialOptions.periodStart
        || Self.dateFormatter.string(from: endDate) != setup.initialOptions.periodEnd))
  }

  private var saveLabel: String {
    guard setup.isEditing else { return "Save Cinema" }
    return options.hasSamePictureContent(as: setup.initialOptions) ? "Save changes" : "Save & update pictures"
  }

  private func cancel() {
    if hasChanges { discardChanges = true }
    else { creation?.cancel(); dismiss() }
  }

  private func create() { create(copy: false) }

  private func create(copy: Bool) {
    var request = setup.request
    request.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    request.tracks = music.tracks
    request.clientRequestId = copy ? UUID().uuidString : requestId
    var chosen = options
    chosen.periodStart = nil
    chosen.periodEnd = nil
    if customDates && options.mode != .work && options.mode != .photos {
      let formatter = DateFormatter()
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "yyyy-MM-dd"
      chosen.periodStart = formatter.string(from: startDate)
      chosen.periodEnd = formatter.string(from: endDate)
    }
    chosen.subjectIsExplicit = true
    request.options = setup.isEditing && chosen == setup.initialOptions
      && setup.request.options == nil ? nil : chosen
    if lastSubmittedRequest != request {
      mutationId = UUID().uuidString
      lastSubmittedRequest = request
    }
    if options.mode != .photos {
      saving = true; failure = nil; conflict = false
      creation = Task {
        defer { saving = false }
        do {
          try await store.cinema.save(request: request, original: copy ? nil : setup.original,
            mutationId: mutationId, client: store.client)
          chosen.rememberPreferences()
          dismiss()
        } catch is CancellationError { }
        catch {
          failure = error.localizedDescription
          if case RoonAPIError.httpStatus(409, _) = error { conflict = true }
        }
      }
      return
    }
    saving = true; failure = nil
    creation = Task {
      defer { saving = false }
      do {
        let capsule: TimeCapsule
        if let original = setup.original {
          capsule = try await PersonalCinemaStore.shared.update(original, options: chosen, request: request)
        } else {
          #if os(iOS)
          capsule = try await photos.create(request: request)
          #else
          throw PersonalCinemaError("Create photo cinemas on your iPhone or iPad, then sync them here.")
          #endif
        }
        if Task.isCancelled {
          if setup.original == nil { try? await PersonalCinemaStore.shared.remove(capsule) }
          return
        }
        chosen.rememberPreferences()
        store.cinema.pendingPersonal = capsule
        dismiss()
      } catch is CancellationError {
      } catch { failure = error.localizedDescription }
    }
  }
}

#if DEBUG
#Preview("Chart week") {
  CapsuleSetupView(setup: CapsuleSetup(request: CapsuleRequest(
    context: CapsuleSearchContext(query: "UK top ten this week in 1978"), tracks: [])))
    .environment(MockStore())
}
#Preview("Django") {
  CapsuleSetupView(setup: CapsuleSetup(request: CapsuleRequest(
    context: CapsuleSearchContext(query: "Django Reinhardt's greatest hits"), tracks: [])))
    .environment(MockStore())
}
#Preview("Beethoven") {
  CapsuleSetupView(setup: CapsuleSetup(request: CapsuleRequest(
    context: CapsuleSearchContext(query: "Beethoven Symphony No. 6"), tracks: [])))
    .environment(MockStore())
}
#endif
