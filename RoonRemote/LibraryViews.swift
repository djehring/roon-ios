import SwiftUI

struct LibraryRootView: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(
          columns: [GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)],
          spacing: 12
        ) {
          ForEach(store.library) { entry in
            NavigationLink(value: entry) {
              VStack(alignment: .leading, spacing: 12) {
                Image(systemName: entry.symbol)
                  .font(.system(size: 22, weight: .medium))
                  .foregroundStyle(Palette.accent)
                Text(entry.title)
                  .font(.headline)
                  .foregroundStyle(Palette.primary)
              }
              .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
              .padding(16)
              .background(Palette.surface)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .stroke(Palette.hairline, lineWidth: 1)
              }
            }
          }
        }
        .padding(20)
      }
      .background(Palette.background)
      .navigationTitle("Library")
      .navigationDestination(for: LibraryEntry.self) { entry in
        BrowseListView(node: entry.root)
      }
      .toolbar {
        if store.isRecordingAction {
          ToolbarItem(placement: .status) {
            Text("Recording")
              .font(.caption.weight(.semibold))
              .foregroundStyle(Palette.onAccent)
              .padding(.horizontal, 10)
              .padding(.vertical, 4)
              .background(Palette.accent)
              .clipShape(Capsule())
          }
        }
      }
    }
  }
}

struct BrowseListView: View {
  @Environment(MockStore.self) private var store
  let node: BrowseNode
  @State private var prompt = ""
  @State private var jump: String?

  var body: some View {
    ZStack(alignment: .trailing) {
      List {
        ForEach(node.children) { child in
          if child.isPrompt {
            promptRow(child)
          } else if child.children.isEmpty {
            leafRow(child)
          } else {
            NavigationLink(value: child) {
              rowLabel(child)
            }
          }
        }
        .listRowBackground(Palette.surface)
      }
      .scrollContentBackground(.hidden)
      .background(Palette.background)
      .navigationTitle(node.title)
      .navigationDestination(for: BrowseNode.self) { child in
        BrowseListView(node: child)
      }
      if showsIndex {
        indexBar
      }
    }
    .safeAreaInset(edge: .bottom) {
      if store.isRecordingAction {
        recordingBar
      }
    }
  }

  private var showsIndex: Bool {
    ["Albums", "Artists", "Composers", "Playlists", "Radios"].contains(node.title)
  }

  private func rowLabel(_ child: BrowseNode) -> some View {
    HStack(spacing: 12) {
      CoverArt(title: child.title, corner: 6)
        .frame(width: 48, height: 48)
      VStack(alignment: .leading, spacing: 2) {
        Text(child.title)
        if let subtitle = child.subtitle {
          Text(subtitle)
            .font(.footnote)
            .foregroundStyle(Palette.secondary)
        }
      }
    }
  }

  private func leafRow(_ child: BrowseNode) -> some View {
    rowLabel(child)
      .contextMenu {
        ForEach(child.actions, id: \.self) { action in
          Button(action) {}
        }
      }
  }

  private func promptRow(_ child: BrowseNode) -> some View {
    HStack {
      TextField(child.title, text: $prompt)
        .textInputAutocapitalization(.never)
      Button(child.actions.first ?? "Search") {}
        .foregroundStyle(Palette.accent)
    }
  }

  private var indexBar: some View {
    VStack(spacing: 0) {
      ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ#"), id: \.self) { letter in
        Text(String(letter))
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(Palette.tertiary)
      }
    }
    .padding(.trailing, 4)
  }

  private var recordingBar: some View {
    HStack {
      Button("Cancel") { store.isRecordingAction = false }
      Spacer()
      Button("Save") { store.isRecordingAction = false }
        .fontWeight(.semibold)
        .foregroundStyle(Palette.accent)
    }
    .padding()
    .background(Palette.surface)
  }
}
