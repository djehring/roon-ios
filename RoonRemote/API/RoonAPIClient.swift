import Foundation

final class RoonAPIClient: CinemaClient, @unchecked Sendable {
  static let clientIdAccount = "client_id"
  static let hostAccount = "bridge_host"
  static let portAccount = "bridge_port"

  private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  private let session: URLSession
  private let imageSession: URLSession
  /// Status polling must not queue behind slow library browsing requests.
  private let cinemaSession: URLSession
  /// OpenAI-backed endpoints upload a photo or audio clip and then wait on model
  /// inference. The general session's 20s request / 60s resource budget cut those
  /// off mid-flight and surfaced as "The request timed out".
  private let aiSession: URLSession
  private var eventSession: URLSession?
  private var eventDelegate: EventStreamDelegate?
  private var eventTask: URLSessionDataTask?
  private var eventsTask: Task<Void, Never>?
  private var clientId: String?

  private(set) var host: String
  private(set) var port: Int
  private(set) var version: String?

  var onState: ((ApiStatePayload) -> Void)?
  var onZone: ((ZoneStatePayload) -> Void)?
  var onQueue: ((QueueStatePayload) -> Void)?
  var onConfig: ((SharedConfigPayload) -> Void)?
  var onEventsFailed: ((Error) -> Void)?

  init(host: String = "", port: Int = 3000) {
    self.host = host
    self.port = port
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 20
    config.timeoutIntervalForResource = 60
    config.waitsForConnectivity = false
    config.httpMaximumConnectionsPerHost = 4
    session = URLSession(configuration: config)
    let cinema = URLSessionConfiguration.default
    cinema.timeoutIntervalForRequest = 20
    cinema.timeoutIntervalForResource = 60
    cinema.waitsForConnectivity = false
    cinema.httpMaximumConnectionsPerHost = 2
    cinemaSession = URLSession(configuration: cinema)
    let images = URLSessionConfiguration.default
    images.timeoutIntervalForRequest = 12
    images.timeoutIntervalForResource = 20
    images.waitsForConnectivity = false
    images.httpMaximumConnectionsPerHost = 2
    imageSession = URLSession(configuration: images)
    let ai = URLSessionConfiguration.default
    ai.timeoutIntervalForRequest = 120
    ai.timeoutIntervalForResource = 240
    ai.waitsForConnectivity = false
    ai.httpMaximumConnectionsPerHost = 2
    aiSession = URLSession(configuration: ai)
    if let savedHost = KeychainStore.get(Self.hostAccount),
       let savedPort = KeychainStore.get(Self.portAccount).flatMap(Int.init)
    {
      self.host = savedHost
      self.port = savedPort
    }
    clientId = KeychainStore.get(Self.clientIdAccount)
  }

  var isPaired: Bool {
    clientId != nil && !host.isEmpty
  }

  var storedClientId: String? { clientId }

  func setBridge(host: String, port: Int) {
    self.host = host
    self.port = port
    KeychainStore.set(host, account: Self.hostAccount)
    KeychainStore.set(String(port), account: Self.portAccount)
  }

  func pair(pin: String) async throws {
    let request = try jsonRequest(
      path: "/api/pair",
      method: "POST",
      body: ["pin": pin]
    )
    let (_, response) = try await data(for: request)
    let http = try http(response)
    if http.statusCode == 403 {
      throw RoonAPIError.invalidPIN
    }
    guard http.statusCode == 201 else {
      throw RoonAPIError.httpStatus(http.statusCode, nil)
    }
    try storeClient(from: http)
  }

  func start() async throws {
    guard !host.isEmpty else { throw RoonAPIError.unpaired }
    try await pingVersion()
    var path = "/api/register"
    if let clientId {
      path += "/\(clientId)"
    }
    let request = try jsonRequest(path: path, method: "POST", body: nil as [String: String]?)
    let (_, response) = try await data(for: request)
    let http = try http(response)
    guard http.statusCode == 201 else {
      throw RoonAPIError.httpStatus(http.statusCode, nil)
    }
    try storeClient(from: http)
    startEventStream()
  }

  func stopEvents() {
    eventsTask?.cancel()
    eventsTask = nil
    eventTask?.cancel()
    eventTask = nil
    eventSession?.invalidateAndCancel()
    eventSession = nil
    eventDelegate = nil
  }

