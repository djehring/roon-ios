import SwiftUI

struct BrowsePlaybackPresentation: ViewModifier {
  @Environment(MockStore.self) private var store

  func body(content: Content) -> some View {
    @Bindable var playback = store.browsePlayback
    content
      .overlay(alignment: .top) {
        if let feedback = playback.feedback {
          HStack(spacing: 14) {
            if feedback.isLoading {
              ProgressView()
                .tint(Palette.accent)
            } else {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.accent)
                .font(.title2)
            }
            VStack(alignment: .leading, spacing: 4) {
              Text(feedback.title)
                .font(.headline)
              Text(feedback.room)
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
            }
          }
          .padding(20)
          .foregroundStyle(Palette.primary)
          .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
          .overlay {
            RoundedRectangle(cornerRadius: 18)
              .stroke(Palette.hairline, lineWidth: 1)
          }
          .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
          .padding()
          .allowsHitTesting(false)
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("browse-playback-feedback")
        }
      }
      .alert("Unable to complete playback action", isPresented: Binding(
        get: { playback.error != nil },
        set: { if !$0 { playback.error = nil } }
      )) {
        Button("OK", role: .cancel) { playback.error = nil }
      } message: {
        Text(playback.error ?? "Please try again.")
      }
  }
}
