import SwiftUI
import Combine
@MainActor
final class LeadsViewModel: ObservableObject {
    @Published var leads: [FieldLead] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""
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
        if searchText.isEmpty { return leads }
        let q = searchText.lowercased()
        return leads.filter {
            $0.address.lowercased().contains(q) ||
            ($0.name?.lowercased().contains(q) ?? false) ||
            ($0.phone?.lowercased().contains(q) ?? false)
        }
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
            leads = try await fieldLeadsService.fetchLeads(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func addLead(_ lead: FieldLead) async {
        do {
            let inserted = try await fieldLeadsService.addLead(lead)
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
        do {
            try await fieldLeadsService.deleteLead(lead)
            leads.removeAll { $0.id == lead.id }
            if selectedLead?.id == lead.id { selectedLead = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
