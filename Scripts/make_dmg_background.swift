// Draws the DMG background image: a title, a bilingual "drag to Applications"
// hint, an arrow between the two icon positions and a first-launch note.
//
// Usage: swift Scripts/make_dmg_background.swift <output.tiff>
//
// The image is written as a two-representation TIFF (1x at 72 dpi and 2x at
// 144 dpi) so it looks sharp on both Retina and non-Retina displays.

import AppKit
import ImageIO
import UniformTypeIdentifiers

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "dmg-background.tiff"

// Matches the Finder window size set in make_dmg.sh (bounds 100,100,760,548).
let width: CGFloat = 660
let height: CGFloat = 420

/// Top-left origin helper, because AppKit draws from the bottom-left.
func yFromTop(_ y: CGFloat) -> CGFloat { height - y }

func drawContent() {
    let full = NSRect(x: 0, y: 0, width: width, height: height)

    // Soft vertical gradient.
    let gradient = NSGradient(colors: [
        NSColor(deviceWhite: 1.0, alpha: 1.0),
        NSColor(deviceWhite: 0.93, alpha: 1.0),
    ])
    gradient?.draw(in: full, angle: -90)

    func centered(_ text: String, top: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (width - size.width) / 2, y: yFromTop(top) - size.height),
                  withAttributes: attributes)
    }

    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 26, weight: .bold),
        .foregroundColor: NSColor(deviceWhite: 0.15, alpha: 1.0),
    ]
    centered("Whisky YAAGL", top: 74, attributes: titleAttrs)

    let hintAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        .foregroundColor: NSColor(deviceWhite: 0.35, alpha: 1.0),
    ]
    centered("Drag Whisky YAAGL into the Applications folder to install", top: 104, attributes: hintAttrs)
    centered("将 Whisky YAAGL 拖入 Applications 文件夹即可完成安装", top: 124, attributes: hintAttrs)

    // Arrow between the app icon (x≈165) and the Applications icon (x≈495).
    let midY = yFromTop(205)
    let arrowColor = NSColor(calibratedRed: 0.20, green: 0.47, blue: 0.90, alpha: 0.65)
    arrowColor.setStroke()
    arrowColor.setFill()

    let shaft = NSBezierPath()
    shaft.lineWidth = 9
    shaft.lineCapStyle = .round
    shaft.move(to: NSPoint(x: 252, y: midY))
    shaft.line(to: NSPoint(x: 402, y: midY))
    shaft.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: 406, y: midY))
    head.line(to: NSPoint(x: 380, y: midY + 17))
    head.line(to: NSPoint(x: 380, y: midY - 17))
    head.close()
    head.fill()

    let helpAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor(deviceWhite: 0.45, alpha: 1.0),
    ]
    centered("First launch: right-click Whisky YAAGL in Applications and choose Open.",
             top: 350, attributes: helpAttrs)
    centered("首次打开：在“应用程序”中右键 Whisky YAAGL 并选择“打开”。",
             top: 372, attributes: helpAttrs)
}

func makeRepresentation(scale: CGFloat) -> NSBitmapImageRep {
    let pixelWidth = Int(width * scale)
    let pixelHeight = Int(height * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelWidth,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("could not allocate a bitmap representation")
    }
    rep.size = NSSize(width: width, height: height)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("could not create a graphics context")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    drawContent()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let rep1x = makeRepresentation(scale: 1)
let rep2x = makeRepresentation(scale: 2)

guard let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: outPath) as CFURL,
    UTType.tiff.identifier as CFString,
    2,
    nil
) else {
    fatalError("could not create the output image destination")
}

func properties(dpi: Int) -> CFDictionary {
    [
        kCGImagePropertyDPIWidth: dpi,
        kCGImagePropertyDPIHeight: dpi,
        kCGImagePropertyTIFFDictionary: [
            kCGImagePropertyTIFFXResolution: dpi,
            kCGImagePropertyTIFFYResolution: dpi,
            kCGImagePropertyTIFFCompression: 5, // LZW
        ],
    ] as CFDictionary
}

CGImageDestinationAddImage(destination, rep1x.cgImage!, properties(dpi: 72))
CGImageDestinationAddImage(destination, rep2x.cgImage!, properties(dpi: 144))
guard CGImageDestinationFinalize(destination) else {
    fatalError("could not write \(outPath)")
}

print("wrote \(outPath)")
