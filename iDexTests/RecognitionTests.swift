import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import iDex

@Suite("Bundled offline Pokémon recognition", .serialized)
@MainActor
struct RecognitionTests {
    @Test("Core ML identifies opaque bundled sprites", arguments: [25, 6])
    func identifiesKnownPokemon(dexID: Int) async throws {
        let sprite = try #require(UIImage(named: String(format: "pokemon-%03d", dexID)))
        let image = try #require(renderOpaque(sprite: sprite))
        let classifier = PokemonClassifier()

        let result = try await classifier.classify(image: image)

        let accepted = try #require(result.accepted)
        #expect(accepted.dexID == dexID)
        #expect(result.candidates.first?.dexID == dexID)
        #expect(result.candidates.count == 3)
        #expect(accepted.confidence >= 0.60)
        #expect(accepted.logit >= 3)
        #expect(result.logitMargin >= 2)
    }

    @Test("Core ML abstains on blank images", arguments: [false, true])
    func rejectsBlankImages(black: Bool) async throws {
        let image = try #require(renderOpaque(sprite: nil, background: black ? .black : .white))
        let result = try await PokemonClassifier().classify(image: image)

        #expect(result.accepted == nil)
        #expect(result.candidates.count == 3)
        #expect(result.candidates.allSatisfy { (1...151).contains($0.dexID) })
        #expect(result.candidates.allSatisfy { $0.confidence.isFinite && (0...1).contains($0.confidence) })
    }

    @Test("Model labels map exactly to the bundled Kanto catalog")
    func labelCoverageMatchesCatalog() throws {
        struct Label: Decodable {
            let id: Int
            let name: String
        }
        let url = try #require(Bundle.main.url(forResource: "pokemon_labels", withExtension: "json"))
        let labels = try JSONDecoder().decode([Label].self, from: Data(contentsOf: url))

        #expect(labels.count == 151)
        #expect(Set(labels.map(\.id)) == Set(PokemonCatalog.shared.entries.map(\.id)))
        #expect(labels.enumerated().allSatisfy { $0.element.id == $0.offset + 1 })
        #expect(labels.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        #expect(labels[24].name == "pikachu")
        #expect(labels[5].name == "charizard")
    }

    // Match the app's sample path: a 96px transparent sprite becomes an opaque
    // white 384px image before Core ML performs its 224px image conversion.
    private func renderOpaque(sprite: UIImage?, background: UIColor = .white) -> CGImage? {
        let size = CGSize(width: 384, height: 384)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.interpolationQuality = .none
            sprite?.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}
