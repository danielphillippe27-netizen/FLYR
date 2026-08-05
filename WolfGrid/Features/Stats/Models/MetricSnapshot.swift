import Foundation

struct MetricSnapshot: Codable {
    var leads: Int
    var conversations: Int
    var distance: Double
    var doorknocks: Int
    
    init(leads: Int = 0, conversations: Int = 0, distance: Double = 0.0, doorknocks: Int = 0) {
        self.leads = leads
        self.conversations = conversations
        self.distance = distance
        self.doorknocks = doorknocks
    }

    func value(for metric: String) -> Double {
        switch metric {
        case "leads":
            return Double(leads)
        case "conversations":
            return Double(conversations)
        case "distance":
            return distance
        default:
            return Double(doorknocks)
        }
    }
}
