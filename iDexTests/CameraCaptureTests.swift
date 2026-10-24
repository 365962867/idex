import AVFoundation
import CoreImage
import CoreVideo
import ImageIO
import Testing
@testable import iDex

struct CameraCaptureTests {
    @MainActor @Test func viewfinderLeavesAudioConfigurationToPlayback() {
        let camera = CameraController()
        #expect(!camera.session.automaticallyConfiguresApplicationAudioSession)
    }

    @Test func scanRetainsTheTapTimeFrameWhenNewFramesArrive() throws {
        let frames = CameraFrameBuffer()
        #expect(throws: CameraError.self) { try frames.snapshot() }
        let first = try makeBuffer()
        frames.update(first)
        let captured = try frames.snapshot()
        let next = try makeBuffer()
        frames.update(next)

        #expect(captured.pixels === first)
        #expect(try frames.snapshot().pixels === next)
        frames.clear()
        #expect(throws: CameraError.self) { try frames.snapshot() }
        #expect(captured.pixels === first)
    }

    @Test(arguments: [0, 90, 180, 270])
    func captureUsesTheUprightCenterSquare(rotation: Int) throws {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let source = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 60))
            .composited(over: CIImage(color: .black))
            .cropped(to: CGRect(x: 0, y: 0, width: 100, height: 60))
        let marked = CIImage(color: .red).cropped(to: CGRect(x: 20, y: 30, width: 25, height: 30))
            .composited(over: source)
        let orientations: [Int: CGImagePropertyOrientation] = [0: .up, 90: .right, 180: .down, 270: .left]
        let expectedOrientation = marked.oriented(try #require(orientations[rotation]))
        let extent = expectedOrientation.extent
        let expected = try #require(context.createCGImage(expectedOrientation, from: CGRect(x: extent.midX - 30, y: extent.midY - 30, width: 60, height: 60)))
        let captured = try #require(CameraFrameRenderer.squareImage(marked, rotation: CGFloat(rotation), context: context))

        #expect(captured.width == 60)
        #expect(captured.height == 60)
        #expect(captured.dataProvider?.data as Data? == expected.dataProvider?.data as Data?)
    }

    @Test(arguments: [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
    func nativeYUVFramesRenderAsUprightRGB(format: OSType) throws {
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 64, 48, format,
                                   [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer) == kCVReturnSuccess)
        let pixels = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        for plane in 0..<CVPixelBufferGetPlaneCount(pixels) {
            let base = try #require(CVPixelBufferGetBaseAddressOfPlane(pixels, plane))
            memset(base, 128, CVPixelBufferGetBytesPerRowOfPlane(pixels, plane) * CVPixelBufferGetHeightOfPlane(pixels, plane))
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let captured = try #require(CameraFrameRenderer.squareImage(CIImage(cvPixelBuffer: pixels), rotation: 90, context: context))
        #expect(captured.width == 48)
        #expect(captured.height == 48)
        let rgb = try #require(CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8, bytesPerRow: 48 * 4,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        rgb.draw(captured, in: CGRect(x: 0, y: 0, width: 48, height: 48))
        let bytes = try #require(rgb.data).assumingMemoryBound(to: UInt8.self)
        #expect((120...140).contains(bytes[0]))
        #expect(abs(Int(bytes[0]) - Int(bytes[1])) <= 2)
        #expect(abs(Int(bytes[1]) - Int(bytes[2])) <= 2)
    }

    private func makeBuffer() throws -> CVPixelBuffer {
        var pixels: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, nil, &pixels)
        #expect(status == kCVReturnSuccess)
        return try #require(pixels)
    }
}
