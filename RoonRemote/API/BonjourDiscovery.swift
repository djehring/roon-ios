import Foundation

@MainActor
final class BonjourDiscovery: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
  private let browser = NetServiceBrowser()
  private var resolving: [NetService] = []
  private var found: [DiscoveredBridge] = []
  private var continuation: CheckedContinuation<[DiscoveredBridge], Never>?
  private var timeoutWork: DispatchWorkItem?

  func discover(timeout: TimeInterval = 8) async -> [DiscoveredBridge] {
    if let pending = continuation {
      pending.resume(returning: found)
      continuation = nil
    }
    found = []
    resolving = []
    return await withCheckedContinuation { cont in
      continuation = cont
      browser.delegate = self
      browser.searchForServices(ofType: "_roon-web-stack._tcp.", inDomain: "local.")
      let work = DispatchWorkItem { [weak self] in
        self?.finish()
      }
      timeoutWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }
  }

  func stop() {
    timeoutWork?.cancel()
    browser.stop()
    finish()
  }

  func netServiceBrowser(
    _ browser: NetServiceBrowser,
    didFind service: NetService,
    moreComing: Bool
  ) {
    service.delegate = self
    service.resolve(withTimeout: 5)
    resolving.append(service)
  }

  func netServiceDidResolveAddress(_ sender: NetService) {
    guard let host = sender.hostName else { return }
    var version: String?
    if let txt = sender.txtRecordData() {
      let dict = NetService.dictionary(fromTXTRecord: txt)
      if let ver = dict["ver"], let text = String(data: ver, encoding: .utf8) {
        version = text
      }
    }
    let trimmed = host.hasSuffix(".") ? String(host.dropLast()) : host
    let bridge = DiscoveredBridge(
      name: sender.name,
      host: trimmed,
      port: sender.port,
      version: version
    )
    if !found.contains(bridge) {
      found.append(bridge)
    }
  }

  func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
    finish()
  }

  private func finish() {
    timeoutWork?.cancel()
    timeoutWork = nil
    browser.stop()
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(returning: found)
  }
}
