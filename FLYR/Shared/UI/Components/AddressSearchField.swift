import SwiftUI
import CoreLocation

struct AddressSearchField: View {
  @ObservedObject var auto: UseAddressAutocomplete
  var onPick: (AddressSuggestion) -> Void
  @FocusState private var focused: Bool

  var body: some View {
    VStack(spacing: 8) {
      HStack {
        TextField("Enter a starting address", text: $auto.query)
          .textInputAutocapitalization(.never)
          .disableAutocorrection(true)
          .focused($focused)
          .onChange(of: auto.query) { _ in auto.bind() }
          .onSubmit { focused = false }     // keyboard return collapses
      }
      .padding(12)
      .background(Color(.secondarySystemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .onChange(of: focused) { isFocused in
        if !isFocused { auto.clear() }      // blur → hide list
      }

      if auto.isLoading {
        ProgressView().padding(.vertical, 6)
      }

      if !auto.suggestions.isEmpty {
        VStack(spacing: 0) {
          ForEach(auto.suggestions) { s in
            Button {
              focused = false               // collapse immediately
              auto.pick(s)
              onPick(s)
            } label: {
              HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                  .font(.system(size: 18))
                  .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                  Text(s.title)
                    .font(.flyrSubheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                  if let sub = s.subtitle {
                    Text(sub)
                      .font(.flyrFootnote)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                }
                Spacer()
              }
              .contentShape(Rectangle())
              .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if s.id != auto.suggestions.last?.id {
              Divider().padding(.leading, 42) // inset under text, not icon
            }
          }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
  }
}
