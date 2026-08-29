import SwiftUI

struct TVSearchView: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    @Bindable var store = store
    ScrollView {
      VStack(alignment: .leading, spacing: 32) {
        Text("Search")
          .font(.system(size: 44, weight: .bold))

        HStack(spacing: 16) {
          TextField("Artists, albums, songs…", text: $store.aiQuery)
            .font(.title2)
            .padding(22)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onSubmit { store.runAISearch() }

          Button("Search") { store.runAISearch() }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .foregroundStyle(Palette.onAccent)
            .frame(width: 180, height: 64)
        }

        if store.aiLoading {
          ProgressView()
            .tint(Palette.accent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else if let error = store.aiError {
          Text(error)
            .font(.title3)
            .foregroundStyle(.red.opacity(0.85))
        } else if store.aiResults.isEmpty {
          ContentUnavailableView(
            "Find music",
            systemImage: "magnifyingglass",
            description: Text("Search your library with AI, then play the results.")
          )
          .frame(maxWidth: .infinity)
          .padding(.top, 60)
        } else {
          HStack {
            Text("Results")
              .font(.title.weight(.semibold))
            Spacer()
            Button("Play all") { store.playAIResults() }
              .buttonStyle(.borderedProminent)
              .tint(Palette.accent)
              .foregroundStyle(Palette.onAccent)
              .frame(width: 200, height: 52)
          }

          LazyVStack(spacing: 12) {
            ForEach(store.aiResults) { item in
              resultRow(item)
            }
          }
        }
      }
      .padding(48)
      .frame(maxWidth: 1100, alignment: .leading)
    }
    .background(Palette.background)
  }

  private func resultRow(_ item: SuggestedTrack) -> some View {
    HStack(spacing: 20) {
      CoverArt(title: item.album, corner: 8)
        .frame(width: 64, height: 64)
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.title3.weight(.semibold))
        Text("\(item.artist)  ·  \(item.album)")
          .font(.body)
          .foregroundStyle(Palette.secondary)
        if let error = item.error {
          Text(error)
            .font(.callout)
            .foregroundStyle(.red.opacity(0.8))
        } else if item.corrected {
          Text("Auto-corrected")
            .font(.caption)
            .foregroundStyle(Palette.accent)
        }
      }
      Spacer()
      if item.error == nil {
        Image(systemName: "play.circle.fill")
          .font(.title)
          .foregroundStyle(Palette.accent)
      }
    }
    .padding(20)
    .background(Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}
