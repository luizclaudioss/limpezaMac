import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func renderIcon(pixelSize: Int) -> Data? {
    let size = CGFloat(pixelSize)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.08
    let cardRect = rect.insetBy(dx: inset, dy: inset)
    let cornerRadius = cardRect.width * 0.225

    // Drop shadow
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.025)
    shadow.shadowBlurRadius = size * 0.04
    shadow.set()

    let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor.clear.setFill()
    cardPath.fill()

    // Clip to squircle for gradient
    NSGraphicsContext.saveGraphicsState()
    cardPath.addClip()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.07, green: 0.45, blue: 0.98, alpha: 1.0),
        NSColor(calibratedRed: 0.22, green: 0.20, blue: 0.85, alpha: 1.0),
        NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.35, alpha: 1.0)
    ], atLocations: [0.0, 0.55, 1.0], colorSpace: .deviceRGB)
    gradient?.draw(in: cardRect, angle: -55)

    // Subtle top highlight glow
    let glowRect = NSRect(x: cardRect.minX - size * 0.1, y: cardRect.midY, width: cardRect.width * 1.2, height: cardRect.height * 0.7)
    let glow = NSGradient(starting: NSColor.white.withAlphaComponent(0.24), ending: NSColor.white.withAlphaComponent(0.0))
    glow?.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: NSPoint(x: 0, y: 0.2))

    // Subtle inner border
    NSColor.white.withAlphaComponent(0.22).setStroke()
    cardPath.lineWidth = max(1.0, size * 0.012)
    cardPath.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // Draw main SF Symbol: sparkles + internaldrive / trash / broom
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.44, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor.white.set()
        let symRect = NSRect(origin: .zero, size: symbol.size)
        symbol.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        symRect.fill(using: .sourceAtop)
        tinted.unlockFocus()

        let drawSize = symbol.size
        let origin = NSPoint(
            x: (size - drawSize.width) / 2.0,
            y: (size - drawSize.height) / 2.0 + size * 0.02
        )
        tinted.draw(in: NSRect(origin: origin, size: drawSize), from: .zero, operation: .sourceOver, fraction: 0.96)
    }

    // Small shield badge at bottom-right to signify ROOT protection
    let badgeSize = size * 0.22
    let badgeConfig = NSImage.SymbolConfiguration(pointSize: badgeSize * 0.85, weight: .bold)
    if let shield = NSImage(systemSymbolName: "checkmark.shield.fill", accessibilityDescription: nil)?.withSymbolConfiguration(badgeConfig) {
        let tintedShield = NSImage(size: shield.size)
        tintedShield.lockFocus()
        NSColor(calibratedRed: 0.30, green: 0.92, blue: 0.58, alpha: 1.0).set()
        let sRect = NSRect(origin: .zero, size: shield.size)
        shield.draw(in: sRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        sRect.fill(using: .sourceAtop)
        tintedShield.unlockFocus()

        let shieldOrigin = NSPoint(
            x: cardRect.maxX - shield.size.width - size * 0.09,
            y: cardRect.minY + size * 0.09
        )
        tintedShield.draw(in: NSRect(origin: shieldOrigin, size: shield.size), from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, px) in sizes {
    if let data = renderIcon(pixelSize: px) {
        let path = "\(outputDir)/\(filename)"
        try data.write(to: URL(fileURLWithPath: path))
    }
}
print("Generated iconset at \(outputDir)")
