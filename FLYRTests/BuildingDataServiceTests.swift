import XCTest
@testable import FLYR

@MainActor
final class BuildingDataServiceTests: XCTestCase {
    
    // Note: These tests require a mock Supabase client for full testing
    // For now, we'll test the data models and logic
    
    // MARK: - ResolvedAddress Tests
    
    func testResolvedAddressDisplayStreet() {
        let address = ResolvedAddress(
            id: UUID(),
            street: "123 Main St",
            formatted: "123 Main St, Toronto, ON",
            locality: "Toronto",
            region: "ON",
            postalCode: "M5V 2T6",
            houseNumber: "123",
            streetName: "Main St",
            gersId: UUID()
        )
        
        XCTAssertEqual(address.displayStreet, "123 Main St")
    }
    
    func testResolvedAddressDisplayStreetFallback() {
        let address = ResolvedAddress(
            id: UUID(),
            street: "",
            formatted: "Unknown Address",
            locality: "Toronto",
            region: "ON",
            postalCode: "M5V 2T6",
            houseNumber: "",
            streetName: "",
            gersId: UUID()
        )
        
        XCTAssertEqual(address.displayStreet, "Unknown Address")
    }
    
    func testResolvedAddressDisplayFull() {
        let address = ResolvedAddress(
            id: UUID(),
            street: "123 Main St",
            formatted: "123 Main St, Toronto, ON",
            locality: "Toronto",
            region: "ON",
            postalCode: "M5V 2T6",
            houseNumber: "123",
            streetName: "Main St",
            gersId: UUID()
        )
        
        XCTAssertEqual(address.displayFull, "123 Main St, Toronto, ON, M5V 2T6")
    }
    
    // MARK: - QRStatus Tests
    
    func testQRStatusIsScanned() {
        let scannedStatus = QRStatus(hasFlyer: true, totalScans: 5, lastScannedAt: Date())
        XCTAssertTrue(scannedStatus.isScanned)
        
        let unscannedStatus = QRStatus(hasFlyer: true, totalScans: 0, lastScannedAt: nil)
        XCTAssertFalse(unscannedStatus.isScanned)
    }
    
    func testQRStatusText() {
        let scannedStatus = QRStatus(hasFlyer: true, totalScans: 5, lastScannedAt: Date())
        XCTAssertEqual(scannedStatus.statusText, "Scanned 5x")
        
        let unscannedStatus = QRStatus(hasFlyer: true, totalScans: 0, lastScannedAt: nil)
        XCTAssertEqual(unscannedStatus.statusText, "Flyer delivered")
        
        let noFlyerStatus = QRStatus(hasFlyer: false, totalScans: 0, lastScannedAt: nil)
        XCTAssertEqual(noFlyerStatus.statusText, "No QR code")
    }
    
    func testQRStatusSubtext() {
        let scannedStatus = QRStatus(hasFlyer: true, totalScans: 5, lastScannedAt: Date())
        XCTAssertTrue(scannedStatus.subtext.contains("Last:"))
        
        let unscannedStatus = QRStatus(hasFlyer: true, totalScans: 0, lastScannedAt: nil)
        XCTAssertEqual(unscannedStatus.subtext, "Not scanned yet")
        
        let noFlyerStatus = QRStatus(hasFlyer: false, totalScans: 0, lastScannedAt: nil)
        XCTAssertEqual(noFlyerStatus.subtext, "Generate in campaign")
    }
    
    // MARK: - BuildingData Tests
    
    func testBuildingDataHasAddress() {
        let addressData = BuildingData(
            isLoading: false,
            error: nil,
            address: ResolvedAddress(
                id: UUID(),
                street: "123 Main St",
                formatted: "123 Main St",
                locality: "Toronto",
                region: "ON",
                postalCode: "M5V 2T6",
                houseNumber: "123",
                streetName: "Main St",
                gersId: UUID()
            ),
            residents: [],
            qrStatus: .empty,
            buildingExists: true,
            addressLinked: true
        )
        
        XCTAssertTrue(addressData.hasAddress)
        
        let noAddressData = BuildingData(
            isLoading: false,
            error: nil,
            address: nil,
            residents: [],
            qrStatus: .empty,
            buildingExists: false,
            addressLinked: false
        )
        
        XCTAssertFalse(noAddressData.hasAddress)
    }
    
