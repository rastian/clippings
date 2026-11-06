import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent()
func color(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: 1)
}
for dark in [false, true] {
    let size = 1024
    let cg = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
    let background = color(dark ? 0x19231F : 0x345644)
    let paper = color(dark ? 0xE5DDC9 : 0xF5EFDE)
    let ink = color(dark ? 0x263F32 : 0x345644)
    background.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
    let clipping = NSBezierPath()
    clipping.move(to: NSPoint(x: 252, y: 794))
    clipping.line(to: NSPoint(x: 652, y: 794))
    clipping.line(to: NSPoint(x: 772, y: 674))
    clipping.line(to: NSPoint(x: 772, y: 252))
    clipping.line(to: NSPoint(x: 724, y: 230))
    clipping.line(to: NSPoint(x: 676, y: 252))
    clipping.line(to: NSPoint(x: 628, y: 230))
    clipping.line(to: NSPoint(x: 580, y: 252))
    clipping.line(to: NSPoint(x: 532, y: 230))
    clipping.line(to: NSPoint(x: 484, y: 252))
    clipping.line(to: NSPoint(x: 436, y: 230))
    clipping.line(to: NSPoint(x: 388, y: 252))
    clipping.line(to: NSPoint(x: 340, y: 230))
    clipping.line(to: NSPoint(x: 292, y: 252))
    clipping.line(to: NSPoint(x: 252, y: 230))
    clipping.close()
    paper.setFill(); clipping.fill()
    color(dark ? 0xABA990 : 0xBCC5AE).setFill()
    let fold = NSBezierPath()
    fold.move(to: NSPoint(x: 652, y: 794)); fold.line(to: NSPoint(x: 652, y: 674)); fold.line(to: NSPoint(x: 772, y: 674)); fold.close(); fold.fill()
    let attrs: [NSAttributedString.Key:Any] = [.font: NSFont(name: "Georgia-Bold", size: 340)!, .foregroundColor: ink]
    NSString(string: "C").draw(at: NSPoint(x: 310, y: 390), withAttributes: attrs)
    ink.setFill()
    NSBezierPath(rect: NSRect(x: 320, y: 351, width: 384, height: 15)).fill()
    NSBezierPath(rect: NSRect(x: 320, y: 311, width: 260, height: 15)).fill()
    NSGraphicsContext.restoreGraphicsState()
    let data = NSBitmapImageRep(cgImage: cg.makeImage()!).representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent(dark ? "AppIcon-Dark.png" : "AppIcon.png"))
}
