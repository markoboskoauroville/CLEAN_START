// make_icon.swift: the icon of Clean Start (Mantra), drawn in code, run by build.sh on GitHub (never on the Mac).
// MANTRA_MANIFEST six-letter-icon.md: six white letters CLE / STA (CLEan STArt), SF Pro Rounded Black, over one element,
// the power symbol (what the app is about: what happens at power-on), white at 46 %, on the black tile of the unpromoted
// apps (DEFAULT LOOK, #000000), Apple's 824/1024 tile with a soft vertical gradient.
// Usage: swift tools/make_icon.swift <out.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S: CGFloat = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("no bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(white: 0.0, alpha: 1), ending: NSColor(white: 0.09, alpha: 1))?.draw(in: shape, angle: 90)

// the one element behind the letters
if let base = NSImage(systemSymbolName: "power", accessibilityDescription: nil),
   let sym = base.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 520, weight: .regular)) {
    let sz = sym.size
    let k = 640 / max(sz.width, sz.height)
    let w = sz.width * k, h = sz.height * k
    let tinted = NSImage(size: NSSize(width: w, height: h), flipped: false) { r in
        sym.draw(in: r)
        NSColor(white: 1, alpha: 0.46).set()
        r.fill(using: .sourceAtop)
        return true
    }
    tinted.draw(in: NSRect(x: (S - w) / 2, y: (S - h) / 2, width: w, height: h))
}

// six letters, two rows of three, one size
let size: CGFloat = 230
let plain = NSFont.systemFont(ofSize: size, weight: .black)
let font = plain.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? plain
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.55)
shadow.shadowBlurRadius = 18
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white, .shadow: shadow]
let cap = font.capHeight
let gap: CGFloat = 78
for (row, word) in ["CLE", "STA"].enumerated() {
    let a = NSAttributedString(string: word, attributes: attrs)
    let w = a.size().width
    let baseline = row == 0 ? S / 2 + gap / 2 : S / 2 - gap / 2 - cap
    a.draw(at: NSPoint(x: (S - w) / 2, y: baseline + font.descender))
}

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
try png.write(to: URL(fileURLWithPath: out))
print("icon \(out)")
