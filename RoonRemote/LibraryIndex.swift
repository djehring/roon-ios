import Foundation

enum LibraryIndex {
  static let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ#")

  static func jumpTarget(for letter: Character, in items: [BrowseNode]) -> BrowseNode.ID? {
    if letter == "#" {
      return items.first { item in
        guard let first = item.title.uppercased().first else { return false }
        return !first.isLetter
      }?.id
    }
    return items.first {
      $0.title.uppercased().hasPrefix(String(letter))
    }?.id
  }
}
