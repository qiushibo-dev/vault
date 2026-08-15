import AppKit
import CoreText

// Vault 的 app icon：桃色 squircle ＋ Alfa Slab One 的 V
// usage: makeicon <font.ttf> <out.png>
//
// 直接畫進 NSBitmapImageRep。用 NSImage + lockFocus 的話背景會變成不透明的黑，
// icon 四角必須是透明的。

let args = CommandLine.arguments
guard args.count >= 3 else { exit(1) }

CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: args[1]) as CFURL, .process, nil)

let S = 1024
let side = CGFloat(S)
// macOS 的圖示格線：內容區佔 824/1024，四邊各留 100
let inset: CGFloat = 100
let box = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)

guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let shape = NSBezierPath(roundedRect: box, xRadius: 185, yRadius: 185)
NSColor(srgbRed: 0xf6/255, green: 0xe0/255, blue: 0xdb/255, alpha: 1).setFill()
shape.fill()

// **不要描黑框。**
// DESIGN.md 的「2px 黑框」是給 UI 卡片用的。等比放大到 1024 尺度會變成 13px，
// 縮回 Dock 的 32px 之後只剩 0.4px，抗鋸齒把它糊成一圈灰黑，讀起來像髒邊而不是設計。
// macOS 的圖示慣例本來也不描外框——輪廓由形狀本身負責。

let size: CGFloat = 600
guard let font = NSFont(name: "AlfaSlabOne-Regular", size: size)
              ?? NSFont(name: "Alfa Slab One", size: size) else {
    FileHandle.standardError.write("font not found\n".data(using: .utf8)!)
    exit(1)
}
let s = NSAttributedString(string: "V", attributes: [.font: font,
                                                     .foregroundColor: NSColor.black])
// 視覺置中。字框含 descender，靠 bounding box 對齊會整個偏高，所以往下推一點。
let sz = s.size()
s.draw(at: NSPoint(x: (side - sz.width) / 2, y: (side - sz.height) / 2 - 26))

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
