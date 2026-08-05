import SwiftUI

struct ContactsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.flyrLargeTitle)
                .foregroundColor(.gray)
            Text("Contacts")
                .font(.flyrTitle2)
                .fontWeight(.semibold)
            Text("Contact management coming soon")
                .font(.flyrSubheadline)
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





