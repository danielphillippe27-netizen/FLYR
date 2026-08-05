import Foundation

/// Export mode options for QR code exports
public enum ExportMode: String, CaseIterable, Identifiable {
    case pdfGrid = "PDF Grid"
    case pdfSingle = "PDF Single"
    case pngOnly = "PNG Only"
    case zipArchive = "ZIP Archive"
    
    public var id: String { rawValue }
    
    /// Display name for the export mode
    public var displayName: String {
        switch self {
        case .pdfGrid:
            return "PDF (Print Grid)"
        case .pdfSingle:
            return "PDF (One Per Page)"
        case .pngOnly:
            return "PNG Only"
        case .zipArchive:
            return "ZIP (PNG + CSV)"
        }
    }
    
    /// Description for the export mode
    public var description: String {
        switch self {
        case .pdfGrid:
            return "Multiple QR codes per page in a grid layout (2×3 or 3×3)"
        case .pdfSingle:
            return "One QR code per page, perfect for print shops"
        case .pngOnly:
            return "Individual PNG files for each QR code"
        case .zipArchive:
            return "ZIP file containing PNG files and CSV for Canva bulk create"
        }
    }
    
    /// System icon name for the export mode
    public var iconName: String {
        switch self {
        case .pdfGrid:
            return "square.grid.2x2"
        case .pdfSingle:
            return "doc.text"
        case .pngOnly:
            return "photo"
        case .zipArchive:
            return "archivebox"
        }
    }
}

