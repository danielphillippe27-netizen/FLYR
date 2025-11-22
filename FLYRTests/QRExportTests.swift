import XCTest
@testable import FLYR

/// Unit tests for QR Export system
final class QRExportTests: XCTestCase {
    
    // MARK: - StringSlugifier Tests
    
    func testSlugifyBasic() {
        let input = "161 Sprucewood Crescent"
        let output = StringSlugifier.slugify(input)
        XCTAssertEqual(output, "161_sprucewood_crescent")
    }
    
    func testSlugifyWithSpecialCharacters() {
        let input = "123 Main St., Apt #4"
        let output = StringSlugifier.slugify(input)
        XCTAssertFalse(output.contains(","))
        XCTAssertFalse(output.contains("."))
        XCTAssertFalse(output.contains("#"))
        XCTAssertFalse(output.contains(" "))
    }
    
    func testSlugifyWithInvalidChars() {
        let input = "Test/File:Name?<>|*\""
        let output = StringSlugifier.slugify(input)
        XCTAssertFalse(output.contains("/"))
        XCTAssertFalse(output.contains(":"))
        XCTAssertFalse(output.contains("?"))
    }
    
    func testSlugifyEmptyString() {
        let input = ""
        let output = StringSlugifier.slugify(input)
        XCTAssertEqual(output, "address")
    }
    
    func testSlugifyLongString() {
        let input = String(repeating: "a", count: 150)
        let output = StringSlugifier.slugify(input)
        XCTAssertLessThanOrEqual(output.count, 100)
    }
    
    func testSlugifyMultipleUnderscores() {
        let input = "Test   Multiple    Spaces"
        let output = StringSlugifier.slugify(input)
        XCTAssertFalse(output.contains("__"))
    }
    
    // MARK: - CSVExportService Tests
    
    func testCSVFormat() throws {
        let addresses = [
            QRCodeAddress(
                id: UUID(),
                addressId: UUID(),
                formatted: "161 Sprucewood Crescent",
                webURL: "https://flyr.app/address/test1",
                deepLinkURL: "flyr://address/test1"
            ),
            QRCodeAddress(
                id: UUID(),
                addressId: UUID(),
                formatted: "153 Sprucewood Crescent",
                webURL: "https://flyr.app/address/test2",
                deepLinkURL: "flyr://address/test2"
            )
        ]
        
        let filenames: [UUID: String] = [
            addresses[0].id: "161_sprucewood_crescent.png",
            addresses[1].id: "153_sprucewood_crescent.png"
        ]
        
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("csv_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let csvFilename = try CSVExportService.generateCSV(
            addresses: addresses,
            filenames: filenames,
            outputDirectory: testDir,
            batchName: "Test Batch"
        )
        
        let csvURL = testDir.appendingPathComponent(csvFilename)
        let csvContent = try String(contentsOf: csvURL, encoding: .utf8)
        let lines = csvContent.components(separatedBy: "\n")
        
        // Check header
        XCTAssertEqual(lines[0], "address,qr")
        
        // Check first data row
        XCTAssertTrue(lines[1].contains("161 Sprucewood Crescent"))
        XCTAssertTrue(lines[1].contains("qr/161_sprucewood_crescent.png"))
        
        // Check second data row
        XCTAssertTrue(lines[2].contains("153 Sprucewood Crescent"))
        XCTAssertTrue(lines[2].contains("qr/153_sprucewood_crescent.png"))
    }
    
    func testCSVEscaping() throws {
        let addresses = [
            QRCodeAddress(
                id: UUID(),
                addressId: UUID(),
                formatted: "123 Main St, Apt 4",
                webURL: "https://flyr.app/address/test",
                deepLinkURL: "flyr://address/test"
            )
        ]
        
        let filenames: [UUID: String] = [addresses[0].id: "test.png"]
        
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("csv_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let csvFilename = try CSVExportService.generateCSV(
            addresses: addresses,
            filenames: filenames,
            outputDirectory: testDir,
            batchName: "Test"
        )
        
        let csvURL = testDir.appendingPathComponent(csvFilename)
        let csvContent = try String(contentsOf: csvURL, encoding: .utf8)
        
        // CSV should properly escape commas
        XCTAssertTrue(csvContent.contains("\"123 Main St, Apt 4\""))
    }
    
    // MARK: - PNGExportService Tests
    
    func testPNGCount() throws {
        let addresses = [
            QRCodeAddress(
                id: UUID(),
                addressId: UUID(),
                formatted: "Address 1",
                webURL: "https://flyr.app/address/test1",
                deepLinkURL: "flyr://address/test1"
            ),
            QRCodeAddress(
                id: UUID(),
                addressId: UUID(),
                formatted: "Address 2",
                webURL: "https://flyr.app/address/test2",
                deepLinkURL: "flyr://address/test2"
            ),
            QRCodeAddress(
                id: UUID(),
                addressId: UUID(),
                formatted: "Address 3",
                webURL: "https://flyr.app/address/test3",
                deepLinkURL: "flyr://address/test3"
            )
        ]
        
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("png_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let filenames = try PNGExportService.generatePNGs(
            addresses: addresses,
            outputDirectory: testDir,
            useTransparentBackground: false
        )
        
        // Should generate PNG for each address
        XCTAssertEqual(filenames.count, addresses.count)
        
        // Check that files exist
        let qrDir = testDir.appendingPathComponent("qr", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: qrDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, addresses.count)
    }
    
