import Darwin
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
    guard let host = lanHost(from: sender) else { return }
    var version: String?
    if let txt = sender.txtRecordData() {
      let dict = NetService.dictionary(fromTXTRecord: txt)
      if let ver = dict["ver"], let text = String(data: ver, encoding: .utf8) {
        version = text
      }
    }
    let bridge = DiscoveredBridge(
      name: sender.name,
      host: host,
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

  private func lanHost(from service: NetService) -> String? {
    let ips = ipv4Addresses(from: service)
    if let lan = ips.first(where: { $0.hasPrefix("192.168.") }) {
      return lan
    }
    if let first = ips.first {
      return first
    }
    guard let host = service.hostName else { return nil }
    return host.hasSuffix(".") ? String(host.dropLast()) : host
  }

  private func ipv4Addresses(from service: NetService) -> [String] {
    guard let addresses = service.addresses else { return [] }
    var ips: [String] = []
    for data in addresses {
      var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      let ok = data.withUnsafeBytes { raw -> Bool in
        guard raw.count >= MemoryLayout<sockaddr>.size else { return false }
        guard let sa = raw.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return false }
        guard sa.pointee.sa_family == sa_family_t(AF_INET) else { return false }
        return getnameinfo(
          sa,
          socklen_t(data.count),
          &hostname,
          socklen_t(hostname.count),
          nil,
          0,
          NI_NUMERICHOST
        ) == 0
      }
      guard ok else { continue }
      let ip = String(cString: hostname)
      if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") {
        ips.append(ip)
      }
    }
    return ips
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
