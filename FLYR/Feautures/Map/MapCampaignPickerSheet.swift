import SwiftUI

struct MapCampaignPickerSheet: View {
    @Binding var selectedCampaignId: UUID?
    @Binding var selectedFarmId: UUID?
    @ObservedObject var viewModel: MapCampaignPickerViewModel
    let onDismiss: () -> Void
    
    @State private var selectionType: SelectionType = .campaign
    
    enum SelectionType {
        case campaign
        case farm
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Type Picker
                Picker("Type", selection: $selectionType) {
                    Text("Campaigns").tag(SelectionType.campaign)
                    Text("Farms").tag(SelectionType.farm)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // List
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if selectionType == .campaign {
                                ForEach(viewModel.campaigns) { campaign in
                                    CampaignFarmRow(
                                        title: campaign.name,
                                        subtitle: campaign.addressCount.map { "\($0) addresses" },
                                        isSelected: selectedCampaignId == campaign.id
                                    ) {
                                        selectedCampaignId = campaign.id
                                        selectedFarmId = nil
                                    }
                                }
                            } else {
                                ForEach(viewModel.farms) { farm in
                                    CampaignFarmRow(
                                        title: farm.name,
                                        subtitle: farm.areaLabel ?? farm.addressCount.map { "\($0) addresses" },
                                        isSelected: selectedFarmId == farm.id
                                    ) {
                                        selectedFarmId = farm.id
                                        selectedCampaignId = nil
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Select Campaign/Farm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if selectedCampaignId != nil || selectedFarmId != nil {
                        Button("Clear") {
                            selectedCampaignId = nil
                            selectedFarmId = nil
                            onDismiss()
                        }
                    }
                }
            }
        }
    }
}

struct CampaignFarmRow: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.flyrHeadline)
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.flyrCaption)
                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(isSelected ? Color.red : Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}



