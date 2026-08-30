import Foundation

/// Byte-budgeted store for cover artwork, keyed by image key *and* pixel size so
/// that a 48pt list thumbnail and a full-size Now Playing hero of the same album
/// can be held at once.
///
/// Reads are deliberately non-mutating. Views call them from `body`, and an
/// least-recently-used policy would have to record the access, writing to
/// observable state during evaluation. Eviction is insertion-ordered instead,
/// with `setPinned(_:)` to protect artwork that stays on screen far longer than
/// it was last touched.
struct ArtworkCache {
  struct Key: Hashable {
    let imageKey: String
    let pixels: Int
  }

  /// Pixel size for artwork in list rows.
  static let thumbnailPixels = 128

  /// Pixel size for full-bleed and Now Playing artwork. One size covers every
  /// display: a 340pt iPhone hero at 3x wants ~1020px and a 520pt iPad hero at
  /// 2x wants ~1040px, so resizing a window never forces a second fetch.
  static let heroPixels = 1200

  /// Bytes of artwork to hold before evicting. An entry larger than the whole
  /// budget is still kept, so `bytes` can legitimately exceed this.
  var budget: Int

  private(set) var bytes = 0
  private var entries: [Key: Data] = [:]
  private var insertions: [Key] = []
  private var pinned: Set<Key> = []

  init(budget: Int) {
    self.budget = budget
  }

  var count: Int { entries.count }

  var pinnedKeys: Set<Key> { pinned }

  func data(for key: Key) -> Data? { entries[key] }

  func contains(_ key: Key) -> Bool { entries[key] != nil }

  mutating func insert(_ data: Data, for key: Key) {
    if let existing = entries[key] {
      bytes -= existing.count
    } else {
      insertions.append(key)
    }
    entries[key] = data
    bytes += data.count
    evict(keeping: key)
  }

  /// Replaces the set of keys eviction must not touch. Callers declare the whole
  /// set — typically the playing track's artwork at every size in use — so they
  /// never have to remember what they pinned last.
  mutating func setPinned(_ keys: Set<Key>) {
    pinned = keys
  }

  /// Drops everything except the pinned keys. Used on memory pressure, where
  /// keeping the artwork that is currently on screen matters more than the
  /// scroll-back cache.
  mutating func evictUnpinned() {
    for key in insertions where !pinned.contains(key) {
      if let data = entries.removeValue(forKey: key) {
        bytes -= data.count
      }
    }
    insertions.removeAll { !pinned.contains($0) }
  }

  mutating func removeAll() {
    entries.removeAll()
    insertions.removeAll()
    pinned.removeAll()
    bytes = 0
  }

  /// Evicts oldest-first until back inside the budget. `newest` is spared so a
  /// single insert can never immediately discard itself.
  private mutating func evict(keeping newest: Key) {
    var index = 0
    while bytes > budget, index < insertions.count {
      let candidate = insertions[index]
      if candidate == newest || pinned.contains(candidate) {
        index += 1
        continue
      }
      if let data = entries.removeValue(forKey: candidate) {
        bytes -= data.count
      }
      insertions.remove(at: index)
    }
  }
}
