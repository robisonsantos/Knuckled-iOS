import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Generates Knuckled/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
// NOTE: brief's NSImage lockFocus draft renders at 2048px on Retina Macs
// (backingScaleFactor 2x), which actool rejects ("is 2048x2048 but should be
// 1024x1024") and then emits no Assets.car. This version draws into an
// explicit 1024x1024 bitmap context so the PNG is exactly 1024x1024 pixels.
// Same concept: ivory rounded die + 3 gold pips diagonal on felt-dark.
let W = 1024, H = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}
let size = CGSize(width: 1024, height: 1024)

// Felt-dark background.
ctx.setFillColor(CGColor(red: 0x07/255, green: 0x1A/255, blue: 0x10/255, alpha: 1))
ctx.fill(CGRect(origin: .zero, size: size))

// Ivory die, centered, slightly rotated like a tossed die.
ctx.saveGState()
ctx.translateBy(x: size.width / 2, y: size.height / 2)
ctx.rotate(by: -12 * .pi / 180)
let die = CGRect(x: -280, y: -280, width: 560, height: 560)
let diePath = CGPath(roundedRect: die, cornerWidth: 110, cornerHeight: 110, transform: nil)
ctx.setFillColor(CGColor(red: 0xFF/255, green: 0xFA/255, blue: 0xF0/255, alpha: 1))
ctx.addPath(diePath)
ctx.fillPath()
// 3 gold pips, diagonal.
ctx.setFillColor(CGColor(red: 0xE2/255, green: 0xC2/255, blue: 0x6A/255, alpha: 1))
for (dx, dy) in [(-150, 150), (0, 0), (150, -150)] as [(CGFloat, CGFloat)] {
    ctx.fillEllipse(in: CGRect(x: dx - 62, y: dy - 62, width: 124, height: 124))
}
ctx.restoreGState()

guard let cg = ctx.makeImage() else { fatalError("render failed") }
let out = URL(fileURLWithPath: "Knuckled/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("encode failed")
}
CGImageDestinationAddImage(dest, cg, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("wrote \(out.path)")
