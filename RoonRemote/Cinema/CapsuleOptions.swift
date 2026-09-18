import Foundation

enum CapsuleMode: String, Codable, CaseIterable, Identifiable {
  case period, artist, work, photos
  var id: Self { self }
  var title: String {
    switch self {
    case .period: "Around this time"
    case .artist: "About the artist"
    case .work: "About the work"
    case .photos: "My photos"
    }
  }
  var symbol: String {
    switch self {
    case .period: "calendar"
    case .artist: "person.crop.square"
    case .work: "music.note.list"
    case .photos: "photo.on.rectangle"
    }
  }
  var topics: [CapsuleTopic] {
    switch self {
    case .period: [.headlines, .sports, .culture, .everydayLife]
    case .artist: [.artistImages, .career, .collaborators, .places, .historicalContext]
    case .work: [.composer, .programmeNotes, .artwork, .manuscripts, .places, .performers, .historicalContext]
    case .photos: []
    }
  }
  static func suggested(query: String, tracks: [CapsuleTrack]) -> Self {
    let lower = query.lowercased()
    if lower.range(of: #"\b(symphon(?:y|ies)|concerto|sonata|quartet|quintet|oratorio|cantata|opus|op\.)\b"#, options: .regularExpression) != nil { return .work }
    let artists = Set(tracks.map { $0.artist.lowercased() }.filter { !$0.isEmpty })
    if artists.count == 1, let artist = artists.first, lower.contains(artist) { return .artist }
    let remainder = lower
      .replacingOccurrences(of: #"\b\d+(?:st|nd|rd|th|s)?\b"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #"\b(top|hits?|songs?|tracks?|music|charts?|singles|billboard|best|popular|number|one|ten|twenty|forty|hundred|first|second|third|fourth|last|this|that|week|weeks|month|months|year|years|january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec|uk|britain|british|united|kingdom|england|scotland|wales|us|usa|states|american|france|french|germany|german|brazil|brazilian|australia|australian|in|of|the|from|to|on|for|and|between|during)\b"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #"[^\p{L}]"#, with: "", options: .regularExpression)
    return remainder.isEmpty ? .period : .artist
  }

  func suggestedSubject(query: String, tracks: [CapsuleTrack]) -> String {
    let artists = unique(tracks.map(\.artist))
    switch self {
    case .artist:
      return artists.count == 1 ? artists[0] : query
    case .work:
      let works = unique(tracks.map(\.track).map(Self.workTitle))
      let work = works.count == 1 ? works[0] : query
      return ([artists.count == 1 ? artists[0] : nil, work] as [String?])
        .compactMap { $0 }.joined(separator: " — ")
    case .period, .photos:
      return query
    }
  }

  private func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
  }

  private static func workTitle(_ title: String) -> String {
    title.replacingOccurrences(
      of: #":\s*(?:[IVXLCDM]+|\d+)\.?\s+.*$"#,
      with: "",
      options: [.regularExpression, .caseInsensitive]
    )
  }
}

enum CapsuleTopic: String, Codable, CaseIterable, Identifiable {
  case headlines, sports, culture, everydayLife, artistImages, career, collaborators, places
  case historicalContext, composer, programmeNotes, artwork, manuscripts, performers, albumCovers
  var id: Self { self }
  var title: String {
    switch self {
    case .headlines: "Headlines"
    case .sports: "Sports highlights"
    case .culture: "TV, film & culture"
    case .everydayLife: "Everyday life"
    case .artistImages: "Artist photographs"
    case .career: "Career stories"
    case .collaborators: "Collaborators"
    case .places: "Places & venues"
    case .historicalContext: "Wider historical context"
    case .composer: "Composer portraits & life"
    case .programmeNotes: "Programme notes"
    case .artwork: "Art & architecture"
    case .manuscripts: "Manuscripts & scores"
    case .performers: "Performers & recording"
    case .albumCovers: "Album covers"
    }
  }
}

enum CapsuleCaptions: String, Codable, CaseIterable, Identifiable {
  case none, brief, detailed
  var id: Self { self }
  var title: String {
    switch self { case .none: "Pictures only"; case .brief: "Brief captions"; case .detailed: "More context" }
  }
}
enum CapsuleMotion: String, Codable, CaseIterable, Identifiable {
  case still, gentle, kenBurns
  var id: Self { self }
  var title: String {
    switch self { case .still: "Still"; case .gentle: "Gentle motion"; case .kenBurns: "Ken Burns" }
  }
}
enum CapsulePace: String, Codable, CaseIterable, Identifiable {
  case relaxed, standard, lively
  var id: Self { self }
  var title: String { rawValue.capitalized }
  var seconds: Double {
    switch self { case .relaxed: 16; case .standard: 8; case .lively: 5 }
  }
}
enum CapsuleOrder: String, Codable, CaseIterable, Identifiable {
  case curated, chronological, shuffled
  var id: Self { self }
  var title: String {
    switch self { case .curated: "Selected order"; case .chronological: "Chronological"; case .shuffled: "Shuffle" }
  }
}
enum CapsuleWorkContext: String, Codable, CaseIterable, Identifiable {
  case composition, recording
  var id: Self { self }
  var title: String { self == .composition ? "Work & composer" : "This recording" }
}

struct CapsuleOptions: Codable, Equatable {
  var mode: CapsuleMode
  var topics: [CapsuleTopic]
  var subject: String
  var region: String
  var periodStart: String?
  var periodEnd: String?
  var workContext: CapsuleWorkContext = .composition
  var captions: CapsuleCaptions = .brief
  var motion: CapsuleMotion = .gentle
  var pace: CapsulePace = .standard
  var order: CapsuleOrder = .curated

