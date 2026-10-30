import SwiftUI

enum CampaignMapSelectionFilter: String, CaseIterable, Identifiable {
    case all = "All items", address = "Addresses", building = "Buildings", parcel = "Parcels"
    var id: String { rawValue }
}

struct CampaignMapEditToolbar: View {
    let title: String
    let message: String
    let status: String
    let selectionCount: Int
    let canUndo: Bool
    let canUnlink: Bool
    let moving: Bool
    let adding: Bool
    let canContinueAdding: Bool
    let showsLinkedToggle: Bool
    let needsSyncAttention: Bool
    @Binding var filter: CampaignMapSelectionFilter
    @Binding var moveLinked: Bool
    let select: () -> Void
    let move: () -> Void
    let add: () -> Void
    let continueAdding: () -> Void
    let unlink: () -> Void
    let delete: () -> Void
    let undo: () -> Void
    let clear: () -> Void
    let retry: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: "hammer.fill").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Done", action: done).font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
            Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if showsLinkedToggle {
                Toggle("Move linked items", isOn: $moveLinked).font(.subheadline).tint(.red)
            }
            HStack(spacing: 6) {
                Menu {
                    Picker("Select", selection: $filter) {
                        ForEach(CampaignMapSelectionFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if selectionCount > 0 { Button("Clear selection", action: clear) }
                } label: { Label("Select", systemImage: "checkmark.circle") }
                .simultaneousGesture(TapGesture().onEnded { _ in select() })
                .frame(maxWidth: .infinity, minHeight: 44)
                if selectionCount > 1 {
                    tool("Remove", icon: "trash", action: delete)
                } else {
                    tool("Move", icon: "arrow.up.and.down.and.arrow.left.and.right", active: moving, action: move)
                        .disabled(selectionCount != 1)
                }
                tool("Add", icon: "plus", active: adding, action: add)
                tool("Undo", icon: "arrow.uturn.backward", action: undo).disabled(!canUndo)
                Menu {
                    if canUnlink { Button("Unlink address from building", systemImage: "link.badge.minus", action: unlink) }
                    Button("Remove selected items", systemImage: "trash", role: .destructive, action: delete)
                        .disabled(selectionCount == 0)
                } label: { Label("More", systemImage: "ellipsis") }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            HStack {
                Text(status).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if adding { Button("Continue", action: continueAdding).disabled(!canContinueAdding).font(.caption.weight(.semibold)) }
                if needsSyncAttention { Button("Review / Retry", action: retry).font(.caption.weight(.semibold)) }
            }
        }
        .padding(14)
        .foregroundStyle(.primary)
        .tint(.red)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("campaign-map-edit-toolbar")
    }
    private func tool(_ title: String, icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) { Image(systemName: icon); Text(title) }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(active ? Color.red.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }
    }
}

struct CampaignMapLinkChoiceSheet: View {
    let proposal: CampaignMapEditProposal
    let save: ([CampaignMapLinkChoice]) -> Void
    let cancel: () -> Void
    @State private var selected: Set<String> = []
    private var allowsMultiple: Bool { Set(proposal.choices.map(\.buildingID)).count == 1 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(proposal.message)
                    ForEach(proposal.choices) { choice in
                        Button {
                            if selected.contains(choice.id) { selected.remove(choice.id) }
                            else if allowsMultiple { selected.insert(choice.id) }
                            else { selected = [choice.id] }
                        } label: {
                            HStack {
                                Text(choice.title).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selected.contains(choice.id) ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    }
                }
                Button(selected.isEmpty ? "Save without new building links" : "Save and link") {
                    save(proposal.choices.filter { selected.contains($0.id) })
                }
                .fontWeight(.semibold)
            }
            .navigationTitle("Link map items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) } }
        }
        .tint(.red)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }
}
