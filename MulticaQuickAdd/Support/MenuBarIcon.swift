import AppKit

extension NSImage {
  // The Multica asterisk, traced from the official favicon polygon (100x100 viewBox).
  @MainActor static let multicaMenuBarIcon: NSImage = {
    let points: [CGPoint] = [
      CGPoint(x: 45, y: 62.1), CGPoint(x: 45, y: 100), CGPoint(x: 55, y: 100),
      CGPoint(x: 55, y: 62.1), CGPoint(x: 81.8, y: 88.9), CGPoint(x: 88.9, y: 81.8),
      CGPoint(x: 62.1, y: 55), CGPoint(x: 100, y: 55), CGPoint(x: 100, y: 45),
      CGPoint(x: 62.1, y: 45), CGPoint(x: 88.9, y: 18.2), CGPoint(x: 81.8, y: 11.1),
      CGPoint(x: 55, y: 37.9), CGPoint(x: 55, y: 0), CGPoint(x: 45, y: 0),
      CGPoint(x: 45, y: 37.9), CGPoint(x: 18.2, y: 11.1), CGPoint(x: 11.1, y: 18.2),
      CGPoint(x: 37.9, y: 45), CGPoint(x: 0, y: 45), CGPoint(x: 0, y: 55),
      CGPoint(x: 37.9, y: 55), CGPoint(x: 11.1, y: 81.8), CGPoint(x: 18.2, y: 88.9),
    ]
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { rect in
      let scale = rect.width / 100
      let path = NSBezierPath()
      path.move(to: NSPoint(x: points[0].x * scale, y: points[0].y * scale))
      for point in points.dropFirst() {
        path.line(to: NSPoint(x: point.x * scale, y: point.y * scale))
      }
      path.close()
      NSColor.black.setFill()
      path.fill()
      return true
    }
    image.isTemplate = true
    return image
  }()
}
