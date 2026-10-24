import CoreGraphics
import Foundation
import ImageIO

/// Decode only a viewfinder-sized image, off the UI actor. Source bytes remain
/// in memory; orientation and the centered square match the camera scan path.
nonisolated enum ScanImagePreparer {
    static let maximumSide = 1200
    static let maximumDecodedPixelCount = 2048 * 2048

    static func photo(data: Data) async throws -> CGImage {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) {
            try preparePhoto(data: data)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    static func preparePhoto(data: Data) throws -> CGImage {
        try Task.checkCancellation()
        return try autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.doubleValue > 0, height.doubleValue > 0 else {
                throw ScanError.imageUnavailable
            }
            let shortSide = min(width.doubleValue, height.doubleValue)
            let longSide = max(width.doubleValue, height.doubleValue)
            // Bound pixel area instead of the long edge so panoramic imports
            // retain useful detail in their centered square.
            let decodeScale = min(1, Double(maximumSide) / shortSide,
                                  sqrt(Double(maximumDecodedPixelCount) / (longSide * shortSide)))
            let decodedDimension = max(1, floor(longSide * decodeScale))
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: decodedDimension,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw ScanError.imageUnavailable
            }
            try Task.checkCancellation()
            let side = min(maximumSide, image.width, image.height)
            guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw ScanError.imageUnavailable
            }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let scale = Double(side) / Double(min(image.width, image.height))
            let drawWidth = Double(image.width) * scale
            let drawHeight = Double(image.height) * scale
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: (Double(side) - drawWidth) / 2, y: (Double(side) - drawHeight) / 2,
                                           width: drawWidth, height: drawHeight))
            guard let result = context.makeImage() else { throw ScanError.imageUnavailable }
            return result
        }
    }
}
