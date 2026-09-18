import SwiftUI

struct CapsuleSetupView: View {
  let setup: CapsuleSetup
  @Environment(MockStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var presentationCategory = false
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
            .navigationTitle("Set up Cinema")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { creation?.cancel(); dismiss() }
              }
            }
        }
      }
      .background(Palette.background)
    }
    .tint(Palette.accent)
    .preferredColorScheme(.dark)
    .interactiveDismissDisabled(saving)
    .task(id: setup.id) {
      store.cinema.warmArtwork(tracks: setup.request.tracks, zoneId: store.selectedZoneId, client: store.client)
    }
    .onDisappear { creation?.cancel() }
  }

  private var creationForm: some View {
    Form {
        Section {
          Text(setup.request.query).font(.headline)
          Text("\(setup.request.tracks.count) selected tracks · your soundtrack stays the same")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        Section("What would you like to see?") {
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
          Button(options.mode == .photos ? "Save montage" : "Create montage", action: create)
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
          Button("Cancel") { creation?.cancel(); dismiss() }
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
    .onExitCommand { dismiss() }
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
          Text(original.title).font(CinemaLayout.isTV ? .system(size: 38, weight: .bold) : .title.bold())
            .lineLimit(CinemaLayout.isTV ? 2 : nil)
          Text("\(setup.request.tracks.count) tracks · soundtrack unchanged")
            .font(.subheadline).foregroundStyle(Palette.secondary)
        } else {
          HStack(spacing: 14) {
            CinemaArtwork(capsule: original).frame(width: 56, height: 56)
              .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
              Text(original.title).font(.headline)
              Text("\(setup.request.tracks.count) tracks · soundtrack unchanged")
                .font(.caption).foregroundStyle(Palette.secondary)
            }
          }
        }
      }
      if CinemaLayout.isTV {
        Button { presentationCategory = false } label: {
          CinemaSettingLabel(title: "Pictures")
            .background(!presentationCategory ? Palette.surface : .clear)
        }.cinemaPlainButton()
        Button { presentationCategory = true } label: {
          CinemaSettingLabel(title: "Presentation", detail: "Captions, motion, pace & order")
            .background(presentationCategory ? Palette.surface : .clear)
        }.cinemaPlainButton()
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
                choices: availableModes.map { CinemaOption(value: $0, title: $0.title) })
                .accessibilityIdentifier("cinema-mode")
              Divider()
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
                CinemaSettingLabel(title: "\(options.captions.title) · \(options.motion.title)",
                  detail: "\(Int(options.pace.seconds)) seconds · \(options.order.title)")
              }.cinemaPlainButton()
            }
          }
          if !wide {
            Text("Your current pictures stay available until the new montage is ready.")
              .font(.footnote).foregroundStyle(Palette.secondary)
          }
          if let failure { Text(failure).foregroundStyle(.red).font(.subheadline) }
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
            Text("Save & regenerate")
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
      CinemaOptionRow(title: "Captions", selection: $options.captions,
        choices: CapsuleCaptions.allCases.filter { options.mode != .photos || $0 != .detailed }.map { CinemaOption(value: $0, title: $0.title) })
      Divider()
      CinemaOptionRow(title: "Movement", selection: $options.motion,
        choices: CapsuleMotion.allCases.map { CinemaOption(value: $0, title: $0.title) })
      Divider()
      CinemaOptionRow(title: "Pace", selection: $options.pace,
        choices: CapsulePace.allCases.map { CinemaOption(value: $0, title: "\(Int($0.seconds)) seconds") })
      Divider()
      CinemaOptionRow(title: "Order", selection: $options.order,
        choices: CapsuleOrder.allCases.map { CinemaOption(value: $0, title: $0.title) })
    }
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
      Picker("Captions", selection: $options.captions) {
        ForEach(CapsuleCaptions.allCases.filter { options.mode != .photos || $0 != .detailed }) { Text($0.title).tag($0) }
      }
      Picker("Movement", selection: $options.motion) {
        ForEach(CapsuleMotion.allCases) { Text($0.title).tag($0) }
      }
      Picker("Pace", selection: $options.pace) {
        ForEach(CapsulePace.allCases) { Text("\($0.title) · \(Int($0.seconds)) seconds").tag($0) }
      }
      Picker("Order", selection: $options.order) {
        ForEach(CapsuleOrder.allCases) { Text($0.title).tag($0) }
      }
      if options.mode == .photos {
        Text("Captions show the photo date when available. Undated photos keep their selected order in a chronological montage.")
          .font(.footnote).foregroundStyle(.secondary)
      }
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
    if options.mode == .photos {
      #if os(iOS)
      return setup.original?.isPersonal == true || (photos.count > 0 && photos.count <= 200)
      #else
      return false
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
        subject: mode.suggestedSubject(query: setup.request.query, tracks: setup.request.tracks),
        locale: setup.request.locale
      )
      options.restorePreferences()
    }
    customDates = false
    failure = nil
  }

  private func create() {
    var request = setup.request
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
    request.options = chosen
    if options.mode != .photos {
      chosen.rememberPreferences()
      store.cinema.pendingRequest = request
      store.cinema.pendingOriginal = setup.original
      dismiss()
      return
    }
    #if os(iOS)
    saving = true; failure = nil
    creation = Task {
      defer { saving = false }
      do {
        let capsule: TimeCapsule
        if let original = setup.original {
          capsule = try await PersonalCinemaStore.shared.update(original, options: chosen)
        } else {
          capsule = try await photos.create(request: request)
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
    #endif
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
