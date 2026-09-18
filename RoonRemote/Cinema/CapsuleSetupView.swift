import SwiftUI

struct CapsuleSetupView: View {
  let setup: CapsuleSetup
  @Environment(MockStore.self) private var store
  @Environment(\.dismiss) private var dismiss
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
    let request = setup.request
    let mode = CapsuleMode.suggested(query: request.query, tracks: request.tracks)
    var suggested = CapsuleOptions(
      mode: mode,
      subject: mode.suggestedSubject(query: request.query, tracks: request.tracks),
      locale: request.locale
    )
    suggested.restorePreferences()
    _options = State(initialValue: suggested)
    let anchor = ISO8601DateFormatter().date(from: request.requestedAt) ?? Date()
    _startDate = State(initialValue: anchor)
    _endDate = State(initialValue: anchor)
  }

  var body: some View {
    NavigationStack {
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
      .background(Palette.background)
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
    .tint(Palette.accent)
    .interactiveDismissDisabled(saving)
    .onDisappear { creation?.cancel() }
  }

  private var availableModes: [CapsuleMode] {
    #if os(iOS)
    CapsuleMode.allCases
    #else
    CapsuleMode.allCases.filter { $0 != .photos }
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
      return photos.count > 0 && photos.count <= 200
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
      dismiss()
      return
    }
    #if os(iOS)
    saving = true; failure = nil
    creation = Task {
      defer { saving = false }
      do {
        let capsule = try await photos.create(request: request)
        if Task.isCancelled {
          await PersonalCinemaStore.shared.remove(capsule)
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
