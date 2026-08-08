import AppKit
import UniformTypeIdentifiers

// Extracts image attachments from a pasteboard, shared by paste, drag-and-drop,
// and the file picker.
enum ImagePasteboard {
  static let pastedFilename = "Pasted image.png"

  // Pasting prefers text when both are present (e.g. spreadsheet cells copy a
  // bitmap rendering alongside the text). Exceptions: copied image files,
  // where the string is just the filename, and a browser's "Copy Image",
  // where the string is the image's URL.
  static func pastedImages(from pasteboard: NSPasteboard) -> [PendingAttachment] {
    let files = imageFiles(from: pasteboard)
    if !files.isEmpty { return files }
    if let string = pasteboard.string(forType: .string), !isWebURL(string) { return [] }
    return bitmapImages(from: pasteboard)
  }

  private static func isWebURL(_ string: String) -> Bool {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.contains(where: \.isNewline), !trimmed.contains(" ") else { return false }
    return trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://")
  }

  static func draggedImages(from pasteboard: NSPasteboard) -> [PendingAttachment] {
    let files = imageFiles(from: pasteboard)
    return files.isEmpty ? bitmapImages(from: pasteboard) : files
  }

  // Cheap check for drag feedback, so no file bytes are read while hovering.
  static func canReadDraggedImages(from pasteboard: NSPasteboard) -> Bool {
    if pasteboard.canReadObject(forClasses: [NSURL.self], options: imageFileOptions) {
      return true
    }
    return pasteboard.availableType(from: [.png, .tiff]) != nil
  }

  static func attachment(fromFileURL url: URL) -> PendingAttachment? {
    guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return PendingAttachment(filename: url.lastPathComponent, data: data)
  }

  private static var imageFileOptions: [NSPasteboard.ReadingOptionKey: Any] {
    [
      .urlReadingFileURLsOnly: true,
      .urlReadingContentsConformToTypes: [UTType.image.identifier],
    ]
  }

  private static func imageFiles(from pasteboard: NSPasteboard) -> [PendingAttachment] {
    let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: imageFileOptions)
    return (urls as? [URL] ?? []).compactMap { attachment(fromFileURL: $0) }
  }

  private static func bitmapImages(from pasteboard: NSPasteboard) -> [PendingAttachment] {
    if let png = pasteboard.data(forType: .png) {
      return [PendingAttachment(filename: pastedFilename, data: png)]
    }
    if let tiff = pasteboard.data(forType: .tiff), let png = pngData(fromTIFF: tiff) {
      return [PendingAttachment(filename: pastedFilename, data: png)]
    }
    return []
  }

  static func pngData(fromTIFF tiff: Data) -> Data? {
    NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
  }
}
