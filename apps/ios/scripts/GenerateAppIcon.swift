import AppKit

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let background = NSBezierPath(rect: CGRect(origin: .zero, size: size))
NSColor(calibratedRed: 0.04, green: 0.36, blue: 0.95, alpha: 1).setFill()
background.fill()

let cardRect = CGRect(x: 184, y: 168, width: 656, height: 688)
let card = NSBezierPath(roundedRect: cardRect, xRadius: 112, yRadius: 112)
NSColor.white.setFill()
card.fill()

let accentRect = CGRect(x: 274, y: 654, width: 476, height: 72)
let accent = NSBezierPath(roundedRect: accentRect, xRadius: 36, yRadius: 36)
NSColor(calibratedRed: 0.04, green: 0.36, blue: 0.95, alpha: 1).setFill()
accent.fill()

for y in [520.0, 394.0, 268.0] {
    let dot = NSBezierPath(ovalIn: CGRect(x: 274, y: y, width: 72, height: 72))
    NSColor(calibratedRed: 0.04, green: 0.36, blue: 0.95, alpha: 1).setFill()
    dot.fill()
    let line = NSBezierPath(roundedRect: CGRect(x: 386, y: y + 12, width: 364, height: 48), xRadius: 24, yRadius: 24)
    NSColor(calibratedRed: 0.70, green: 0.80, blue: 1.0, alpha: 1).setFill()
    line.fill()
}

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render app icon")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
