import CoreImage
import CoreVideo
import ImageIO
import Testing
@testable import iDex

struct CameraCaptureTests {
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

    private func makeBuffer() throws -> CVPixelBuffer {
        var pixels: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, nil, &pixels)
        #expect(status == kCVReturnSuccess)
        return try #require(pixels)
    }
}
