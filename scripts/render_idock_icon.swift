import AppKit

// Reproducible vector source for the iDock icon; no external artwork.
let destination = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let rect = NSRect(x: 80, y: 80, width: 864, height: 864)
let shape = NSBezierPath(roundedRect: rect, xRadius: 194, yRadius: 194)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor(white: 0.92, alpha: 1).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [NSColor(srgbRed: 0.97, green: 0.985, blue: 1, alpha: 1),
                    NSColor(srgbRed: 0.78, green: 0.84, blue: 0.92, alpha: 1)])!
    .draw(in: shape, angle: -65)
NSColor.white.withAlphaComponent(0.9).setStroke()
shape.lineWidth = 3
shape.stroke()
let inner = NSBezierPath(roundedRect: rect.insetBy(dx: 72, dy: 72), xRadius: 150, yRadius: 150)
NSGradient(colors: [NSColor(srgbRed: 0.20, green: 0.70, blue: 1, alpha: 1),
                    NSColor(srgbRed: 0.015, green: 0.34, blue: 0.85, alpha: 1)])!
    .draw(in: inner, angle: -90)
NSColor.white.withAlphaComponent(0.65).setStroke()
inner.lineWidth = 3
inner.stroke()
NSGraphicsContext.saveGraphicsState()
inner.addClip()
let gleam = NSBezierPath(ovalIn: NSRect(x: 115, y: 490, width: 900, height: 430))
NSGradient(starting: NSColor.white.withAlphaComponent(0.34), ending: NSColor.white.withAlphaComponent(0))!
    .draw(in: gleam, angle: -90)
NSGraphicsContext.restoreGraphicsState()
let symbol = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: nil)!
let config = NSImage.SymbolConfiguration(pointSize: 340, weight: .medium)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
let mark = symbol.withSymbolConfiguration(config)!
let aspect = mark.size.width / mark.size.height
let width: CGFloat = 500
let height = width / aspect
mark.draw(in: NSRect(x: (1024-width)/2, y: (1024-height)/2, width: width, height: height))
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
