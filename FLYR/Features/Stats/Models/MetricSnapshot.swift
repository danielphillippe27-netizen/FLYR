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
}
