import SwiftUI

struct TVSearchView: View {
  @Environment(MockStore.self) private var store

  var body: some View {
    @Bindable var store = store
    ScrollView {
      VStack(alignment: .leading, spacing: 56) {
        Text("Search")
          .font(.system(size: 44, weight: .bold))

        HStack(spacing: 40) {
          TextField("Artists, albums, songs…", text: $store.aiQuery)
            .font(.title2)
            .onSubmit { store.runAISearch() }

          TVPrimaryButton(title: "Search", minHeight: 64) {
            store.runAISearch()
          }
          .frame(width: 240)
          .disabled(store.aiQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()

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
          HStack(alignment: .center, spacing: 36) {
            Text("Results")
              .font(.title.weight(.semibold))
            Spacer(minLength: 40)
            TVPrimaryButton(title: "Play all", minHeight: 56) {
              store.playAIResults()
            }
            .frame(width: 220)
          }
          .frame(maxWidth: .infinity)

          LazyVStack(spacing: 12) {
            ForEach(store.aiResults) { item in
              Button {
                store.playAIResults([item])
              } label: {
                TVSearchResultRow(item: item)
              }
              .tvUnplated()
              .disabled(item.error != nil)
            }
          }
          .focusSection()
        }
      }
      .padding(48)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Palette.background)
  }
}

private struct TVSearchResultRow: View {
  let item: SuggestedTrack
  @Environment(\.isFocused) private var isFocused

  var body: some View {
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
          .foregroundStyle(isFocused ? Palette.onAccent : Palette.accent)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(isFocused ? Palette.onAccent : Palette.primary)
    .background(isFocused ? Color.white : Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}
