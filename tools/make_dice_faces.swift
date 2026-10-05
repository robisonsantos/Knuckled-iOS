import AppKit
import CoreGraphics

// Standard pip cells (3x3 positions 1-9, row-major) per face value.
func pips(for value: Int) -> Set<Int> {
    switch value {
    case 1: return [5]
    case 2: return [1, 9]
    case 3: return [1, 5, 9]
    case 4: return [1, 3, 7, 9]
    case 5: return [1, 3, 5, 7, 9]
    case 6: return [1, 3, 4, 6, 7, 9]
    default: return []
    }
}

let size = CGSize(width: 256, height: 256)
let ivory = CGColor(red: 0xFF/255, green: 0xFA/255, blue: 0xF0/255, alpha: 1)
let brown = CGColor(red: 0x1A/255, green: 0x12/255, blue: 0x07/255, alpha: 1)

for value in 1...6 {
    let image = NSImage(size: size)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }
    ctx.setFillColor(ivory)
    ctx.fill(CGRect(origin: .zero, size: size))
    ctx.setFillColor(brown)
    let cell = size.width / 3
    for pos in pips(for: value) {
        let cx = cell * (CGFloat((pos - 1) % 3) + 0.5)
        let cy = cell * (CGFloat((pos - 1) / 3) + 0.5)
        ctx.fillEllipse(in: CGRect(x: cx - cell * 0.26, y: cy - cell * 0.26, width: cell * 0.52, height: cell * 0.52))
    }
    image.unlockFocus()
    let out = URL(fileURLWithPath: "Knuckled/Resources/DiceFaces/\(value).png")
    guard let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("encode failed") }
    CGImageDestinationAddImage(dest, cg, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
    print("wrote \(out.path)")
}
