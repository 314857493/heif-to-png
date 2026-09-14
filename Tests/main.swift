import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func check(_ condition: Bool, _ message: String) {
    if !condition { fatalError("FAIL: \(message)") }
    print("PASS: \(message)")
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let custom = root.appendingPathComponent("converted", isDirectory: true)
try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
let width = 120, height = 80
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 60, height: 80))
context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
context.fill(CGRect(x: 60, y: 0, width: 60, height: 80))
let image = context.makeImage()!

func write(_ url: URL, type: UTType = .heic, orientation: Int = 1) throws {
    let encoder = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(encoder, image, [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
    check(CGImageDestinationFinalize(encoder), "encode fixture \(url.lastPathComponent)")
}

for orientation in 1...8 {
    let input = root.appendingPathComponent("照片方向-\(orientation).HEIC")
    try write(input, orientation: orientation)
    let original = try Data(contentsOf: input)
    let result = try Converter.convert(input, to: custom)
    check(result.width == (orientation >= 5 ? height : width) && result.height == (orientation >= 5 ? width : height), "orientation \(orientation) retains full dimensions")
    let png = CGImageSourceCreateWithURL(result.url as CFURL, nil)!
    check(CGImageSourceGetType(png) as String? == UTType.png.identifier, "output is real PNG")
    check(try Data(contentsOf: input) == original, "original unchanged")
    if orientation == 6 {
        let decoded = CGImageSourceCreateImageAtIndex(png, 0, nil)!
        let pixels = CGContext(data: nil, width: decoded.width, height: decoded.height, bitsPerComponent: 8, bytesPerRow: decoded.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pixels.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
        let data = pixels.data!.assumingMemoryBound(to: UInt8.self)
        let top = (10 * decoded.width + 40) * 4
        let bottom = (100 * decoded.width + 40) * 4
        check(data[top] > 230 && data[top+2] < 25 && data[bottom+2] > 230 && data[bottom] < 25, "orientation 6 rotates red/blue pixels correctly")
    }
}
let input = root.appendingPathComponent("照片方向-1.HEIC")
let existing = custom.appendingPathComponent("照片方向-1.png")
let old = try Data(contentsOf: existing)
let again = try Converter.convert(input, to: custom)
check(again.url.lastPathComponent == "照片方向-1 (1).png", "duplicate gets numbered filename")
check(try Data(contentsOf: existing) == old, "existing PNG not overwritten")
let beside = try Converter.convert(input)
check(beside.url.deletingLastPathComponent() == root, "default output beside original")
let corrupt = root.appendingPathComponent("broken.heic")
try Data("not an image".utf8).write(to: corrupt)
do { _ = try Converter.convert(corrupt); fatalError("accepted corrupt file") }
catch { print("PASS: corrupt file rejected") }
let disguised = root.appendingPathComponent("actually-png.heic")
try write(disguised, type: .png)
do { _ = try Converter.convert(disguised); fatalError("accepted PNG input") }
catch ConversionError.unsupportedImage { print("PASS: content type checked") }
let leftovers = try FileManager.default.contentsOfDirectory(atPath: custom.path).filter { $0.hasSuffix(".tmp") }
check(leftovers.isEmpty, "temporary files cleaned up")
print("All conversion checks passed.")
