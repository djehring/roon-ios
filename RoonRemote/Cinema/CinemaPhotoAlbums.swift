#if os(iOS)
import Photos
import SwiftUI

struct CinemaPhotoAlbum: Identifiable {
  enum Group: String, CaseIterable {
    case albums = "My albums", shared = "Shared albums", photos = "From Photos"
  }

  let id: String
  let title: String
  let folder: String?
  let group: Group
  let assets: PHFetchResult<PHAsset>
  let cover: PHAsset?
  var count: Int { assets.count }
}

enum CinemaPhotoLibrary {
  static func imageOptions() -> PHFetchOptions {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
    return options
  }

  static func albums() -> [CinemaPhotoAlbum] {
    var folders: [String: String] = [:]
    func visit(_ collections: PHFetchResult<PHCollection>, path: [String]) {
      collections.enumerateObjects { collection, _, _ in
        if let folder = collection as? PHCollectionList {
          visit(PHCollection.fetchCollections(in: folder, options: nil),
            path: path + [folder.localizedTitle ?? "Untitled folder"])
        } else if !path.isEmpty {
          folders[collection.localIdentifier] = path.joined(separator: " / ")
        }
      }
    }
    visit(PHCollectionList.fetchTopLevelUserCollections(with: nil), path: [])

    var found: [CinemaPhotoAlbum] = []
    func append(_ collection: PHAssetCollection, group: CinemaPhotoAlbum.Group) {
      let assets = PHAsset.fetchAssets(in: collection, options: imageOptions())
      guard assets.count > 0 else { return }
      let title = collection.localizedTitle
      found.append(CinemaPhotoAlbum(id: collection.localIdentifier,
        title: title.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? "Untitled album",
        folder: folders[collection.localIdentifier], group: group, assets: assets,
        cover: PHAsset.fetchKeyAssets(in: collection, options: imageOptions())?.firstObject ?? assets.firstObject))
    }
    PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
      .enumerateObjects { collection, _, _ in
        append(collection, group: collection.assetCollectionSubtype == .albumCloudShared ? .shared : .albums)
      }
    // Only public, photo-based collections. Hidden and Recently Deleted stay private.
    let types: Set<PHAssetCollectionSubtype> = [.smartAlbumUserLibrary, .smartAlbumFavorites,
      .smartAlbumRecentlyAdded, .smartAlbumPanoramas, .smartAlbumSelfPortraits,
      .smartAlbumScreenshots, .smartAlbumLivePhotos, .smartAlbumDepthEffect, .smartAlbumLongExposures]
    PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
      .enumerateObjects { collection, _, _ in
        if types.contains(collection.assetCollectionSubtype) { append(collection, group: .photos) }
      }
    return found.sorted {
      let comparison = $0.title.localizedStandardCompare($1.title)
      if comparison == .orderedSame { return ($0.folder ?? "") < ($1.folder ?? "") }
      return comparison == .orderedAscending
    }
  }
}

struct CinemaPhotoAlbumPicker: View {
  @Bindable var selection: CinemaPhotoSelection
  @Environment(\.openURL) private var openURL
  @State private var search = ""

  private var albums: [CinemaPhotoAlbum] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    return selection.albums.filter {
      query.isEmpty || $0.title.localizedStandardContains(query) || ($0.folder?.localizedStandardContains(query) ?? false)
    }
  }

  var body: some View {
    NavigationStack {
      Group {
        if selection.loadingAlbums {
          ProgressView("Loading albums…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = selection.message {
          ContentUnavailableView {
            Label("Your Photos albums", systemImage: "photo.on.rectangle")
          } description: { Text(message) } actions: {
            if PHPhotoLibrary.authorizationStatus(for: .readWrite) != .authorized {
              Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            }
            Button("Try again") { Task { await selection.findAlbums() } }
          }
        } else {
          List {
            ForEach(CinemaPhotoAlbum.Group.allCases, id: \.self) { group in
              let grouped = albums.filter { $0.group == group }
              if !grouped.isEmpty {
                Section(group.rawValue) {
                  ForEach(grouped) { album in
                    NavigationLink {
                      CinemaPhotoAlbumPreview(album: album, selection: selection)
                    } label: {
                      HStack(spacing: 14) {
                        CinemaPhotoThumbnail(asset: album.cover)
                          .frame(width: 72, height: 72)
                          .clipShape(RoundedRectangle(cornerRadius: 8))
                          .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                          Text(album.title).font(.headline).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                          if let folder = album.folder { Text(folder).font(.caption).foregroundStyle(.secondary) }
                          Text("\(album.count) photos").font(.subheadline).foregroundStyle(.secondary)
                        }
                      }.padding(.vertical, 4)
                    }.accessibilityIdentifier("cinema-album-\(album.id)")
                  }
                }
              }
            }
          }
          .overlay { if albums.isEmpty { ContentUnavailableView.search(text: search) } }
          .searchable(text: $search, prompt: "Album or folder name")
        }
      }
      .navigationTitle("Choose an album")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { selection.showingAlbums = false }
        }
      }
      .safeAreaInset(edge: .bottom) {
        Text("Open an album to preview its photos. Choose up to 200 for your montage.")
          .font(.footnote).foregroundStyle(.secondary).padding().frame(maxWidth: .infinity).background(.bar)
      }
    }
    .task { await selection.findAlbums() }
  }
}

