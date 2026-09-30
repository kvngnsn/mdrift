import Cocoa

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for (size, name) in [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"),
    (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x"),
] {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let background = NSBezierPath(
        roundedRect: NSRect(x: 65, y: 65, width: 894, height: 894), xRadius: 190, yRadius: 190)
    NSColor(calibratedWhite: 0.032, alpha: 1).setFill()
    background.fill()
    let page = NSBezierPath()
    page.move(to: NSPoint(x: 270, y: 207))
    page.line(to: NSPoint(x: 746, y: 207))
    page.line(to: NSPoint(x: 746, y: 663))
    page.line(to: NSPoint(x: 600, y: 814))
    page.line(to: NSPoint(x: 270, y: 814))
    page.close()
    NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.93, alpha: 1).setFill()
    page.fill()
    let fold = NSBezierPath()
    fold.move(to: NSPoint(x: 600, y: 814))
    fold.line(to: NSPoint(x: 600, y: 663))
    fold.line(to: NSPoint(x: 746, y: 663))
    fold.close()
    NSColor(calibratedWhite: 0.64, alpha: 1).setFill()
    fold.fill()
    let ink = NSColor(calibratedWhite: 0.032, alpha: 1)
    let font = NSFont.monospacedSystemFont(ofSize: 225, weight: .semibold)
    let label = NSAttributedString(string: ".md", attributes: [.font: font, .foregroundColor: ink])
    let labelSize = label.size()
    label.draw(at: NSPoint(x: (1024 - labelSize.width) / 2, y: 332))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(
        to: directory.appendingPathComponent(name + ".png"))
}
