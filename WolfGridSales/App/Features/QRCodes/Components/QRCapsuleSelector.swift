import SwiftUI

/// Horizontal scrolling capsule selector for campaigns or farms
struct QRCapsuleSelector<T: Identifiable & Hashable>: View {
    let items: [T]
    let selectedId: T.ID?
    let titleKeyPath: KeyPath<T, String>
    let subtitleKeyPath: KeyPath<T, String?>?
    let onSelect: (T.ID) -> Void
    
    init(
        items: [T],
        selectedId: T.ID?,
        titleKeyPath: KeyPath<T, String>,
        subtitleKeyPath: KeyPath<T, String?>? = nil,
        onSelect: @escaping (T.ID) -> Void
    ) {
        self.items = items
        self.selectedId = selectedId
        self.titleKeyPath = titleKeyPath
        self.subtitleKeyPath = subtitleKeyPath
        self.onSelect = onSelect
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(items) { item in
                    CapsuleButton(
                        item: item,
                        selectedId: selectedId,
                        titleKeyPath: titleKeyPath,
                        subtitleKeyPath: subtitleKeyPath,
                        onSelect: onSelect
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 14)
    }
}

private struct CapsuleButton<T: Identifiable & Hashable>: View {
    let item: T
    let selectedId: T.ID?
    let titleKeyPath: KeyPath<T, String>
    let subtitleKeyPath: KeyPath<T, String?>?
    let onSelect: (T.ID) -> Void
    
    var isSelected: Bool {
        selectedId == item.id
    }
    
    var body: some View {
        Button {
            onSelect(item.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item[keyPath: titleKeyPath])
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                
                if let subtitleKeyPath = subtitleKeyPath,
                   let subtitle = item[keyPath: subtitleKeyPath] {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .frame(minWidth: 120)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Group {
                    if isSelected {
                        Color.red
                    } else {
                        Color(.systemGray6)
                            .opacity(0.6)
                    }
                }
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Convenience Views

struct CampaignCapsuleSelector: View {
    let items: [CampaignListItem]
    let selectedId: UUID?
    let onSelect: (UUID) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(items) { item in
                    CampaignCapsuleButton(
                        item: item,
                        selectedId: selectedId,
                        onSelect: onSelect
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 14)
    }
}

struct FarmCapsuleSelector: View {
    let items: [FarmListItem]
    let selectedId: UUID?
    let onSelect: (UUID) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(items) { item in
                    FarmCapsuleButton(
                        item: item,
                        selectedId: selectedId,
                        onSelect: onSelect
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 14)
    }
}

// MARK: - Specific Capsule Buttons

private struct CampaignCapsuleButton: View {
    let item: CampaignListItem
    let selectedId: UUID?
    let onSelect: (UUID) -> Void
    
    var isSelected: Bool {
        selectedId == item.id
    }
    
    var body: some View {
        Button {
            onSelect(item.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                
                if let addressCount = item.addressCount {
                    Text("\(addressCount) addresses")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .frame(minWidth: 120)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Group {
                    if isSelected {
                        Color.red
                    } else {
                        Color(.systemGray6)
                            .opacity(0.6)
                    }
                }
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct FarmCapsuleButton: View {
    let item: FarmListItem
    let selectedId: UUID?
    let onSelect: (UUID) -> Void
    
    var isSelected: Bool {
        selectedId == item.id
    }
    
    var body: some View {
        Button {
            onSelect(item.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                
                if let areaLabel = item.areaLabel {
                    Text(areaLabel)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .frame(minWidth: 120)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Group {
                    if isSelected {
                        Color.red
                    } else {
                        Color(.systemGray6)
                            .opacity(0.6)
                    }
                }
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}


