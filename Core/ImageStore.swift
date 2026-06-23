import AppKit

/// Persists captured images to disk and generates downscaled thumbnails.
/// Files are keyed by the owning Memory Object's id so they are easy to relate
/// and clean up. Uses FileSystemManager for the on-disk layout.
enum ImageStore {
    /// Maximum edge length for generated thumbnails.
    private static let thumbnailMaxDimension: CGFloat = 480

    /// Saves the full image as a PNG asset plus a thumbnail.
    /// Returns the on-disk paths (either may be nil if encoding failed).
    static func persist(_ image: NSImage, id: UUID) -> (asset: String?, thumbnail: String?) {
        let fileName = "\(id.uuidString).png"
        var assetPath: String?
        var thumbnailPath: String?

        if let full = pngData(from: image),
           let url = try? FileSystemManager.shared.saveAsset(full, fileName: fileName) {
            assetPath = url.path
        }
        if let thumb = image.resized(maxDimension: thumbnailMaxDimension),
           let data = pngData(from: thumb),
           let url = try? FileSystemManager.shared.saveThumbnail(data, fileName: fileName) {
            thumbnailPath = url.path
        }
        return (assetPath, thumbnailPath)
    }

    /// Generates a thumbnail from an existing image file (e.g. a screenshot).
    static func thumbnail(fromFile path: String, id: UUID) -> String? {
        guard let image = NSImage(contentsOfFile: path),
              let thumb = image.resized(maxDimension: thumbnailMaxDimension),
              let data = pngData(from: thumb),
              let url = try? FileSystemManager.shared.saveThumbnail(data, fileName: "\(id.uuidString).png") else {
            return nil
        }
        return url.path
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

private extension NSImage {
    /// Returns a copy scaled so its longest edge is at most `maxDimension`.
    func resized(maxDimension: CGFloat) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let result = NSImage(size: newSize)
        result.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy, fraction: 1)
        result.unlockFocus()
        return result
    }
}
