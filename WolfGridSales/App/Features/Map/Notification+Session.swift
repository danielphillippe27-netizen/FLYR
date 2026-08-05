import Foundation

extension Notification.Name {
    static let sessionEnded = Notification.Name("sessionEnded")
    /// Posted after a lead is saved from the session lead-capture sheet so the Leads tab can refresh.
    static let leadSavedFromSession = Notification.Name("leadSavedFromSession")
    /// Posted when a building is auto-completed (proximity/dwell) so the map can turn it green immediately.
    static let sessionBuildingAutoCompleted = Notification.Name("sessionBuildingAutoCompleted")
}

extension Notification {
    /// Use with `sessionBuildingAutoCompleted`; value is the building gersId (String).
    static let sessionBuildingAutoCompletedBuildingIdKey = "buildingId"
}


