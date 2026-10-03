// 앱 아이콘 생성: swift make_icon.swift <out.png>  (1024px)
import AppKit
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let path = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(path); ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [NSColor(red: 0.98, green: 0.36, blue: 0.33, alpha: 1).cgColor,
                               NSColor(red: 0.55, green: 0.20, blue: 0.62, alpha: 1).cgColor] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
// 파형 막대
let bars: [CGFloat] = [0.22, 0.42, 0.70, 0.48, 0.86, 0.56, 0.34, 0.62, 0.28]
let barW: CGFloat = 46, gap: CGFloat = 26
let total = CGFloat(bars.count) * barW + CGFloat(bars.count - 1) * gap
var x = (size - total) / 2
ctx.setFillColor(NSColor.white.cgColor)
for b in bars {
    let h = b * 520
    let r = CGRect(x: x, y: size / 2 - h / 2, width: barW, height: h)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil)); ctx.fillPath()
    x += barW + gap
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
