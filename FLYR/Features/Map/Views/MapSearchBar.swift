import SwiftUI

/// Floating pill search bar for the Map tab: filter campaigns by name and select to fly to marker.
struct MapSearchBar: View {
    @Binding var searchText: String
    var campaigns: [CampaignListItem]
    var onSelectCampaign: (UUID) -> Void
    var onFocus: (() -> Void)?
    var isLoading: Bool = false

    @FocusState private var isFocused: Bool

    private var filteredCampaigns: [CampaignListItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return campaigns }
        return campaigns.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)

                TextField("Search campaign or farm", text: $searchText)
                    .font(.system(size: 16))
                    .focused($isFocused)
                    .onTapGesture { onFocus?() }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 28)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("Loading campaign…")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.top, 8)
            } else if isFocused && !filteredCampaigns.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredCampaigns.prefix(8)) { campaign in
                            Button {
                                isFocused = false
                                searchText = ""
                                onSelectCampaign(campaign.id)
                            } label: {
                                HStack {
                                    Text(campaign.name)
                                        .font(.system(size: 15))
                                        .foregroundColor(.primary)
                                    if let count = campaign.addressCount {
                                        Text("\(count) addresses")
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 240)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.top, 8)
            }
        }
        .padding(.top, 4)
    }
}

#Preview {
    MapSearchBar(
        searchText: .constant(""),
        campaigns: [
            CampaignListItem(id: UUID(), name: "Summer Flyer", addressCount: 51),
            CampaignListItem(id: UUID(), name: "Fall Campaign", addressCount: 120)
        ],
        onSelectCampaign: { _ in }
    )
}