  func unpair() async {
    if let clientId {
      let request = try? jsonRequest(
        path: "/api/\(clientId)/unregister",
        method: "POST",
        body: nil as [String: String]?
      )
      if let request {
        _ = try? await session.data(for: request)
      }
    }
    stopEvents()
    self.clientId = nil
    KeychainStore.delete(Self.clientIdAccount)
    KeychainStore.delete(Self.hostAccount)
    KeychainStore.delete(Self.portAccount)
    host = ""
    port = 3000
  }

  func pairingPin() async throws -> String {
    let request = try jsonRequest(path: "/api/pairing", method: "GET", body: nil as [String: String]?)
    let (data, response) = try await data(for: request)
    try throwIfNeeded(response, data: data)
    return try decoder.decode(PairingPinResponse.self, from: data).pin
  }

  func rotatePairingPin() async throws -> String {
    let request = try jsonRequest(path: "/api/pairing", method: "POST", body: nil as [String: String]?)
    let (data, response) = try await data(for: request)
    try throwIfNeeded(response, data: data)
    return try decoder.decode(PairingPinResponse.self, from: data).pin
  }

  func command(_ payload: [String: Any]) async throws {
    let clientId = try requireClient()
    let request = try jsonRequest(
      path: "/api/\(clientId)/command",
      method: "POST",
      object: payload
    )
    let (data, response) = try await data(for: request)
    try throwIfNeeded(response, data: data, ok: [202])
  }

  func browse(_ options: [String: Any]) async throws -> BrowseResponse {
    let clientId = try requireClient()
    let request = try jsonRequest(
      path: "/api/\(clientId)/browse",
      method: "POST",
      object: options
    )
    let (data, response) = try await data(for: request)
    try throwIfNeeded(response, data: data)
    return try decoder.decode(BrowseResponse.self, from: data)
  }

  func load(_ options: [String: Any]) async throws -> LoadResponse {
    let clientId = try requireClient()
    let request = try jsonRequest(
      path: "/api/\(clientId)/load",
      method: "POST",
      object: options
    )
    let (data, response) = try await data(for: request)
    try throwIfNeeded(response, data: data)
    return try decoder.decode(LoadResponse.self, from: data)
  }

  func image(imageKey: String, width: Int = 400, height: Int = 400) async throws -> Data {
    var components = try urlComponents("/api/image")
    components.queryItems = [
      URLQueryItem(name: "image_key", value: imageKey),
      URLQueryItem(name: "scale", value: "fit"),
      URLQueryItem(name: "width", value: String(width)),
      URLQueryItem(name: "height", value: String(height)),
    ]
    guard let url = components.url else { throw RoonAPIError.invalidURL }
    let (data, response) = try await imageSession.data(from: url)
    try throwIfNeeded(response, data: data)
    return data
  }

  func aiSearch(query: String) async throws -> [SuggestedTrackPayload] {
    let clientId = try requireClient()
    var request = try rawRequest(path: "/api/\(clientId)/aisearch", method: "POST")
    request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(query.utf8)
    let (data, response) = try await data(for: request, using: aiSession)
    try throwIfOpenAI(response, data: data)
    return try decoder.decode([SuggestedTrackPayload].self, from: data)
  }

  func playTracks(zoneId: String, tracks: [[String: String]]) async throws -> [SuggestedTrackPayload] {
    let clientId = try requireClient()
    let request = try jsonRequest(
      path: "/api/\(clientId)/play-tracks",
      method: "POST",
      object: ["zoneId": zoneId, "tracks": tracks]
    )
    let (data, response) = try await data(for: request, using: aiSession)
    try throwIfNeeded(response, data: data)
    return try decoder.decode([SuggestedTrackPayload].self, from: data)
  }

  func timeCapsules() async throws -> [TimeCapsule] {
    try decoder.decode([TimeCapsule].self, from: await capsuleResponse(""))
  }

  func createTimeCapsule(_ input: CapsuleRequest) async throws -> CapsuleJob {
    let body = try JSONEncoder().encode(input)
    return try decoder.decode(CapsuleJob.self, from: await capsuleResponse("", method: "POST", body: body))
  }

