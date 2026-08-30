import Foundation

enum SearchSelection {
  /// Keeps a visible result selected as AI results are corrected or reordered,
  /// and moves to the first result only when the current one disappears.
  static func resolved<ID: Hashable>(current: ID?, available: [ID]) -> ID? {
    if let current, available.contains(current) {
      return current
    }
    return available.first
  }
}
