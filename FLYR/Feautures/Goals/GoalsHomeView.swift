import SwiftUI

struct GoalsHomeView: View {
  @State private var showCreate = false
  var body: some View {
    VStack {
      Spacer()
      Image(systemName: "target")
        .font(.system(size: 56)).foregroundStyle(.secondary)
      Text("No Goals Yet").font(.title3.weight(.semibold)).padding(.top, 8)
      Text("Set activity or outcome goals to stay on track.")
        .font(.footnote).foregroundStyle(.secondary).padding(.top, 2)
      Button("Create Goal") { showCreate = true }
        .buttonStyle(.borderedProminent).padding(.top, 16)
      Spacer()
    }
    .padding(.horizontal, 20)
    .navigationDestination(isPresented: $showCreate) {
      GoalsCreateView()
    }
  }
}







