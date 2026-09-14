import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ConversionError: LocalizedError {
    case invalidImage, unsupportedImage, decodeFailed, encodeFailed
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法读取图片，文件可能已损坏。"
        case .unsupportedImage: return "请选择 HEIF 或 HEIC 图片。"
        case .decodeFailed: return "系统无法解码这张 HEIF 图片。"
        case .encodeFailed: return "PNG 编码失败。"
        }
    }
}

struct ConversionResult {
    let url: URL
    let width: Int
    let height: Int
    let bytes: Int
}

enum Converter {
    static func convert(_ input: URL, to directory: URL? = nil) throws -> ConversionResult {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { throw ConversionError.invalidImage }
        guard let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier),
              type.conforms(to: .heic) || type.conforms(to: .heif) else {
            throw ConversionError.unsupportedImage
        }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        guard let width = properties?[kCGImagePropertyPixelWidth] as? Int,
              let height = properties?[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw ConversionError.decodeFailed }
        // Decode the primary image at full size and bake its orientation into the pixels.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            throw ConversionError.decodeFailed
        }
        let folder = directory ?? input.deletingLastPathComponent()
        let temporary = folder.appendingPathComponent(".heif-png-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ConversionError.encodeFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.encodeFailed }

        let name = input.deletingPathExtension().lastPathComponent
        var suffix = 0
        var output: URL
        repeat {
            output = folder.appendingPathComponent(name + (suffix == 0 ? "" : " (\(suffix))") + ".png")
            suffix += 1
        } while FileManager.default.fileExists(atPath: output.path)
        // moveItem refuses to replace an existing file, including a concurrent writer's file.
        try FileManager.default.moveItem(at: temporary, to: output)
        let bytes = (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.intValue ?? 0
        return ConversionResult(url: output, width: image.width, height: image.height, bytes: bytes)
    }
}