  init(mode: CapsuleMode, subject: String, locale: String = Locale.current.identifier) {
    self.mode = mode
    self.subject = subject
    region = Locale(identifier: locale).region?.identifier ?? "GB"
    if mode == .period {
      let regions: [(String, String)] = [
        (#"\b(UK|British|Britain|United Kingdom)\b"#, "GB"),
        (#"\b(US|USA|American|Billboard|United States)\b"#, "US"),
        (#"\b(France|French)\b"#, "FR"), (#"\b(Germany|German)\b"#, "DE"),
        (#"\b(Australia|Australian)\b"#, "AU"), (#"\b(Brazil|Brazilian)\b"#, "BR"),
      ]
      if let matched = regions.first(where: { subject.range(of: $0.0, options: [.regularExpression, .caseInsensitive]) != nil }) {
        region = matched.1
      }
    }
    topics = mode.topics.filter { $0 != .historicalContext }
    if mode == .work || mode == .photos { pace = .relaxed }
    if mode == .photos { captions = .none; motion = .kenBurns }
  }

  var summary: String {
    let content = topics.map(\.title).joined(separator: ", ")
    return [mode == .photos ? "Personal photos" : content, captions.title, motion.title,
      "\(Int(pace.seconds)) seconds per picture"].filter { !$0.isEmpty }.joined(separator: " · ")
  }

  /// Remember presentation and content choices, never a previous subject or date window.
  mutating func restorePreferences(from defaults: UserDefaults = .standard) {
    guard let data = defaults.data(forKey: "cinema.preferences.\(mode.rawValue)"),
          let saved = try? JSONDecoder().decode(Self.self, from: data) else { return }
    topics = saved.topics
    captions = saved.captions; motion = saved.motion; pace = saved.pace; order = saved.order
  }
  func rememberPreferences(in defaults: UserDefaults = .standard) {
    var preferences = self
    preferences.subject = ""; preferences.region = ""
    preferences.periodStart = nil; preferences.periodEnd = nil
    if let data = try? JSONEncoder().encode(preferences) {
      defaults.set(data, forKey: "cinema.preferences.\(mode.rawValue)")
    }
  }
}

struct CapsuleSetup: Identifiable {
  let id = UUID()
  let request: CapsuleRequest
}
