import AppKit
import CoreGraphics
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let cards: [(source: String, filename: String, lines: [String])] = [
    ("Home-KPIs-illustrative.png", "01-Create-Goals.png", ["Create Goals"]),
    ("Build-Your-Territory-new.png", "02-Build-Your-Territory.png", ["Build Your", "Territory"]),
    ("03-Map-3D.png", "03-Track-Progress-Visually.png", ["Track Progress", "Visually"]),
    ("04-Lead.png", "04-Capture-Every-Lead.png", ["Capture Every", "Lead"]),
    ("05-Share-Activity.png", "05-Share-Your-Progress.png", ["Share Your", "Progress"]),
    ("06-Customize-Wolf.png", "06-Make-Wolfy-Yours.png", ["Make Wolfy", "Yours"])
]
let width = 1320, height = 2868
let phone = CGRect(x: 127, y: 78, width: 1066, height: 2225)
let screen = phone.insetBy(dx: 20, dy: 20)
let silver = CGColor(red: 0.57, green: 0.59, blue: 0.60, alpha: 1)
let darkMetal = CGColor(red: 0.16, green: 0.17, blue: 0.18, alpha: 1)

func rounded(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawLine(_ value: String, baseline: CGFloat, context: CGContext) {
    let font = NSFont.systemFont(ofSize: 118, weight: .heavy)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .kern: -2.2
    ]
    let text = value as NSString
    let size = text.size(withAttributes: attributes)
    let x = (CGFloat(width) - size.width) / 2
    text.draw(at: NSPoint(x: x, y: baseline), withAttributes: attributes)
}

for card in cards {
    let sourceURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true).appendingPathComponent(card.source)
    guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: sourceURL)),
          let screenshot = bitmap.cgImage else { fatalError("Cannot read \(sourceURL.path)") }
    let context = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .high

    // Device side keys and body, kept behind the screenshot.
    context.setFillColor(darkMetal)
    context.fill(CGRect(x: phone.minX - 7, y: 1665, width: 10, height: 110))
    context.fill(CGRect(x: phone.minX - 7, y: 1415, width: 10, height: 160))
    context.fill(CGRect(x: phone.maxX - 3, y: 1370, width: 10, height: 170))
    context.setFillColor(CGColor(gray: 0.02, alpha: 1))
    context.addPath(rounded(phone, radius: 145))
    context.fillPath()
    context.setStrokeColor(silver)
    context.setLineWidth(10)
    context.addPath(rounded(phone, radius: 145))
    context.strokePath()
    context.setStrokeColor(CGColor(red: 0.28, green: 0.30, blue: 0.31, alpha: 1))
    context.setLineWidth(4)
    context.addPath(rounded(phone.insetBy(dx: 8, dy: 8), radius: 138))
    context.strokePath()

    context.saveGState()
    context.addPath(rounded(screen, radius: 123))
    context.clip()
    let scale = screen.width / CGFloat(screenshot.width)
    let drawHeight = CGFloat(screenshot.height) * scale
    context.draw(screenshot, in: CGRect(x: screen.minX,
                                       y: screen.maxY - drawHeight,
                                       width: screen.width, height: drawHeight))
    if card.source == "06-Customize-Wolf.png" {
        // The captured screen has a transient sync error below the stage meter.
        // Cover only that status line with the same panel color for the store card.
        context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [28.0 / 255.0, 28.0 / 255.0, 30.0 / 255.0, 1])!)
        context.fill(CGRect(x: screen.minX + 20, y: 583, width: screen.width - 40, height: 80))
    }
    context.restoreGState()
    context.setStrokeColor(CGColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1))
    context.setLineWidth(5)
    context.addPath(rounded(screen, radius: 123))
    context.strokePath()

    // Dynamic Island to complete the hardware framing.
    let island = CGRect(x: (CGFloat(width) - 232) / 2, y: screen.maxY - 92, width: 232, height: 72)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.addPath(rounded(island, radius: 37))
    context.fillPath()
    context.setStrokeColor(CGColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1))
    context.setLineWidth(7)
    context.addPath(rounded(island, radius: 37))
    context.strokePath()
    context.setFillColor(CGColor(red: 0.025, green: 0.04, blue: 0.055, alpha: 1))
    context.fillEllipse(in: CGRect(x: island.maxX - 49, y: island.midY - 18, width: 36, height: 36))

    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    if card.lines.count == 1 {
        drawLine(card.lines[0], baseline: 2510, context: context)
    } else {
        drawLine(card.lines[0], baseline: 2545, context: context)
        drawLine(card.lines[1], baseline: 2395, context: context)
    }
    NSGraphicsContext.restoreGraphicsState()

    guard let image = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode \(card.filename)")
    }
    let output = destination.appendingPathComponent(card.filename)
    try png.write(to: output)
    print(output.path)
}
