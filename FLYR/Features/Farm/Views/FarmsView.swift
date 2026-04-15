import SwiftUI

struct FarmsView: View {
    @State private var farmFilter: FarmFilter = .active
    @State private var showFarmInfo = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FarmListView(
                    externalFilter: $farmFilter,
                    onCreateFarmTapped: showFarmInfoMessage
                )
            }
            .navigationTitle("Farm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(FarmFilter.allCases) { filterOption in
                            Button(filterOption.rawValue) {
                                farmFilter = filterOption
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(farmFilter.rawValue)
                                .font(.system(size: 15, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.primary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFarmInfoMessage()
                    } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .alert("Farm Is Created On Web", isPresented: $showFarmInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add farms on web at flyr.software. The farm limit is 5000 homes.")
        }
    }

    private func showFarmInfoMessage() {
        HapticManager.light()
        showFarmInfo = true
    }
}

#Preview {
    FarmsView()
}
