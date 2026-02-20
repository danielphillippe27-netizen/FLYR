import Foundation
import Combine

@MainActor
final class WorkspaceOnboardingViewModel: ObservableObject {
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var workspaceName = ""
    @Published var useCase: OnboardingUseCase = .solo
    @Published var industry: String?
    @Published var brokerage = ""
    @Published var brokerageId: String?
    @Published var brokerageSuggestions: [BrokerageSuggestion] = []
    @Published var isBrokerageSuggestionsOpen = false
    @Published var isBrokerageSearching = false
    @Published var brokerageSearchError: String?
    @Published var inviteEmails: [String] = []
    @Published var referralCode: String?
    @Published var errorMessage: String?

    private var brokerageSearchTask: Task<Void, Never>?

    var showBrokerageField: Bool {
        industry == "Real Estate"
    }

    var hasTypedBrokerage: Bool {
        !brokerage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSubmit: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && !workspaceName.trimmingCharacters(in: .whitespaces).isEmpty
            && industry != nil
    }

    func onIndustryChanged(_ newValue: String?) {
        industry = (newValue?.isEmpty ?? true) ? nil : newValue
        if !showBrokerageField {
            resetBrokerageState()
        }
    }

    func onBrokerageTextChanged(_ newText: String) {
        brokerage = newText
        brokerageId = nil
        brokerageSearchError = nil

        guard showBrokerageField else {
            resetBrokerageState()
            return
        }

        let query = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            cancelBrokerageSearch()
            brokerageSuggestions = []
            isBrokerageSuggestionsOpen = false
            isBrokerageSearching = false
            return
        }

        scheduleBrokerageSearch(for: query)
    }

    func onSelectSuggestion(_ item: BrokerageSuggestion) {
        brokerage = item.name
        brokerageId = item.id
        brokerageSuggestions = []
        isBrokerageSuggestionsOpen = false
        brokerageSearchError = nil
        isBrokerageSearching = false
        cancelBrokerageSearch()
    }

    func onSelectAddNewBrokerage() {
        brokerage = Self.sanitizeBrokerageText(brokerage)
        brokerageId = nil
        isBrokerageSuggestionsOpen = false
    }

    func dismissBrokerageSuggestions() {
        isBrokerageSuggestionsOpen = false
    }

    func cancelBrokerageSearch() {
        brokerageSearchTask?.cancel()
        brokerageSearchTask = nil
    }

    func buildRequest() -> OnboardingCompleteRequest? {
        let sanitizedBrokerage = Self.sanitizeBrokerageText(brokerage)
        let includeBrokerage = showBrokerageField
        let selectedBrokerageId = includeBrokerage ? brokerageId : nil
        let mappedBrokerageText = includeBrokerage ? (sanitizedBrokerage.isEmpty ? nil : sanitizedBrokerage) : nil

        return OnboardingCompleteRequest(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            workspaceName: workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : workspaceName.trimmingCharacters(in: .whitespacesAndNewlines),
            industry: industry,
            referralCode: referralCode,
            useCase: useCase,
            inviteEmails: inviteEmails.isEmpty ? nil : inviteEmails,
            brokerage: mappedBrokerageText,
            brokerageId: selectedBrokerageId
        )
    }

    private func scheduleBrokerageSearch(for query: String) {
        cancelBrokerageSearch()
        brokerageSearchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await self?.searchBrokerages(query: query)
            } catch {
                // ignore cancellation
            }
        }
    }

    private func searchBrokerages(query: String) async {
        isBrokerageSearching = true
        do {
            let results = try await AccessAPI.shared.searchBrokerages(query: query, limit: 15)
            guard !Task.isCancelled else { return }
            brokerageSuggestions = results
            isBrokerageSuggestionsOpen = true
            brokerageSearchError = nil
        } catch {
            guard !Task.isCancelled else { return }
            brokerageSuggestions = []
            isBrokerageSuggestionsOpen = hasTypedBrokerage
            brokerageSearchError = "Couldn't load suggestions"
        }
        isBrokerageSearching = false
    }

    private func resetBrokerageState() {
        brokerage = ""
        brokerageId = nil
        brokerageSuggestions = []
        isBrokerageSuggestionsOpen = false
        isBrokerageSearching = false
        brokerageSearchError = nil
        cancelBrokerageSearch()
    }

    private static func sanitizeBrokerageText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
        return parts.joined(separator: " ")
    }
}
