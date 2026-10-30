// Usage: swift Scripts/make_phone_icon.swift CloudNowPhone/PhoneAssets.xcassets/AppIcon.appiconset/AppIcon.png
// Draws GeForce Now Duo's 1024×1024 app icon: two panels (the Duo's halves) with a play
// symbol across the hinge. Original artwork; no NVIDIA marks.
import AppKit
import CoreGraphics

let size = 1024.0
let space = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha])!
}
func gradient(_ a: UInt32, _ b: UInt32) -> CGGradient {
    CGGradient(colorsSpace: space, colors: [color(a), color(b)] as CFArray, locations: [0, 1])!
}

// Background: deep blue-black, lighter toward the top left.
ctx.drawLinearGradient(gradient(0x1B2433, 0x07090D), start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Two panels with a narrow hinge gap.
let panelWidth = 300.0, panelHeight = 520.0, gap = 28.0, radius = 64.0
let top = (size - panelHeight) / 2
let leftX = size / 2 - gap / 2 - panelWidth
let rightX = size / 2 + gap / 2
for (x, colors) in [(leftX, (UInt32(0x2EE6B0), UInt32(0x0B8F6C))), (rightX, (UInt32(0x22CFA0), UInt32(0x087A5C)))] {
    let rect = CGRect(x: x, y: top, width: panelWidth, height: panelHeight)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.drawLinearGradient(gradient(colors.0, colors.1), start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    ctx.restoreGState()
}

// Play symbol spanning the hinge, with a soft shadow.
let triangle = CGMutablePath()
let cx = size / 2 + 20, cy = size / 2, h = 300.0
triangle.move(to: CGPoint(x: cx - h * 0.42, y: cy + h / 2))
triangle.addLine(to: CGPoint(x: cx - h * 0.42, y: cy - h / 2))
triangle.addLine(to: CGPoint(x: cx + h * 0.5, y: cy))
triangle.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: color(0x000000, 0.45))
// One transparency layer so the outline's shadow doesn't fall onto the fill.
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.setFillColor(color(0xFFFFFF))
ctx.addPath(triangle)
ctx.setLineJoin(.round)
ctx.setLineWidth(36)
ctx.setStrokeColor(color(0xFFFFFF))
ctx.drawPath(using: .fillStroke)
ctx.endTransparencyLayer()
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
