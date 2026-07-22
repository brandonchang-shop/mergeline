import AppKit

// Renders a 1024×1024 app icon: rounded "squircle" with a blue→purple gradient
// and a white "</>" glyph. Output: icon_1024.png (next to CWD).

let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Rounded-rect background (leave a small margin like macOS icons)
let inset = 64.0
let rect = CGRect(x: inset, y: inset, width: size - inset*2, height: size - inset*2)
let radius = (size - inset*2) * 0.225   // macOS squircle-ish corner
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(path)
ctx.clip()

// Gradient fill (blue → purple)
let colors = [NSColor(calibratedRed: 0.29, green: 0.44, blue: 0.96, alpha: 1).cgColor,
              NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.92, alpha: 1).cgColor] as CFArray
if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
    ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
}

// "</>" glyph, centered
let glyph = "</>"
let font = NSFont.systemFont(ofSize: 430, weight: .bold)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white
]
let str = NSAttributedString(string: glyph, attributes: attrs)
let textSize = str.size()
let point = CGPoint(x: (size - textSize.width)/2, y: (size - textSize.height)/2)
str.draw(at: point)

img.unlockFocus()

// Write PNG
guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: "icon_1024.png"))
print("wrote icon_1024.png")
