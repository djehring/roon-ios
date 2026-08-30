import Foundation
import Testing

@Suite("ArtworkCache")
struct ArtworkCacheTests {
  private func key(_ imageKey: String, _ pixels: Int = 128) -> ArtworkCache.Key {
    ArtworkCache.Key(imageKey: imageKey, pixels: pixels)
  }

  private func blob(_ bytes: Int) -> Data {
    Data(repeating: 0xAB, count: bytes)
  }

  @Test("stores and returns artwork")
  func roundTrip() {
    var cache = ArtworkCache(budget: 1000)
    cache.insert(blob(10), for: key("a"))

    #expect(cache.data(for: key("a")) == blob(10))
    #expect(cache.contains(key("a")))
    #expect(cache.count == 1)
    #expect(cache.bytes == 10)
  }

  @Test("misses report nothing rather than a neighbouring size")
  func miss() {
    var cache = ArtworkCache(budget: 1000)
    cache.insert(blob(10), for: key("a"))

    #expect(cache.data(for: key("b")) == nil)
    #expect(!cache.contains(key("b")))
  }

  @Test("one image key at two pixel sizes is two entries")
  func sizesAreDistinct() {
    var cache = ArtworkCache(budget: 1000)
    let thumbnail = key("a", ArtworkCache.thumbnailPixels)
    let hero = key("a", ArtworkCache.heroPixels)

    cache.insert(blob(10), for: thumbnail)
    cache.insert(blob(200), for: hero)

    #expect(cache.count == 2)
    #expect(cache.data(for: thumbnail)?.count == 10)
    #expect(cache.data(for: hero)?.count == 200)
    #expect(cache.bytes == 210)
  }

  @Test("re-inserting a key replaces it without double counting bytes")
  func replace() {
    var cache = ArtworkCache(budget: 1000)
    cache.insert(blob(10), for: key("a"))
    cache.insert(blob(40), for: key("a"))

    #expect(cache.count == 1)
    #expect(cache.bytes == 40)
    #expect(cache.data(for: key("a"))?.count == 40)
  }

  @Test("eviction drops oldest insertions until back inside the budget")
  func evictsOldestFirst() {
    var cache = ArtworkCache(budget: 100)
    cache.insert(blob(40), for: key("a"))
    cache.insert(blob(40), for: key("b"))
    cache.insert(blob(40), for: key("c"))

    #expect(cache.bytes <= 100)
    #expect(!cache.contains(key("a")))
    #expect(cache.contains(key("b")))
    #expect(cache.contains(key("c")))
  }

  @Test("replacing a key does not move it to the back of the eviction queue")
  func replaceKeepsPosition() {
    var cache = ArtworkCache(budget: 100)
    cache.insert(blob(40), for: key("a"))
    cache.insert(blob(40), for: key("b"))
    cache.insert(blob(40), for: key("a"))
    cache.insert(blob(40), for: key("c"))

    // "a" was written twice but first in, so the next eviction still takes it.
    #expect(!cache.contains(key("a")))
    #expect(cache.contains(key("b")))
    #expect(cache.contains(key("c")))
  }

  @Test("pinned artwork survives eviction pressure")
  func pinnedSurvives() {
    var cache = ArtworkCache(budget: 100)
    cache.insert(blob(40), for: key("hero"))
    cache.setPinned([key("hero")])

    for index in 0..<10 {
      cache.insert(blob(40), for: key("row\(index)"))
    }

    #expect(cache.contains(key("hero")))
  }

  @Test("an entry larger than the whole budget is still kept")
  func oversizedEntryIsKept() {
    var cache = ArtworkCache(budget: 100)
    cache.insert(blob(500), for: key("huge"))

    #expect(cache.contains(key("huge")))
    #expect(cache.bytes == 500)
  }

  @Test("an oversized entry does not permanently starve later inserts")
  func oversizedEntryIsEvictedLater() {
    var cache = ArtworkCache(budget: 100)
    cache.insert(blob(500), for: key("huge"))
    cache.insert(blob(10), for: key("small"))

    #expect(!cache.contains(key("huge")))
    #expect(cache.contains(key("small")))
    #expect(cache.bytes == 10)
  }

  @Test("memory pressure clears everything except the pins")
  func evictUnpinned() {
    var cache = ArtworkCache(budget: 10_000)
    cache.insert(blob(40), for: key("hero"))
    cache.insert(blob(40), for: key("row1"))
    cache.insert(blob(40), for: key("row2"))
    cache.setPinned([key("hero")])

    cache.evictUnpinned()

    #expect(cache.count == 1)
    #expect(cache.bytes == 40)
    #expect(cache.contains(key("hero")))
    #expect(!cache.contains(key("row1")))
  }

  @Test("pinned keys are readable so callers can skip redundant writes")
  func pinnedKeysAreReadable() {
    var cache = ArtworkCache(budget: 1000)
    #expect(cache.pinnedKeys.isEmpty)

    cache.setPinned([key("a"), key("a", ArtworkCache.heroPixels)])

    #expect(cache.pinnedKeys == [key("a"), key("a", ArtworkCache.heroPixels)])
  }

  @Test("pinning a new set releases the previous pins")
  func repinning() {
    var cache = ArtworkCache(budget: 10_000)
    cache.insert(blob(40), for: key("first"))
    cache.insert(blob(40), for: key("second"))
    cache.setPinned([key("first")])
    cache.setPinned([key("second")])

    cache.evictUnpinned()

    #expect(cache.contains(key("second")))
    #expect(!cache.contains(key("first")))
  }

  @Test("removeAll empties the cache and its pins")
  func removeAll() {
    var cache = ArtworkCache(budget: 10_000)
    cache.insert(blob(40), for: key("a"))
    cache.setPinned([key("a")])

    cache.removeAll()

    #expect(cache.count == 0)
    #expect(cache.bytes == 0)

    // A cleared pin must not keep protecting anything that is inserted later.
    cache.budget = 50
    cache.insert(blob(40), for: key("a"))
    cache.insert(blob(40), for: key("b"))
    #expect(!cache.contains(key("a")))
  }

  @Test("hero artwork is requested large enough for a 3x compact hero")
  func heroPixelsCoverTheLargestHero() {
    // 340pt at 3x, the compact hero on the widest iPhone.
    #expect(ArtworkCache.heroPixels >= 340 * 3)
    #expect(ArtworkCache.heroPixels > ArtworkCache.thumbnailPixels)
  }
}
