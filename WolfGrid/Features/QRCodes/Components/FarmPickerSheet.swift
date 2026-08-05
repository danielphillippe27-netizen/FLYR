import SwiftUI

struct FarmPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let farms: [FarmListItem]
    @Binding var selectedFarmId: UUID?
    let onSelect: (UUID?) -> Void
    
    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedFarmId = nil
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Text("None")
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                        Spacer()
                        if selectedFarmId == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                
                ForEach(farms) { farm in
                    Button {
                        selectedFarmId = farm.id
                        onSelect(farm.id)
                        dismiss()
                    } label: {
                        HStack {
                            Text(farm.name)
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedFarmId == farm.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Farm")
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


