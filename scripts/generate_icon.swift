import AppKit

let size = 1024
guard let cgContext = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Graphics context failed") }
let context = NSGraphicsContext(cgContext: cgContext, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(srgbRed: 0.16, green: 0.34, blue: 0.27, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
let transform = AffineTransform(rotationByDegrees: 42)
func loop(_ center: NSPoint, width: CGFloat, height: CGFloat) {
    let path = NSBezierPath(roundedRect: NSRect(x: -width/2, y: -height/2, width: width, height: height), xRadius: height/2, yRadius: height/2)
    path.transform(using: transform)
    path.transform(using: AffineTransform(translationByX: center.x, byY: center.y))
    path.lineWidth = 68
    NSColor(srgbRed: 0.96, green: 0.94, blue: 0.86, alpha: 1).setStroke()
    path.stroke()
}
loop(NSPoint(x: 399, y: 410), width: 366, height: 237)
loop(NSPoint(x: 614, y: 604), width: 366, height: 237)
NSColor(srgbRed: 0.89, green: 0.67, blue: 0.44, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 732, y: 227, width: 65, height: 65)).fill()
NSGraphicsContext.restoreGraphicsState()
guard let cgImage = cgContext.makeImage(), let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { fatalError("Icon encoding failed") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
