import CoreGraphics
import ImageIO
import Testing
import UIKit
@testable import iDex

@MainActor
struct ScanImagePreparerTests {
    @Test(arguments: Array(1...8))
    func importedOrientationAndCenterCropMatchTheOriginalPhoto(orientation: Int) async throws {
        let data = try encodedImage(width: 120, height: 80, orientation: orientation)
        let original = try #require(UIImage(data: data))
        let side = min(original.size.width, original.size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let expected = try #require(UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            original.draw(in: CGRect(x: (side - original.size.width) / 2, y: (side - original.size.height) / 2,
                                     width: original.size.width, height: original.size.height))
        }.cgImage)

        let prepared = try await ScanImagePreparer.photo(data: data)

        #expect(prepared.width == Int(side))
        #expect(prepared.height == Int(side))
        #expect(try pixels(prepared) == pixels(expected))
    }

    @Test func transparentImportsAreCompositedOnWhite() async throws {
        let context = try makeContext(width: 40, height: 40)
        context.setFillColor(try #require(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [1, 0, 0, 0.5])))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 40))
        let image = try #require(context.makeImage())
        let prepared = try await ScanImagePreparer.photo(data: encode(image))
        let values = try pixels(prepared)

        #expect(values[0] == 255)
        #expect((126...128).contains(values[1]))
        #expect((126...128).contains(values[2]))
        let clearPixel = 30 * 4
        #expect(Array(values[clearPixel..<(clearPixel + 4)]) == [255, 255, 255, 255])
    }

    @Test func highResolutionImportsProduceABoundedSquare() async throws {
        let data = try encodedImage(width: 4000, height: 3000, type: "public.jpeg")
        let prepared = try await ScanImagePreparer.photo(data: data)
        #expect(prepared.width == 1200)
        #expect(prepared.height == 1200)
        #expect(prepared.bytesPerRow * prepared.height <= 1200 * 1200 * 4)
    }

    @Test func panoramaImportsKeepCenterDetailWithinThePixelBudget() async throws {
        let data = try encodedImage(width: 8000, height: 400, type: "public.jpeg")
        let prepared = try await ScanImagePreparer.photo(data: data)
        #expect(prepared.width == 400)
        #expect(prepared.width == prepared.height)
    }

    @Test func largePanoramaDecodingRespectsThePixelBudget() async throws {
        let data = try encodedImage(width: 16000, height: 800, type: "public.jpeg")
        let prepared = try await ScanImagePreparer.photo(data: data)
        #expect((224...458).contains(prepared.width))
        #expect(prepared.width == prepared.height)
    }

    @Test func unreadablePhotosFailWithoutProducingAnImage() async {
        await #expect(throws: ScanError.self) {
            try await ScanImagePreparer.photo(data: Data("unreadable photo".utf8))
        }
    }

    @Test func cancelledImportsStopBeforeDecoding() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ScanImagePreparer.photo(data: Data())
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private func encodedImage(width: Int, height: Int, orientation: Int = 1, type: String = "public.png") throws -> Data {
        let context = try makeContext(width: width, height: height)
        for (index, color) in [CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                               CGColor(red: 0, green: 0, blue: 1, alpha: 1),
                               CGColor(red: 0, green: 1, blue: 0, alpha: 1),
                               CGColor(red: 1, green: 1, blue: 0, alpha: 1)].enumerated() {
            context.setFillColor(color)
            context.fill(CGRect(x: index % 2 * width / 2, y: index / 2 * height / 2, width: width / 2, height: height / 2))
        }
        return try encode(#require(context.makeImage()), orientation: orientation, type: type)
    }

    private func encode(_ image: CGImage, orientation: Int = 1, type: String = "public.png") throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func makeContext(width: Int, height: Int) throws -> CGContext {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let context = try makeContext(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pointer = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pointer, count: image.width * image.height * 4))
    }
}
