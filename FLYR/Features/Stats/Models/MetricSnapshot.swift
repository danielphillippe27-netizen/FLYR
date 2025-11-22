import Foundation

struct MetricSnapshot: Codable {
    var flyers: Int
    var leads: Int
    var conversations: Int
    var distance: Double
    var doorknocks: Int
    
    init(flyers: Int = 0, leads: Int = 0, conversations: Int = 0, distance: Double = 0.0, doorknocks: Int = 0) {
        self.flyers = flyers
        self.leads = leads
        self.conversations = conversations
        self.distance = distance
        self.doorknocks = doorknocks
    }
}

