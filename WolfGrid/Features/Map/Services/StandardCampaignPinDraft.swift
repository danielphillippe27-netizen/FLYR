import Foundation

/// Lets the menu accept a choice before local pin persistence completes, without
/// saving a status against a missing row or replaying a dismissed/stale choice.
struct StandardCampaignPinDraft<Action> {
    private(set) var addressID: UUID?
    private(set) var pendingAction: Action?

    mutating func begin(addressID: UUID) {
        self.addressID = addressID
        pendingAction = nil
    }

    mutating func queue(_ action: Action, addressID: UUID) -> Bool {
        guard self.addressID == addressID else { return false }
        pendingAction = action
        return true
    }

    mutating func finish(addressID: UUID) -> Action? {
        guard self.addressID == addressID else { return nil }
        let action = pendingAction
        cancel()
        return action
    }

    mutating func cancel() {
        addressID = nil
        pendingAction = nil
    }
}