  func requireCinemaOptionsSupport() async throws {
    struct Capabilities: Decodable { var optionsVersion: Int }
    do {
      let capabilities = try decoder.decode(Capabilities.self, from: await capsuleResponse("capabilities"))
      guard capabilities.optionsVersion >= 2 else {
        throw PersonalCinemaError("Update the bridge to use Cinema's content and presentation options.")
      }
    } catch {
      if case RoonAPIError.httpStatus(404, _) = error {
        throw PersonalCinemaError("Update the bridge to use Cinema's content and presentation options.")
      }
      throw error
    }
  }

  func rebuildTimeCapsule(_ id: String) async throws -> CapsuleJob {
    try decoder.decode(CapsuleJob.self,
      from: await capsuleResponse("\(capsuleComponent(id))/rebuild", method: "POST"))
  }

  func requireCinemaManagementSupport() async throws {
    struct Capabilities: Decodable { var managementVersion: Int? }
    do {
      let capabilities = try decoder.decode(Capabilities.self, from: await capsuleResponse("capabilities"))
      guard (capabilities.managementVersion ?? 0) >= 1 else {
        throw PersonalCinemaError("Update the bridge to edit and delete Cinema playlists.")
      }
    } catch {
      if case RoonAPIError.httpStatus(404, _) = error {
        throw PersonalCinemaError("Update the bridge to edit and delete Cinema playlists.")
      }
      throw error
    }
  }

  func updateTimeCapsule(_ id: String, options: CapsuleOptions) async throws -> CapsuleJob {
    let body = try JSONEncoder().encode(["options": options])
    return try decoder.decode(CapsuleJob.self,
      from: await capsuleResponse(capsuleComponent(id), method: "PUT", body: body))
  }

  func deleteTimeCapsule(_ id: String) async throws {
    _ = try await capsuleResponse(capsuleComponent(id), method: "DELETE")
  }

  func timeCapsuleJob(_ id: String, generation: String? = nil) async throws -> CapsuleJob {
    var request = try capsuleRequest("jobs/\(capsuleComponent(id))", method: "GET")
    if let generation, let url = request.url {
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
      components?.queryItems = [URLQueryItem(name: "generation", value: generation)]
      request.url = components?.url
    }
    let (bytes, response) = try await data(for: request, using: cinemaSession)
    try throwIfNeeded(response, data: bytes, ok: [200])
    return try decoder.decode(CapsuleJob.self, from: bytes)
  }

  func cinemaArtwork(tracks: [CapsuleTrack], zoneId: String) async throws -> Data? {
    struct Input: Encodable { let tracks: [CapsuleTrack]; let zoneId: String }
    struct Output: Decodable { let imageKey: String? }
    let body = try JSONEncoder().encode(Input(tracks: tracks, zoneId: zoneId))
    let output = try decoder.decode(Output.self, from: await capsuleResponse("artwork", method: "POST", body: body))
    guard let key = output.imageKey else { return nil }
    return try await image(imageKey: key, width: ArtworkCache.heroPixels, height: ArtworkCache.heroPixels)
  }

  func zoneTimeCapsule(_ zoneId: String) async throws -> TimeCapsule? {
    let bytes = try await capsuleResponse("zone/\(capsuleComponent(zoneId))")
    return bytes.isEmpty ? nil : try decoder.decode(TimeCapsule.self, from: bytes)
  }

  func setTimeCapsule(_ id: String, zoneId: String) async throws {
    let body = try JSONEncoder().encode(["capsuleId": id])
    _ = try await capsuleResponse("zone/\(capsuleComponent(zoneId))", method: "PUT", body: body)
  }

  func timeCapsuleImageURL(_ file: String) -> URL? {
    #if DEBUG
    if let base = ProcessInfo.processInfo.environment["ROON_CINEMA_PREVIEW_ASSETS"], let url = URL(string: base) {
      return url.appendingPathComponent(file + ".image")
    }
    #endif
    return try? capsuleRequest("images/\(capsuleComponent(file))", method: "GET").url
  }

  private func capsuleComponent(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
  }

