import Foundation

extension Notification.Name {
    static let wolfyHomeStatusDidChange = Notification.Name("wolfgrid.wolfy.homeStatusDidChange")
}

@MainActor enum WolfyHomeStatusFeedback {
    static func didUpdate(_ status: AddressStatus) {
        WolfyFeedback.perform()
        NotificationCenter.default.post(
            name: .wolfyHomeStatusDidChange,
            object: nil,
            userInfo: ["status": status.rawValue]
        )
    }
}
