import SwiftUI

public struct FormRowMenuPicker<T: Hashable & Identifiable & CustomStringConvertible>: View {
  let title: String
  let options: [T]
  @Binding var selection: T

  public init(_ title: String, options: [T], selection: Binding<T>) {
    self.title = title
    self.options = options
    self._selection = selection
  }

  public var body: some View {
    HStack {
      Text(title)
      Spacer()
      Picker("", selection: $selection) {
        ForEach(options) { opt in
          Text(opt.description).tag(opt)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .frame(maxWidth: 200, alignment: .trailing)
    }
    .contentShape(Rectangle())
    .padding(12)
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}







