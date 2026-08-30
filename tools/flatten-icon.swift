// Flatten an app icon's alpha channel onto an opaque background.
//
// App Store Connect rejects a 1024x1024 marketing icon that carries an alpha
// channel -- "The app icon can't be transparent or contain an alpha channel" --
// and Xcode does not catch it, so the failure arrives after the upload. This
// composites the icon over an opaque colour and writes it back with no alpha.
//
//   swift tools/flatten-icon.swift <in.png> <out.png> [size]
//
// The background is sampled from the image's own top-left pixel rather than
// hardcoded: the icon is a wordmark on a solid field, and guessing white would
// have put a white ring around a black icon.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: flatten-icon.swift <in.png> <out.png> [size]\n".utf8))
    exit(2)
}
let inURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])

guard let source = CGImageSourceCreateWithURL(inURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("cannot read \(inURL.path)\n".utf8))
    exit(1)
}

let size = args.count >= 4 ? (Int(args[3]) ?? image.width) : image.width

// Sample the top-left pixel for the background colour.
var pixel: [UInt8] = [0, 0, 0, 0]
let sampleSpace = CGColorSpaceCreateDeviceRGB()
if let sample = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
                          bytesPerRow: 4, space: sampleSpace,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
    sample.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
}
let alpha = CGFloat(pixel[3]) / 255
// A fully transparent corner means the icon has no field of its own; black is
// the app's own background and the least surprising thing to put behind it.
let background = alpha > 0.5
    ? CGColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
              blue: CGFloat(pixel[2]) / 255, alpha: 1)
    : CGColor(red: 0, green: 0, blue: 0, alpha: 1)

guard let context = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    FileHandle.standardError.write(Data("cannot create context\n".utf8))
    exit(1)
}
let rect = CGRect(x: 0, y: 0, width: size, height: size)
context.setFillColor(background)
context.fill(rect)
context.interpolationQuality = .high
context.draw(image, in: rect)

guard let flattened = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write(Data("cannot write \(outURL.path)\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(destination, flattened, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("write failed\n".utf8))
    exit(1)
}
print("wrote \(outURL.lastPathComponent) at \(size)x\(size), no alpha")
