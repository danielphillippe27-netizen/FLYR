import Foundation
import CoreGraphics

/// Thermal label size options for QR code printing
public enum ThermalLabelSize {
    case size2x2   // 2×2 inches = 600×600 pixels @ 300 DPI
    case size3x3   // 3×3 inches = 900×900 pixels @ 300 DPI
    
    /// Pixel dimensions at 300 DPI
    public var pixelSize: CGSize {
        switch self {
        case .size2x2:
            return CGSize(width: 600, height: 600)
        case .size3x3:
            return CGSize(width: 900, height: 900)
        }
    }
    
    /// Dots per inch (standard for thermal printers)
    public var dpi: Int {
        return 300
    }
    
    /// Display name for UI
    public var displayName: String {
        switch self {
        case .size2x2:
            return "2×2 inches"
        case .size3x3:
            return "3×3 inches"
        }
    }
}

