import Foundation
import CoreLocation

// MARK: - QR Code Types

/// QR Code scan record from database
public struct QRCodeScan: Identifiable, Codable {
    public let id: UUID
    public let addressId: UUID
    public let scannedAt: Date
    public let deviceInfo: String?
    public let userAgent: String?
    public let ipAddress: String?
    public let referrer: String?
    
    public init(
        id: UUID,
        addressId: UUID,
        scannedAt: Date,
        deviceInfo: String? = nil,
        userAgent: String? = nil,
        ipAddress: String? = nil,
        referrer: String? = nil
    ) {
        self.id = id
        self.addressId = addressId
        self.scannedAt = scannedAt
        self.deviceInfo = deviceInfo
        self.userAgent = userAgent
        self.ipAddress = ipAddress
        self.referrer = referrer
    }
}

/// Analytics summary data
public struct QRCodeAnalyticsSummary {
    public let totalScans: Int
    public let addressCount: Int
    public let recentScans: [QRCodeScan]
    public let scansByDate: [Date: Int]
    
    public init(
        totalScans: Int,
        addressCount: Int,
        recentScans: [QRCodeScan] = [],
        scansByDate: [Date: Int] = [:]
    ) {
        self.totalScans = totalScans
        self.addressCount = addressCount
        self.recentScans = recentScans
        self.scansByDate = scansByDate
    }
}

/// Campaign list item (lightweight)
public struct CampaignListItem: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let addressCount: Int?
    
    public init(id: UUID, name: String, addressCount: Int? = nil) {
        self.id = id
        self.name = name
        self.addressCount = addressCount
    }
    
    // Convenience initializer from CampaignDBRow
    init(from dbRow: CampaignDBRow, addressCount: Int? = nil) {
        self.id = dbRow.id
        self.name = dbRow.title
        self.addressCount = addressCount
    }
}

/// Address row for selection
public struct AddressRow: Identifiable {
    public let id: UUID
    public let formatted: String
    public let coordinate: CLLocationCoordinate2D?
    
    public init(id: UUID, formatted: String, coordinate: CLLocationCoordinate2D? = nil) {
        self.id = id
        self.formatted = formatted
        self.coordinate = coordinate
    }
}

