import SwiftUI

struct CampaignPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let campaigns: [CampaignListItem]
    @Binding var selectedCampaignId: UUID?
    let onSelect: (UUID?) -> Void
    
    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedCampaignId = nil
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Text("None")
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                        Spacer()
                        if selectedCampaignId == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                
                ForEach(campaigns) { campaign in
                    Button {
                        selectedCampaignId = campaign.id
                        onSelect(campaign.id)
                        dismiss()
                    } label: {
                        HStack {
                            Text(campaign.name)
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedCampaignId == campaign.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Campaign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}


