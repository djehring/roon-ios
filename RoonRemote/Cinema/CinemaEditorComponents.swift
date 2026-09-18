import SwiftUI

struct CinemaOption<Value: Hashable>: Identifiable {
  let value: Value
  let title: String
  var id: Value { value }
}

struct CinemaOptionRow<Value: Hashable>: View {
  let title: String
  @Binding var selection: Value
  let choices: [CinemaOption<Value>]

  var body: some View {
    #if os(tvOS)
    NavigationLink {
      CinemaOptionChoices(title: title, selection: $selection, choices: choices)
    } label: {
      CinemaSettingLabel(title: title, value: choices.first { $0.value == selection }?.title ?? "")
    }.cinemaPlainButton()
    #else
    Picker(selection: $selection) {
      ForEach(choices) { Text($0.title).tag($0.value) }
    } label: { Text(title).foregroundStyle(Palette.primary) }
      .pickerStyle(.menu)
      .font(.body)
      .frame(minHeight: 48)
    #endif
  }
}

private struct CinemaOptionChoices<Value: Hashable>: View {
  let title: String
  @Binding var selection: Value
  let choices: [CinemaOption<Value>]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    List(choices) { choice in
      Button {
        selection = choice.value
        dismiss()
      } label: {
        HStack {
          Text(choice.title)
          Spacer()
          if choice.value == selection { Image(systemName: "checkmark") }
        }
      }
    }.navigationTitle(title)
  }
}

struct CinemaSettingLabel: View {
  let title: String
  var value = ""
  var detail: String?
  @Environment(\.isFocused) private var focused

  var body: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
        if let detail { Text(detail).font(.subheadline).foregroundStyle(focused ? .black.opacity(0.65) : Palette.secondary) }
      }
      Spacer(minLength: 8)
      if !value.isEmpty { Text(value).foregroundStyle(focused ? .black : Palette.accent).multilineTextAlignment(.trailing) }
      Image(systemName: "chevron.right").font(.caption)
    }
    .font(CinemaLayout.isTV ? .system(size: 24) : .body)
    .foregroundStyle(focused ? .black : Palette.primary)
    .frame(minHeight: CinemaLayout.controlHeight)
    .padding(.horizontal, CinemaLayout.isTV ? 16 : 0)
    .background(focused ? Color.white : .clear)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .contentShape(Rectangle())
  }
}

struct CinemaTopicRow: View {
  let title: String
  @Binding var selected: Bool

  var body: some View {
    #if os(tvOS)
    Button { selected.toggle() } label: {
      CinemaTopicLabel(title: title, selected: selected)
    }
    .cinemaPlainButton()
    .accessibilityValue(selected ? "On" : "Off")
    #else
    Toggle(title, isOn: $selected).frame(minHeight: 48).tint(Palette.accent)
    #endif
  }
}

#if os(tvOS)
private struct CinemaTopicLabel: View {
  let title: String
  let selected: Bool
  @Environment(\.isFocused) private var focused

  var body: some View {
      HStack {
        Text(title)
        Spacer()
        Text(selected ? "On" : "Off")
        Image(systemName: selected ? "checkmark" : "minus").frame(width: 24)
      }
      .font(.system(size: 24))
      .padding(.horizontal, 16)
      .frame(minHeight: 64)
      .foregroundStyle(focused ? .black : Palette.primary)
      .background(focused ? .white : .clear)
      .clipShape(RoundedRectangle(cornerRadius: 10))
  }
}
#endif
