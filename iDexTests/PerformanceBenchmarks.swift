import Foundation
import Testing
import SwiftUI
import UIKit
import ImageIO
@testable import iDex

@MainActor
@Suite("Repeatable performance workloads", .serialized)
struct PerformanceBenchmarks {
    @Test func catalogSearchWorkload() {
        let catalog = PokemonCatalog.shared
        let queries = ["Pikachu", "皮卡丘", "006", "fire", "水", "not a pokemon"]
        var count = 0
        let start = ContinuousClock.now
        for _ in 0..<100 {
            for language in AppLanguage.allCases {
                for query in queries {
                    count += catalog.search(query, language: language).count
                }
            }
        }
        print("PERFORMANCE catalog 1200 searches: \(start.duration(to: .now)); matches: \(count)")
        #expect(count > 0)
    }

    @Test func photoPreparationWorkload() async throws {
        // Keep the previous UIKit path here as a reference, not in the app.
        // The new path frees the main actor; total decode time is measured too.
        let data: Data = try autoreleasepool {
            let context = try #require(CGContext(data: nil, width: 6000, height: 4000, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.setFillColor(CGColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 6000, height: 4000))
            let image = try #require(context.makeImage())
            let data = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
            return data as Data
        }
        for optimized in [false, true] {
            let started = ContinuousClock.now
            for _ in 0..<5 {
                if optimized {
                    let image = try await ScanImagePreparer.photo(data: data)
                    #expect(image.width == 1200)
                } else {
                    try autoreleasepool {
                        let image = try #require(UIImage(data: data))
                        let side = min(image.size.width, image.size.height)
                        let scale = min(1, 1200 / max(1, side))
                        let size = CGSize(width: side * scale, height: side * scale)
                        let format = UIGraphicsImageRendererFormat()
                        format.scale = 1
                        format.opaque = true
                        let result = UIGraphicsImageRenderer(size: size, format: format).image { context in
                            UIColor.white.setFill()
                            context.fill(CGRect(origin: .zero, size: size))
                            image.draw(in: CGRect(x: (side - image.size.width) * scale / 2, y: (side - image.size.height) * scale / 2,
                                                  width: image.size.width * scale, height: image.size.height * scale))
                        }
                        #expect(result.cgImage?.width == 1200)
                    }
                }
            }
            print("PERFORMANCE photo 5 x 24MP JPEG, optimized=\(optimized): \(started.duration(to: .now))")
        }
    }

    @Test func expandedShellDrawingWorkload() throws {
        var images: [UIImage] = []
        for optimized in [false, true] {
            let started = ContinuousClock.now
            for index in 0..<5 {
                let view = optimized ? AnyView(ShellSurface()) : AnyView(LegacyShellSurface())
                let renderer = ImageRenderer(content: view.frame(width: 951, height: 669))
                renderer.scale = 1
                let image = try #require(renderer.uiImage)
                if index == 0 { images.append(image) }
            }
            print("PERFORMANCE shell 5 expanded renders, optimized=\(optimized): \(started.duration(to: .now))")
        }
        for (index, image) in images.enumerated() {
            Attachment.record(image, named: "shell-\(index)", as: .png)
        }
        #expect(images[0].pngData() == images[1].pngData())
    }

    @Test func sampleScanResultLatency() async {
        let soundWasEnabled = DeviceAudio.shared.isSoundEnabled
        let savedViewed = UserDefaults.standard.object(forKey: "idex.lastViewed")
        let savedSeen = UserDefaults.standard.object(forKey: "idex.seen")
        DeviceAudio.shared.isSoundEnabled = false
        let store = DexStore()
        store.useSample = true
        defer {
            store.suspend()
            DeviceAudio.shared.isSoundEnabled = soundWasEnabled
            UserDefaults.standard.set(savedViewed, forKey: "idex.lastViewed")
            UserDefaults.standard.set(savedSeen, forKey: "idex.seen")
        }
        for iteration in 0..<4 {
            if iteration > 0 { store.rescan() }
            let started = ContinuousClock.now
            await store.scan()
            print("PERFORMANCE sample scan \(iteration), full result latency: \(started.duration(to: .now))")
            #expect(!store.isScanning)
            #expect(store.scannedPokemon?.id == 25)
            #expect(store.identified)
        }
    }
}

private struct LegacyShellSurface: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.91, green: 0.21, blue: 0.24), DexTheme.red, Color(red: 0.55, green: 0.035, blue: 0.065)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { context, size in
                for x in stride(from: 0.0, to: size.width, by: 4) {
                    for y in stride(from: 0.0, to: size.height, by: 4) {
                        let alpha = (Int(x * 7 + y * 13) % 9 == 0) ? 0.10 : 0.025
                        context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(alpha)))
                    }
                }
            }.allowsHitTesting(false)
            ConcentricRectangle().stroke(.black.opacity(0.35), lineWidth: 5).padding(9)
            ConcentricRectangle().stroke(.white.opacity(0.16), lineWidth: 1).padding(12)
        }
    }
}
