#!/usr/bin/env swift
// Run from the repository root: swift scripts/readme/generate_assets.swift
import AppKit
import CoreText

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("docs/images", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
CTFontManagerRegisterFontsForURL(
    root.appendingPathComponent("iDex/Resources/Fonts/PressStart2P-Regular.ttf") as CFURL,
    .process, nil
)
guard let icon = NSImage(contentsOf: root.appendingPathComponent("iDex/Assets.xcassets/AppIcon.appiconset/AppIcon.png")) else {
    fatalError("Run swift scripts/icon/generate_icon.swift first.")
}

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

func render(name: String, width: Int, height: Int) throws {
    let pixels = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: pixels)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    let scale = CGFloat(width) / 1600
    let canvasHeight = CGFloat(height) / scale
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: scale, y: -scale)
    let flipped = NSGraphicsContext(cgContext: context, flipped: true)
    NSGraphicsContext.current = flipped

    color(0xF5F2E8).setFill()
    NSRect(x: 0, y: 0, width: 1600, height: canvasHeight).fill()
    color(0xB51325).setFill()
    NSRect(x: 0, y: canvasHeight - 10, width: 1600, height: 10).fill()

    func text(_ value: String, x: CGFloat, y: CGFloat, font: NSFont, shade: UInt32) {
        (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
            .font: font, .foregroundColor: color(shade)
        ])
    }
    let middle = canvasHeight / 2
    text("FIELD UNIT 001 / KANTO", x: 92, y: middle - 174,
         font: .monospacedSystemFont(ofSize: 18, weight: .medium), shade: 0x6B705B)
    text("iDex", x: 88, y: middle - 111,
         font: NSFont(name: "PressStart2P-Regular", size: 90)!, shade: 0x24372A)
    text("Gotta scan ’em all.", x: 92, y: middle + 28,
         font: .systemFont(ofSize: 38, weight: .semibold), shade: 0x24372A)
    text("151 Pokémon. Two languages. Zero tall grass.", x: 92, y: middle + 95,
         font: .systemFont(ofSize: 24), shade: 0x626759)
    text("SWIFTUI  /  ON-DEVICE CORE ML", x: 92, y: canvasHeight - 60,
         font: .monospacedSystemFont(ofSize: 16, weight: .medium), shade: 0x6B705B)

    let iconRect = NSRect(x: 1110, y: middle - 188, width: 376, height: 376)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: iconRect, xRadius: 70, yRadius: 70).addClip()
    icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1,
              respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    let data = pixels.representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent(name))
    print("Wrote docs/images/\(name) (\(width) × \(height))")
}

try render(name: "banner.png", width: 1600, height: 560)
try render(name: "social-preview.png", width: 1280, height: 640)
