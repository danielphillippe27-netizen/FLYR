import Foundation
import UIKit
import CoreGraphics

/// Generates the app icon image based on the Landing Pages design
struct AppIconGenerator {
    
    /// Generate a 1024x1024 app icon image
    /// - Returns: UIImage of the app icon, or nil if generation fails
    static func generate() -> UIImage? {
        let size = CGSize(width: 1024, height: 1024)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // Fill with dark background (almost black)
            UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0).setFill()
            cgContext.fill(CGRect(origin: .zero, size: size))
            
            // Calculate rounded rectangle dimensions (centered, with padding)
            let padding: CGFloat = 200
            let rectWidth = size.width - (padding * 2)
            let rectHeight = size.height - (padding * 2)
            let cornerRadius: CGFloat = 80
            let rect = CGRect(
                x: padding,
                y: padding,
                width: rectWidth,
                height: rectHeight
            )
            
            // Draw rounded rectangle with dark gray background
            let roundedRect = UIBezierPath(
                roundedRect: rect,
                cornerRadius: cornerRadius
            )
            
            // Dark gray background
            UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0).setFill()
            roundedRect.fill()
            
            // Subtle border/shadow effect (lighter gray outline)
            UIColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 0.6).setStroke()
            roundedRect.lineWidth = 4
            roundedRect.stroke()
            
            // Draw document icon
            drawDocumentIcon(in: cgContext, rect: rect)
            
            // Draw "Landing Pages" text
            drawText("Landing Pages", in: cgContext, rect: rect)
        }
    }
    
    /// Draw the document icon in the center of the rounded rectangle
    private static func drawDocumentIcon(in context: CGContext, rect: CGRect) {
        let iconSize: CGFloat = 280
        let iconY = rect.midY - 80 // Position above center for text below
        let iconRect = CGRect(
            x: rect.midX - iconSize / 2,
            y: iconY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
        
        // Set white color for icon
        UIColor.white.setStroke()
        UIColor.white.setFill()
        context.setLineWidth(12)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // Draw document body (rectangle with folded corner)
        let bodyRect = CGRect(
            x: iconRect.minX + 40,
            y: iconRect.minY + 60,
            width: iconRect.width - 80,
            height: iconRect.height - 100
        )
        
        // Draw folded corner (top right)
        let foldSize: CGFloat = 50
        let foldPath = UIBezierPath()
        foldPath.move(to: CGPoint(x: bodyRect.maxX - foldSize, y: bodyRect.minY))
        foldPath.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.minY + foldSize))
        foldPath.addLine(to: CGPoint(x: bodyRect.maxX - foldSize, y: bodyRect.minY + foldSize))
        foldPath.close()
        foldPath.fill()
        
        // Draw document outline
        let docPath = UIBezierPath()
        docPath.move(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY))
        docPath.addLine(to: CGPoint(x: bodyRect.maxX - foldSize, y: bodyRect.minY))
        docPath.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.minY + foldSize))
        docPath.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY))
        docPath.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.maxY))
        docPath.close()
        docPath.lineWidth = 12
        docPath.stroke()
        
        // Draw two horizontal lines inside document (representing text)
        let lineSpacing: CGFloat = 30
        let lineY1 = bodyRect.midY - lineSpacing / 2
        let lineY2 = bodyRect.midY + lineSpacing / 2
        let linePadding: CGFloat = 40
        let lineWidth = bodyRect.width - (linePadding * 2)
        
        context.setLineWidth(8)
        context.setLineCap(.round)
        
        // First line
        context.move(to: CGPoint(x: bodyRect.minX + linePadding, y: lineY1))
        context.addLine(to: CGPoint(x: bodyRect.minX + linePadding + lineWidth, y: lineY1))
        context.strokePath()
        
        // Second line
        context.move(to: CGPoint(x: bodyRect.minX + linePadding, y: lineY2))
        context.addLine(to: CGPoint(x: bodyRect.minX + linePadding + lineWidth, y: lineY2))
        context.strokePath()
    }
    
    /// Draw the "Landing Pages" text below the icon
    private static func drawText(_ text: String, in context: CGContext, rect: CGRect) {
        let fontSize: CGFloat = 72
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        let textRect = CGRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY + 120, // Position below center
            width: textSize.width,
            height: textSize.height
        )
        
        // Draw text
        attributedString.draw(in: textRect)
    }
    
    /// Save the generated icon to the app icon asset directory
    /// - Parameter outputURL: URL where to save the icon (should be AppIcon.appiconset directory)
    static func saveIcon(to outputURL: URL) throws {
        guard let icon = generate() else {
            throw NSError(domain: "AppIconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate icon"])
        }
        
        guard let pngData = icon.pngData() else {
            throw NSError(domain: "AppIconGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to convert icon to PNG"])
        }
        
        let fileURL = outputURL.appendingPathComponent("AppIcon-1024.png")
        try pngData.write(to: fileURL)
        print("✅ App icon saved to: \(fileURL.path)")
    }
}


