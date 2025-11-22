import Foundation

/// Creates ZIP archives for QR code exports
struct QRZipExporter {
    
    /// Create ZIP file containing CSV and all PNG files
    /// Uses streaming to avoid loading all files into memory
    /// - Parameters:
    ///   - sourceDirectory: Directory containing CSV and PNG files
    ///   - campaignName: Campaign name for ZIP filename
    ///   - outputURL: URL where ZIP file should be saved
    /// - Returns: URL of the created ZIP file
    /// - Throws: Error if ZIP creation fails
    static func createZIP(
        sourceDirectory: URL,
        campaignName: String,
        outputURL: URL
    ) throws -> URL {
        // Sanitize campaign name for filesystem
        let sanitizedCampaignName = sanitizeFilename(campaignName)
        let zipFilename = "FLYR_QR_EXPORT_\(sanitizedCampaignName).zip"
        let zipURL = outputURL.appendingPathComponent(zipFilename)
        
        // Remove existing ZIP if it exists
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }
        
        // Get all files in source directory
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: [.fileSizeKey])
        
        // Create ZIP file using streaming approach
        try createZipArchiveStreaming(files: files, outputURL: zipURL)
        
        return zipURL
    }
    
    /// Create ZIP archive using streaming to minimize memory usage
    private static func createZipArchiveStreaming(files: [URL], outputURL: URL) throws {
        // Create output file
        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: nil)
        guard let outputHandle = FileHandle(forWritingAtPath: outputURL.path) else {
            throw QRExportError.zipCreationFailed
        }
        defer { outputHandle.closeFile() }
        
        // Store file metadata for central directory
        struct FileMetadata {
            let fileName: String
            let localHeaderOffset: UInt32
            let fileSize: UInt32
            let crc: UInt32
        }
        
        var fileMetadata: [FileMetadata] = []
        var currentOffset: UInt32 = 0
        
        // Write local file headers and file data (streaming)
        for file in files {
            autoreleasepool {
                let fileName = file.lastPathComponent
                let fileNameData = fileName.data(using: .utf8)!
                
                // Read file data only once
                guard let fileData = try? Data(contentsOf: file) else { return }
                let fileSize = UInt32(fileData.count)
                let crc = calculateCRC32(data: fileData)
                
                // Create local file header
                var localHeader = Data()
                localHeader.append(contentsOf: [0x50, 0x4b, 0x03, 0x04]) // Signature
                localHeader.append(contentsOf: [0x14, 0x00]) // Version
                localHeader.append(contentsOf: [0x00, 0x00]) // Flags
                localHeader.append(contentsOf: [0x00, 0x00]) // Compression method
                localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // Mod time
                localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // Mod date
                localHeader.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Data($0) }) // CRC
                localHeader.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Data($0) }) // Compressed size
                localHeader.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Data($0) }) // Uncompressed size
                localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Data($0) }) // Filename length
                localHeader.append(contentsOf: [0x00, 0x00]) // Extra field length
                localHeader.append(fileNameData) // Filename
                
                // Write header and file data immediately
                outputHandle.write(localHeader)
                outputHandle.write(fileData)
                
                // Store metadata for central directory
                fileMetadata.append(FileMetadata(
                    fileName: fileName,
                    localHeaderOffset: currentOffset,
                    fileSize: fileSize,
                    crc: crc
                ))
                
                // Update offset
                currentOffset += UInt32(localHeader.count) + fileSize
            }
        }
        
        // Write central directory
        let centralDirOffset = currentOffset
        for metadata in fileMetadata {
            let fileNameData = metadata.fileName.data(using: .utf8)!
            
            var centralHeader = Data()
            centralHeader.append(contentsOf: [0x50, 0x4b, 0x01, 0x02]) // Signature
            centralHeader.append(contentsOf: [0x14, 0x00]) // Version made by
            centralHeader.append(contentsOf: [0x14, 0x00]) // Version needed
            centralHeader.append(contentsOf: [0x00, 0x00]) // Flags
            centralHeader.append(contentsOf: [0x00, 0x00]) // Compression method
            centralHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // Mod time
            centralHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) }) // Mod date
            centralHeader.append(contentsOf: withUnsafeBytes(of: metadata.crc.littleEndian) { Data($0) }) // CRC
            centralHeader.append(contentsOf: withUnsafeBytes(of: metadata.fileSize.littleEndian) { Data($0) }) // Compressed size
            centralHeader.append(contentsOf: withUnsafeBytes(of: metadata.fileSize.littleEndian) { Data($0) }) // Uncompressed size
            centralHeader.append(contentsOf: withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Data($0) }) // Filename length
            centralHeader.append(contentsOf: [0x00, 0x00]) // Extra field length
            centralHeader.append(contentsOf: [0x00, 0x00]) // Comment length
            centralHeader.append(contentsOf: [0x00, 0x00]) // Disk number
            centralHeader.append(contentsOf: [0x00, 0x00]) // Internal attributes
            centralHeader.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // External attributes
            centralHeader.append(contentsOf: withUnsafeBytes(of: metadata.localHeaderOffset.littleEndian) { Data($0) }) // Local header offset
            centralHeader.append(fileNameData) // Filename
            
            outputHandle.write(centralHeader)
            currentOffset += UInt32(centralHeader.count)
        }
        
        // Write end of central directory
        let centralDirSize = currentOffset - centralDirOffset
        var eocd = Data()
        eocd.append(contentsOf: [0x50, 0x4b, 0x05, 0x06]) // Signature
        eocd.append(contentsOf: [0x00, 0x00]) // Disk number
        eocd.append(contentsOf: [0x00, 0x00]) // Central dir disk
        eocd.append(contentsOf: withUnsafeBytes(of: UInt16(fileMetadata.count).littleEndian) { Data($0) }) // Entries on disk
        eocd.append(contentsOf: withUnsafeBytes(of: UInt16(fileMetadata.count).littleEndian) { Data($0) }) // Total entries
        eocd.append(contentsOf: withUnsafeBytes(of: centralDirSize.littleEndian) { Data($0) }) // Central dir size
        eocd.append(contentsOf: withUnsafeBytes(of: centralDirOffset.littleEndian) { Data($0) }) // Central dir offset
        eocd.append(contentsOf: [0x00, 0x00]) // Comment length
        
        outputHandle.write(eocd)
    }
    
    /// Calculate CRC-32 checksum
    private static func calculateCRC32(data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        let polynomial: UInt32 = 0xedb88320
        
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ polynomial
                } else {
                    crc >>= 1
                }
            }
        }
        
        return crc ^ 0xffffffff
    }
    
    /// Sanitize campaign name for use in filename
    private static func sanitizeFilename(_ name: String) -> String {
        // Remove invalid filesystem characters
        let invalidChars = CharacterSet(charactersIn: "/\\?%*|\"<>")
        let sanitized = name
            .components(separatedBy: invalidChars)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Limit length
        let maxLength = 50
        if sanitized.count > maxLength {
            return String(sanitized.prefix(maxLength))
        }
        
        return sanitized.isEmpty ? "campaign" : sanitized
    }
}

