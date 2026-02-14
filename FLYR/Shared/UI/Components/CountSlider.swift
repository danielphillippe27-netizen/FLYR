import SwiftUI

public struct CountSlider: View {
  private let steps: [Int] = [25, 50, 100, 250, 500, 750, 1000]
  @Binding var value: Int

  public init(value: Binding<Int>) { self._value = value }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("How many homes?").font(.flyrHeadline)
        Spacer()
        Text("\(value)").foregroundStyle(.secondary)
      }
      Slider(value: Binding(
        get: {
          Double(steps.firstIndex(of: value) ?? 2)
        },
        set: { idx in
          let i = Int(round(idx))
          value = steps[min(max(i, 0), steps.count-1)]
        }
      ), in: 0...Double(steps.count-1), step: 1)
    }
  }
}







