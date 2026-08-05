import Foundation

/// Errors that can occur during export operations
public enum ExportError: LocalizedError {
    case invalidAddresses
    case pdfGenerationFailed(String)
    case pngGenerationFailed(String)
    case csvGenerationFailed(String)
    case zipCreationFailed(String)
    case supabaseUploadFailed(String)
    case invalidBatchName
    case fileNotFound(String)
    case directoryCreationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidAddresses:
            return "No valid addresses provided for export"
        case .pdfGenerationFailed(let message):
            return "PDF generation failed: \(message)"
        case .pngGenerationFailed(let message):
            return "PNG generation failed: \(message)"
        case .csvGenerationFailed(let message):
            return "CSV generation failed: \(message)"
        case .zipCreationFailed(let message):
            return "ZIP creation failed: \(message)"
        case .supabaseUploadFailed(let message):
            return "Supabase upload failed: \(message)"
        case .invalidBatchName:
            return "Invalid batch name provided"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .directoryCreationFailed(let path):
            return "Failed to create directory: \(path)"
        }
    }
}

