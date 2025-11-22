import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "apple")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("waddup")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