  private func capsuleResponse(_ suffix: String, method: String = "GET", body: Data? = nil) async throws -> Data {
    var request = try capsuleRequest(suffix, method: method)
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = body
    }
    let (bytes, response) = try await data(for: request, using: cinemaSession)
    try throwIfNeeded(response, data: bytes, ok: [200, 202, 204])
    return bytes
  }

  private func capsuleRequest(_ encodedSuffix: String, method: String) throws -> URLRequest {
    let clientId = try requireClient()
    var components = try urlComponents("/api/\(clientId)/time-capsules/")
    // Segment escaping must happen once; URLComponents.path would escape '%' again.
    components.percentEncodedPath += encodedSuffix
    guard let url = components.url else { throw RoonAPIError.invalidURL }
    var request = URLRequest(url: url)
    request.httpMethod = method
    return request
  }

  func transcribe(audio: Data) async throws -> String {
    let clientId = try requireClient()
    let boundary = UUID().uuidString
    var request = try rawRequest(path: "/api/\(clientId)/transcribe", method: "POST")
    request.setValue(
      "multipart/form-data; boundary=\(boundary)",
      forHTTPHeaderField: "Content-Type"
    )
    var body = Data()
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append(
      "Content-Disposition: form-data; name=\"audio\"; filename=\"audio.m4a\"\r\n"
        .data(using: .utf8)!
    )
    body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
    body.append(audio)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    request.httpBody = body
    let (data, response) = try await data(for: request, using: aiSession)
    try throwIfOpenAI(response, data: data)
    struct TextBody: Decodable { var text: String }
    return try decoder.decode(TextBody.self, from: data).text
  }

  func trackStory(artist: String, track: String) async throws -> TrackStoryPayload {
    let clientId = try requireClient()
    let request = try jsonRequest(
      path: "/api/\(clientId)/trackstory",
      method: "POST",
      object: ["artist": artist, "track": track]
    )
    let (data, response) = try await data(for: request, using: aiSession)
    try throwIfOpenAI(response, data: data)
    struct Wrapper: Decodable { var story: TrackStoryPayload }
    if let wrapped = try? decoder.decode(Wrapper.self, from: data) {
      return wrapped.story
    }
    return try decoder.decode(TrackStoryPayload.self, from: data)
  }

  func recognizeAlbum(
    zoneId: String,
    image: Data?,
    mimeType: String?,
    textHint: String?
  ) async throws -> RecognizeAlbumResponse {
    let clientId = try requireClient()
    var payload: [String: Any] = ["zoneId": zoneId]
    if let image {
      payload["image"] = image.base64EncodedString()
    }
    if let mimeType {
      payload["mimeType"] = mimeType
    }
    if let textHint, !textHint.isEmpty {
      payload["textHint"] = textHint
    }
    let request = try jsonRequest(
      path: "/api/\(clientId)/recognize-album",
      method: "POST",
      object: payload
    )
    let (data, response) = try await data(for: request, using: aiSession)
    try throwIfOpenAI(response, data: data)
    return try decoder.decode(RecognizeAlbumResponse.self, from: data)
  }

  func playItem(zoneId: String, itemKey: String, actionTitle: String) async throws {
    let clientId = try requireClient()
    let request = try jsonRequest(
      path: "/api/\(clientId)/library/play-item",
      method: "POST",
      object: [
        "zoneId": zoneId,
        "item_key": itemKey,
        "actionTitle": actionTitle,
      ]
    )
    let (data, response) = try await data(for: request)
    try throwIfNeeded(response, data: data, ok: [204, 200])
  }

  func searchAlbums(zoneId: String, query: String) async throws -> [LibraryAlbumItem] {
    let clientId = try requireClient()
    let request = try jsonRequest(
      path: "/api/\(clientId)/library/search-albums",
      method: "POST",
      object: ["zoneId": zoneId, "query": query]
    )
    let (data, response) = try await data(for: request)
    try throwIfNeeded(response, data: data)
    struct Wrapper: Decodable { var items: [LibraryAlbumItem] }
    return try decoder.decode(Wrapper.self, from: data).items
  }

  func sharedConfig(_ actions: [[String: Any]]) async throws {
    try await command([
      "type": "SHARED_CONFIG",
      "data": ["sharedConfigUpdate": ["customActions": actions]],
    ])
  }

  private func pingVersion() async throws {
    var request = try rawRequest(path: "/api/version", method: "GET")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (_, response) = try await data(for: request)
    let http = try http(response)
    guard http.statusCode == 204 else {
      throw RoonAPIError.httpStatus(http.statusCode, nil)
    }
    version = http.value(forHTTPHeaderField: "x-roon-web-stack-version")
  }

  func refreshEvents() {
    guard isPaired else { return }
    startEventStream()
  }

  private func startEventStream() {
    stopEvents()
    guard let clientId else { return }
    eventsTask = Task { [weak self] in
      await self?.readEvents(clientId: clientId)
    }
  }

  private func readEvents(clientId: String) async {
    while !Task.isCancelled {
      eventTask?.cancel()
      eventSession?.invalidateAndCancel()
      eventSession = nil
      eventDelegate = nil
      do {
        var request = try rawRequest(path: "/api/\(clientId)/events", method: "GET")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let delegate = EventStreamDelegate()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval.infinity
        config.timeoutIntervalForResource = TimeInterval.infinity
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let streamSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        eventDelegate = delegate
        eventSession = streamSession
        let task = streamSession.dataTask(with: request)
        eventTask = task
        task.resume()

        var buffer = Data()
        for try await chunk in delegate.chunks {
          if Task.isCancelled { return }
          buffer.append(chunk)
          consumeSSE(from: &buffer)
        }
      } catch {
        if Task.isCancelled { return }
        onEventsFailed?(error)
      }
      if Task.isCancelled { return }
      try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
  }

  private func consumeSSE(from buffer: inout Data) {
    let lf = Data("\n\n".utf8)
    let crlf = Data("\r\n\r\n".utf8)
    while true {
      let lfRange = buffer.range(of: lf)
      let crlfRange = buffer.range(of: crlf)
      let range: Range<Data.Index>?
      if let lfRange, let crlfRange {
        range = lfRange.lowerBound <= crlfRange.lowerBound ? lfRange : crlfRange
      } else {
        range = lfRange ?? crlfRange
      }
      guard let range else { return }
      let packet = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
      buffer.removeSubrange(buffer.startIndex..<range.upperBound)
      parseSSEPacket(packet)
    }
  }

  private func parseSSEPacket(_ packet: Data) {
    guard let text = String(data: packet, encoding: .utf8) else { return }
    var eventName = ""
    var dataLines: [String] = []
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
      var line = String(raw)
      if line.hasSuffix("\r") { line.removeLast() }
      if line.hasPrefix("event:") {
        eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
      } else if line.hasPrefix("data:") {
        var value = String(line.dropFirst(5))
        if value.hasPrefix(" ") { value.removeFirst() }
        dataLines.append(value)
      }
    }
    flushSSE(event: eventName, data: dataLines.joined(separator: "\n"))
  }

  private func flushSSE(event: String, data: String) {
    guard !data.isEmpty, let payload = data.data(using: .utf8) else { return }
    switch event {
    case "state":
      do {
        onState?(try decoder.decode(ApiStatePayload.self, from: payload))
      } catch {
        onEventsFailed?(error)
      }
    case "zone":
      do {
        onZone?(try decoder.decode(ZoneStatePayload.self, from: payload))
      } catch {
        NSLog("zone decode failed: %@", error.localizedDescription)
      }
    case "queue":
      do {
        onQueue?(try decoder.decode(QueueStatePayload.self, from: payload))
      } catch {
        NSLog("queue decode failed: %@", error.localizedDescription)
      }
    case "config":
      if let value = try? decoder.decode(SharedConfigPayload.self, from: payload) {
        onConfig?(value)
      }
    default:
      if let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
         object["tracks"] != nil || object["items"] != nil,
         let queue = try? decoder.decode(QueueStatePayload.self, from: payload)
      {
        onQueue?(queue)
      }
    }
  }

  private func storeClient(from http: HTTPURLResponse) throws {
    guard let location = http.value(forHTTPHeaderField: "Location")
      ?? http.value(forHTTPHeaderField: "location")
      ?? http.allHeaderFields["Location"] as? String
      ?? http.allHeaderFields["location"] as? String
    else {
      throw RoonAPIError.missingLocation
    }
    let id = location.split(separator: "/").last.map(String.init) ?? location.replacingOccurrences(
      of: "/api/",
      with: ""
    )
    guard !id.isEmpty else { throw RoonAPIError.missingLocation }
    clientId = id
    KeychainStore.set(id, account: Self.clientIdAccount)
  }

  private func requireClient() throws -> String {
    guard let clientId else { throw RoonAPIError.unpaired }
    return clientId
  }

  private func data(
    for request: URLRequest,
    using override: URLSession? = nil
  ) async throws -> (Data, URLResponse) {
    let session = override ?? self.session
    let first = try await session.data(for: request)
    let path = request.url?.path ?? ""
    if (try? http(first.1))?.statusCode != 403 {
      return first
    }
    if path.contains("/pair") || path.contains("/register") || path.contains("/pairing") {
      return first
    }
    try await reregister()
    return try await session.data(for: request)
  }

  private func reregister() async throws {
    let id = try requireClient()
    let request = try jsonRequest(
      path: "/api/register/\(id)",
      method: "POST",
      body: nil as [String: String]?
    )
    let (_, response) = try await session.data(for: request)
    let http = try http(response)
    guard http.statusCode == 201 else {
      throw RoonAPIError.httpStatus(http.statusCode, nil)
    }
    try storeClient(from: http)
    startEventStream()
  }

  private func jsonRequest<T: Encodable>(
    path: String,
    method: String,
    body: T?
  ) throws -> URLRequest {
    var request = try rawRequest(path: path, method: method)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if body != nil {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(body)
    }
    return request
  }

  private func jsonRequest(path: String, method: String, object: [String: Any]) throws -> URLRequest {
    var request = try rawRequest(path: path, method: method)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: object)
    return request
  }

  private func rawRequest(path: String, method: String) throws -> URLRequest {
    guard let url = try urlComponents(path).url else { throw RoonAPIError.invalidURL }
    var request = URLRequest(url: url)
    request.httpMethod = method
    if path.hasSuffix("/browse") {
      request.timeoutInterval = 15
    }
    return request
  }

  private func urlComponents(_ path: String) throws -> URLComponents {
    var components = URLComponents()
    components.scheme = "http"
    components.host = host
    components.port = port
    components.path = path
    if components.host == nil || components.host?.isEmpty == true {
      throw RoonAPIError.invalidURL
    }
    return components
  }

  private func http(_ response: URLResponse) throws -> HTTPURLResponse {
    guard let http = response as? HTTPURLResponse else { throw RoonAPIError.invalidURL }
    return http
  }

  private func throwIfNeeded(
    _ response: URLResponse,
    data: Data,
    ok: Set<Int> = [200]
  ) throws {
    let http = try http(response)
    if ok.contains(http.statusCode) { return }
    let message = try? decoder.decode(APIErrorBody.self, from: data).error
    throw RoonAPIError.httpStatus(http.statusCode, message)
  }

  private func throwIfOpenAI(_ response: URLResponse, data: Data) throws {
    let http = try http(response)
    if http.statusCode == 503 {
      throw RoonAPIError.missingOpenAI
    }
    try throwIfNeeded(response, data: data)
  }
}

private final class EventStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  let chunks: AsyncThrowingStream<Data, Error>
  private let continuation: AsyncThrowingStream<Data, Error>.Continuation
  private var finished = false

  override init() {
    var continuation: AsyncThrowingStream<Data, Error>.Continuation!
    chunks = AsyncThrowingStream { continuation = $0 }
    self.continuation = continuation
    super.init()
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let http = response as? HTTPURLResponse else {
      finish(RoonAPIError.invalidURL)
      completionHandler(.cancel)
      return
    }
    guard http.statusCode == 200 else {
      finish(RoonAPIError.httpStatus(http.statusCode, nil))
      completionHandler(.cancel)
      return
    }
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    continuation.yield(data)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error, (error as NSError).code != NSURLErrorCancelled {
      finish(error)
    } else {
      finish(nil)
    }
  }

  private func finish(_ error: Error?) {
    guard !finished else { return }
    finished = true
    if let error {
      continuation.finish(throwing: error)
    } else {
      continuation.finish()
    }
  }
}
