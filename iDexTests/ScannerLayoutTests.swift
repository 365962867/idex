import SwiftUI
import Testing
import UIKit
@testable import iDex

@MainActor
@Suite(.serialized)
struct ScannerLayoutTests {
    @Test(arguments: [AppLanguage.en, .zhHans])
    func scannerStatesFitCoverAndExpandedLayouts(language: AppLanguage) throws {
        let savedLanguage = UserDefaults.standard.object(forKey: "idex.language")
        let savedViewed = UserDefaults.standard.object(forKey: "idex.lastViewed")
        let soundWasEnabled = DeviceAudio.shared.isSoundEnabled
        DeviceAudio.shared.isSoundEnabled = false
        defer {
            DeviceAudio.shared.isSoundEnabled = soundWasEnabled
            UserDefaults.standard.set(savedLanguage, forKey: "idex.language")
            UserDefaults.standard.set(savedViewed, forKey: "idex.lastViewed")
        }
        let store = DexStore()
        store.language = language
        store.useSample = true
        store.capturedImage = UIImage(named: "pokemon-025")
        let candidate = RecognitionCandidate(dexID: 25, name: "pikachu", confidence: 0.1, logit: 1)

        for size in [CGSize(width: 466, height: 678), CGSize(width: 951, height: 669)] {
            for scanning in [true, false] {
                if !scanning {
                    try store.applyRecognition(RecognitionResult(candidates: [candidate], accepted: nil, logitMargin: 0))
                }
                store.isScanning = scanning
                let renderer = ImageRenderer(content: ContentView(store: store)
                    .frame(width: size.width, height: size.height))
                renderer.scale = 2
                let image = try #require(renderer.uiImage)
                #expect(image.size == size)
                let posture = size.width > 850 ? "expanded" : "cover"
                let state = scanning ? "scanning" : "best-match"
                Attachment.record(image, named: "scanner-\(posture)-\(state)-\(language.rawValue)", as: .png)
            }
            store.rescan()
            store.capturedImage = UIImage(named: "pokemon-025")
        }
        store.suspend()
    }
}
