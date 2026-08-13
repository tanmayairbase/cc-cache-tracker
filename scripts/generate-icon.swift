// Generates a 1024x1024 PNG app icon: a terminal glyph (evokes Claude Code,
// a CLI tool) on a warm rounded-square background. Deliberately generic/
// original artwork — no Anthropic logo or trademarked imagery used.
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: size * 0.22, yRadius: size * 0.22)
// #D97757 — Claude's brand orange. Colors aren't copyrightable; this is a
// solid fill, not Anthropic's logo/wordmark.
let claudeOrange = NSColor(srgbRed: 217.0 / 255, green: 119.0 / 255, blue: 87.0 / 255, alpha: 1.0)
claudeOrange.setFill()
bgPath.fill()

if let symbol = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .semibold)
    let glyph = symbol.withSymbolConfiguration(config)!

    // A template image ignores any color you set and renders as a
    // system-controlled monochrome mask (comes out black), so tint a copy
    // of it white first — masking white fill to the glyph's own alpha via
    // sourceAtop, confined to the glyph's own bitmap, not the outer canvas.
    let whiteGlyph = NSImage(size: glyph.size)
    whiteGlyph.lockFocus()
    glyph.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
    NSColor.white.setFill()
    NSRect(origin: .zero, size: glyph.size).fill(using: .sourceAtop)
    whiteGlyph.unlockFocus()

    let symSize = whiteGlyph.size
    let scale = (size * 0.56) / max(symSize.width, symSize.height)
    let drawSize = NSSize(width: symSize.width * scale, height: symSize.height * scale)
    let drawRect = NSRect(
        x: (size - drawSize.width) / 2,
        y: (size - drawSize.height) / 2,
        width: drawSize.width,
        height: drawSize.height
    )
    whiteGlyph.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render icon\n".data(using: .utf8)!)
    exit(1)
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