private struct CinemaPhotoAlbumPreview: View {
  let album: CinemaPhotoAlbum
  @Bindable var selection: CinemaPhotoSelection
  @State private var selected: Set<String>

  init(album: CinemaPhotoAlbum, selection: CinemaPhotoSelection) {
    self.album = album
    self.selection = selection
    let ids: [String]
    if selection.album?.id == album.id { ids = selection.albumAssetIDs }
    else if album.count <= CinemaPhotoSelection.limit {
      ids = (0..<album.count).map { album.assets.object(at: $0).localIdentifier }
    } else { ids = [] }
    _selected = State(initialValue: Set(ids))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
          Text(album.title).font(.title2.bold())
          if let folder = album.folder { Text(folder).foregroundStyle(.secondary) }
          Text("\(album.count) photos · \(selected.count) selected").foregroundStyle(.secondary)
          if album.count > CinemaPhotoSelection.limit {
            Text("Choose up to 200 photos from this album.").font(.subheadline)
          }
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
          ForEach(0..<album.count, id: \.self) { index in
            let asset = album.assets.object(at: index)
            let isSelected = selected.contains(asset.localIdentifier)
            Button {
              if isSelected { selected.remove(asset.localIdentifier) }
              else if selected.count < CinemaPhotoSelection.limit { selected.insert(asset.localIdentifier) }
            } label: {
              CinemaPhotoThumbnail(asset: asset)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                  Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(isSelected ? Color.accentColor : .white)
                    .background(Circle().fill(.black.opacity(0.6)))
                    .padding(6)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Photo \(index + 1)")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityIdentifier("cinema-album-photo-\(index)")
            .disabled(!isSelected && selected.count >= CinemaPhotoSelection.limit)
          }
        }
      }.padding()
    }
    .navigationTitle("Preview album")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        if !selected.isEmpty { Button("Deselect all") { selected = [] } }
        else if album.count <= CinemaPhotoSelection.limit {
          Button("Select all") {
            selected = Set((0..<album.count).map { album.assets.object(at: $0).localIdentifier })
          }
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      Button {
        let ids = (0..<album.count).compactMap { index -> String? in
          let id = album.assets.object(at: index).localIdentifier
          return selected.contains(id) ? id : nil
        }
        selection.select(album, assetIDs: ids)
      } label: {
        Text("Use \(selected.count) photos").frame(maxWidth: .infinity).padding(.vertical, 6)
      }
      .buttonStyle(.borderedProminent)
      .foregroundStyle(Palette.onAccent)
      .disabled(selected.isEmpty)
      .accessibilityIdentifier("cinema-use-album")
      .padding().background(.bar)
    }
  }
}

struct CinemaPhotoThumbnail: View {
  let asset: PHAsset?
  @State private var image: UIImage?
  @State private var failed = false

  var body: some View {
    Color.secondary.opacity(0.15)
      .overlay {
        if let image {
          GeometryReader { geometry in
            Image(uiImage: image).resizable().scaledToFill()
              .frame(width: geometry.size.width, height: geometry.size.height).clipped()
          }.accessibilityIdentifier("cinema-photo-thumbnail-loaded")
        } else if failed || asset == nil {
          Image(systemName: "photo").foregroundStyle(.secondary)
        } else { ProgressView() }
      }
      .task(id: asset?.localIdentifier) {
        image = nil; failed = false
        guard let asset else { return }
        do { image = try await CinemaAssetRequest.image(asset, size: CGSize(width: 360, height: 360)) }
        catch is CancellationError { }
        catch { failed = true }
      }
  }
}
#endif
