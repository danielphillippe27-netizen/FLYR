import Foundation
import UIKit
import SwiftUI

/// Manages thermal label printing operations
@MainActor
public class ThermalPrintManager {
    public static let shared = ThermalPrintManager()
    
    private init() {}
    
    /// Generate a thermal label PNG
    /// - Parameters:
    ///   - qrURL: The URL string to encode in the QR code
    ///   - address: Optional address text
    ///   - campaign: Optional campaign name
    ///   - size: Label size (2×2 or 3×3 inches)
    /// - Returns: URL to the generated PNG file
    /// - Throws: Error if generation fails
    public func generateLabel(
        qrURL: String,
        address: String?,
        campaign: String?,
        size: ThermalLabelSize
    ) async throws -> URL {
        return try ThermalLabelGenerator.generate(
            url: qrURL,
            address: address,
            campaignName: campaign,
            size: size
        )
    }
    
    /// Print label using AirPrint
    /// - Parameter url: URL to the PNG file to print
    public func airPrint(url: URL) {
        guard let imageData = try? Data(contentsOf: url),
              let image = UIImage(data: imageData) else {
            print("❌ [ThermalPrint] Failed to load image for printing")
            return
        }
        
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .photo
        printInfo.orientation = .portrait
        printInfo.duplex = .none
        
        printController.printInfo = printInfo
        printController.printingItem = image
        
        // Find the key window's root view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              let rootViewController = window.rootViewController else {
            print("❌ [ThermalPrint] Could not find root view controller")
            return
        }
        
        // Present print dialog
        printController.present(animated: true) { (controller, completed, error) in
            if let error = error {
                print("❌ [ThermalPrint] Print error: \(error.localizedDescription)")
            } else if completed {
                print("✅ [ThermalPrint] Print completed")
            }
        }
    }
    
    /// Create a share sheet for printing (fallback method)
    /// - Parameter url: URL to the PNG file to share/print
    /// - Returns: UIActivityViewController configured for sharing
    public func shareSheetPrint(url: URL) -> UIActivityViewController {
        let activityItems: [Any] = [url]
        
        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        // Exclude some activity types that don't make sense for printing
        activityViewController.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .postToFlickr,
            .postToVimeo,
            .postToTencentWeibo,
            .postToWeibo
        ]
        
        return activityViewController
    }
    
    /// Print via Bluetooth ESC/POS printer (future implementation)
    /// - Parameter url: URL to the PNG file to print
    /// - Note: This is a stub for future Bluetooth printer support
    public func printViaBluetooth(_ url: URL) {
        // TODO: Implement Bluetooth ESC/POS printing
        // This would involve:
        // 1. Discovering Bluetooth printers
        // 2. Converting PNG to ESC/POS bitmap format
        // 3. Sending commands to printer via Bluetooth
        print("⚠️ [ThermalPrint] Bluetooth printing not yet implemented")
    }
}

