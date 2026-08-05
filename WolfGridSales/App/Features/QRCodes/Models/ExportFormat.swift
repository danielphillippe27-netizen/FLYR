import Foundation

/// Export format for batch QR codes
public enum ExportFormat: String, Codable, CaseIterable {
    case pdf = "pdf"
    case label3x3 = "3x3_label"
    case png = "png"
    case canva = "canva"
    
    /// Display label for UI
    public var displayLabel: String {
        switch self {
        case .pdf:
            return "PDF (Grid)"
        case .label3x3:
            return "3×3 Thermal Labels"
        case .png:
            return "PNG Images"
        case .canva:
            return "Canva Export"
        }
    }
    
    /// System icon name for UI
    public var iconName: String {
        switch self {
        case .pdf:
            return "doc.fill"
        case .label3x3:
            return "printer.fill"
        case .png:
            return "photo.fill"
        case .canva:
            return "paintbrush.fill"
        }
    }
    
    /// Description text for UI
    public var description: String {
        switch self {
        case .pdf:
            return "Single PDF with QR codes in a grid layout"
        case .label3x3:
            return "3×3 inch thermal labels for printing"
        case .png:
            return "Individual PNG image files"
        case .canva:
            return "PNG files with CSV mapping for Canva"
        }
    }
}



