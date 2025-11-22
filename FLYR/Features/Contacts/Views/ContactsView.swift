import SwiftUI

struct ContactsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.largeTitle)
                .foregroundColor(.gray)
            Text("Contacts")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Contact management coming soon")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        ContactsView()
            .navigationTitle("Contacts")
    }
}





