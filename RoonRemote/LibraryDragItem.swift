import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
  static let roonLibraryItem = UTType(exportedAs: "com.djehring.roonremote.library-item")
}

struct LibraryDragItem: Codable, Hashable, Transferable {
  let hierarchy: String
  let itemKey: String
  let title: String
  let hint: String?

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .roonLibraryItem)
  }
}
