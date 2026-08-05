import SwiftUI
import Combine

enum LeadInboxFilter: String, CaseIterable, Identifiable {
    case all
    case campaigns

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .campaigns: return "Campaigns"
        }
    }
}

@MainActor
final class LeadsViewModel: ObservableObject {
    @Published var leads: [FieldLead] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var selectedFilter: LeadInboxFilter = .all
    @Published var selectedCampaignId: UUID?
    @Published var selectedLead: FieldLead?
    
    private let fieldLeadsService = FieldLeadsService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }
    
    var filteredLeads: [FieldLead] {
        let scoped = leads.filter { lead in
            switch selectedFilter {
            case .all:
                return true
            case .campaigns:
                if let selectedCampaignId {
                    return lead.campaignId == selectedCampaignId
                }
                return lead.campaignId != nil
            }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return scoped }

        return scoped.filter {
            $0.address.lowercased().contains(q) ||
            ($0.name?.lowercased().contains(q) ?? false) ||
            ($0.phone?.lowercased().contains(q) ?? false) ||
            ($0.email?.lowercased().contains(q) ?? false) ||
            ($0.notes?.lowercased().contains(q) ?? false)
        }
    }

    func selectFilter(_ filter: LeadInboxFilter) {
        selectedFilter = filter
        if filter != .campaigns {
            selectedCampaignId = nil
        }
    }

    func selectCampaign(_ campaignId: UUID?) {
        selectedFilter = .campaigns
        selectedCampaignId = campaignId
    }
    
    func loadLeads() async {
        guard let userId = AuthManager.shared.user?.id else {
            errorMessage = "Not signed in"
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            leads = try await fieldLeadsService.fetchLeads(userId: userId, workspaceId: WorkspaceContext.shared.workspaceId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func addLead(_ lead: FieldLead) async {
        do {
            let inserted = try await fieldLeadsService.addLead(lead, workspaceId: WorkspaceContext.shared.workspaceId)
            leads.insert(inserted, at: 0)
            selectedLead = inserted
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func updateLead(_ lead: FieldLead) async {
        do {
            let updated = try await fieldLeadsService.updateLead(lead)
            if let i = leads.firstIndex(where: { $0.id == lead.id }) {
                leads[i] = updated
            }
            selectedLead = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func deleteLead(_ lead: FieldLead) async {
        await deleteLeads([lead])
    }

    func deleteLeads(_ leadsToDelete: [FieldLead]) async {
        let idsToDelete = Set(leadsToDelete.map(\.id))
        guard !idsToDelete.isEmpty else { return }

        do {
            try await fieldLeadsService.deleteLeads(leadsToDelete)
            leads.removeAll { idsToDelete.contains($0.id) }
            if let selectedLead, idsToDelete.contains(selectedLead.id) {
                self.selectedLead = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