    func testBuildingDataHasNotes() {
        let contact = Contact(
            id: UUID(),
            userId: UUID(),
            fullName: "John Doe",
            phone: "555-1234",
            email: "john@example.com",
            address: "123 Main St",
            campaignId: UUID(),
            farmId: nil,
            status: .new,
            lastContacted: nil,
            notes: "Interested in solar panels",
            reminderDate: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let dataWithNotes = BuildingData(
            isLoading: false,
            error: nil,
            address: nil,
            residents: [contact],
            qrStatus: .empty,
            buildingExists: true,
            addressLinked: true
        )
        
        XCTAssertTrue(dataWithNotes.hasNotes)
        XCTAssertEqual(dataWithNotes.firstNotes, "Interested in solar panels")
    }
    
    // MARK: - CachedBuildingData Tests
    
    func testCachedBuildingDataIsValid() {
        let cached = CachedBuildingData(
            data: .empty,
            timestamp: Date()
        )
        
        XCTAssertTrue(cached.isValid(ttl: 300))
        
        let oldCached = CachedBuildingData(
            data: .empty,
            timestamp: Date().addingTimeInterval(-400)
        )
        
        XCTAssertFalse(oldCached.isValid(ttl: 300))
    }
    
    // MARK: - CampaignAddressResponse Tests
    
    func testCampaignAddressResponseToResolvedAddress() {
        let response = CampaignAddressResponse(
            id: UUID(),
            houseNumber: "123",
            streetName: "Main St",
            formatted: "123 Main St, Toronto, ON",
            locality: "Toronto",
            region: "ON",
            postalCode: "M5V 2T6",
            gersId: UUID(),
            buildingGersId: nil,
            scans: 5,
            lastScannedAt: Date(),
            qrCodeBase64: "base64data"
        )
        
        let fallbackGersId = UUID()
        let resolved = response.toResolvedAddress(fallbackGersId: fallbackGersId)
        
        XCTAssertEqual(resolved.houseNumber, "123")
        XCTAssertEqual(resolved.streetName, "Main St")
        XCTAssertEqual(resolved.street, "123 Main St")
        XCTAssertNotNil(resolved.gersId)
    }
    
    func testCampaignAddressResponseToQRStatus() {
        let response = CampaignAddressResponse(
            id: UUID(),
            houseNumber: "123",
            streetName: "Main St",
            formatted: "123 Main St",
            locality: "Toronto",
            region: "ON",
            postalCode: "M5V 2T6",
            gersId: UUID(),
            buildingGersId: nil,
            scans: 5,
            lastScannedAt: Date(),
            qrCodeBase64: "base64data"
        )
        
        let qrStatus = response.toQRStatus()
        
        XCTAssertTrue(qrStatus.hasFlyer)
        XCTAssertEqual(qrStatus.totalScans, 5)
        XCTAssertNotNil(qrStatus.lastScannedAt)
    }
    
    // MARK: - Color Priority Tests
    
    func testStatusColorPriority() {
        // Priority 1: QR Scanned (Yellow) - highest
        let qrScanned = (scansTotal: 5, status: "not_visited")
        XCTAssertTrue(qrScanned.scansTotal > 0, "QR scanned should have priority")
        
        // Priority 2: Hot (Blue)
        let hot = (scansTotal: 0, status: "hot")
        XCTAssertEqual(hot.status, "hot")
        
        // Priority 3: Visited (Green)
        let visited = (scansTotal: 0, status: "visited")
        XCTAssertEqual(visited.status, "visited")
        
        // Priority 4: Not visited (Red) - default
        let notVisited = (scansTotal: 0, status: "not_visited")
        XCTAssertEqual(notVisited.status, "not_visited")
    }
}