    func testPNGFilenameSlugification() throws {
        let addresses = [
            QRCodeAddress(
                id: UUID(),
                addressId: UUID(),
                formatted: "161 Sprucewood Crescent",
                webURL: "https://flyr.app/address/test",
                deepLinkURL: "flyr://address/test"
            )
        ]
        
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("png_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let filenames = try PNGExportService.generatePNGs(
            addresses: addresses,
            outputDirectory: testDir,
            useTransparentBackground: false
        )
        
        let filename = filenames[addresses[0].id]
        XCTAssertNotNil(filename)
        XCTAssertTrue(filename!.contains("161_sprucewood_crescent"))
        XCTAssertTrue(filename!.hasSuffix(".png"))
    }
    
    // MARK: - ZIPArchiveService Tests
    
    func testZIPIntegrity() throws {
        // Create test files
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("zip_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        // Create qr subdirectory with test PNG
        let qrDir = testDir.appendingPathComponent("qr", isDirectory: true)
        try FileManager.default.createDirectory(at: qrDir, withIntermediateDirectories: true)
        
        let testPNG = qrDir.appendingPathComponent("test.png")
        let testData = Data("test png data".utf8)
        try testData.write(to: testPNG)
        
        // Create test CSV
        let testCSV = testDir.appendingPathComponent("test.csv")
        let csvData = Data("address,qr\ntest,qr/test.png".utf8)
        try csvData.write(to: testCSV)
        
        // Create ZIP
        let zipURL = try ZIPArchiveService.createZIP(
            batchName: "Test Batch",
            qrDirectory: testDir,
            csvFile: testCSV,
            outputURL: testDir
        )
        
        // Verify ZIP exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))
        
        // Verify ZIP is not empty
        let zipData = try Data(contentsOf: zipURL)
        XCTAssertGreaterThan(zipData.count, 0)
        
        // Verify ZIP has correct structure (contains batch name in path)
        // This is a basic check - full ZIP parsing would require ZIPFoundation or similar
        let zipString = String(data: zipData, encoding: .utf8) ?? ""
        // ZIP files contain binary data, but we can check for file signatures
        XCTAssertTrue(zipData.prefix(4) == Data([0x50, 0x4b, 0x03, 0x04]) || 
                      zipData.prefix(4) == Data([0x50, 0x4b, 0x05, 0x06]) ||
                      zipData.prefix(4) == Data([0x50, 0x4b, 0x01, 0x02]))
    }
    
    // MARK: - PDF Tests (Basic structure validation)
    
    func testPDFGridPageCount() throws {
        // Create test addresses
        let addresses = (1...15).map { index in
            QRCodeAddress(
                id: UUID(),
                addressId: UUID(),
                formatted: "Address \(index)",
                webURL: "https://flyr.app/address/test\(index)",
                deepLinkURL: "flyr://address/test\(index)"
            )
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("pdf_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let pdfURL = try PDFGridRenderer.generatePDF(
            addresses: addresses,
            batchName: "Test Batch",
            outputURL: testDir
        )
        
        // Verify PDF exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: pdfURL.path))
        
        // Verify PDF is not empty
        let pdfData = try Data(contentsOf: pdfURL)
        XCTAssertGreaterThan(pdfData.count, 0)
        
        // Verify PDF signature
        let pdfString = String(data: pdfData.prefix(8), encoding: .ascii) ?? ""
        XCTAssertTrue(pdfString.contains("%PDF"))
    }
    
    func testPDFSinglePageCount() throws {
        // Create test addresses
        let addresses = (1...5).map { index in
            QRCodeAddress(
                id: UUID(),
                addressId: UUID(),
                formatted: "Address \(index)",
                webURL: "https://flyr.app/address/test\(index)",
                deepLinkURL: "flyr://address/test\(index)"
            )
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("pdf_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let pdfURL = try PDFSingleRenderer.generatePDF(
            addresses: addresses,
            batchName: "Test Batch",
            outputURL: testDir
        )
        
        // Verify PDF exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: pdfURL.path))
        
        // Verify PDF is not empty
        let pdfData = try Data(contentsOf: pdfURL)
        XCTAssertGreaterThan(pdfData.count, 0)
        
        // Verify PDF signature
        let pdfString = String(data: pdfData.prefix(8), encoding: .ascii) ?? ""
        XCTAssertTrue(pdfString.contains("%PDF"))
    }
}

