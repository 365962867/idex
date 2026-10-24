import Testing
import UIKit
import CoreText
@testable import iDex

@MainActor
struct CatalogTests {
    @Test func catalogIncludesAllOriginalKantoSpecies() {
        let entries = PokemonCatalog.shared.entries
        #expect(entries.map(\.id) == Array(1...151))
        #expect(Set(entries.map(\.englishName)).count == 151)
        #expect(Set(entries.map(\.chineseName)).count == 151)
        #expect(entries.allSatisfy { !$0.englishDescription.isEmpty && !$0.chineseDescription.isEmpty })
        #expect(entries.allSatisfy { !$0.englishGenus.isEmpty && !$0.chineseGenus.isEmpty })
        #expect(entries.allSatisfy { $0.height > 0 && $0.weight > 0 })
        #expect(entries.allSatisfy { $0.stats.count == 6 && $0.stats.allSatisfy { $0.value > 0 } })
        #expect(entries.allSatisfy { (1...2).contains($0.types.count) })
    }

    @Test func spriteAssetsAreBundledForEverySpecies() {
        for pokemon in PokemonCatalog.shared.entries {
            let sprite = UIImage(named: pokemon.spriteName)
            #expect(sprite != nil, "Missing sprite for \(pokemon.englishName)")
            #expect(sprite?.size == CGSize(width: 96, height: 96))
        }
    }

    @Test func bothPixelFontsRegisterFromBundledFiles() {
        PixelFont.register()
        for fontName in [PixelFont.latinName, PixelFont.chineseName] {
            let font = CTFontCreateWithName(fontName as CFString, 12, nil)
            #expect(CTFontCopyPostScriptName(font) as String == fontName)
        }
    }

    @Test func catalogSearchSupportsBothLanguagesAndNumbers() {
        let catalog = PokemonCatalog.shared
        #expect(catalog.search("pIkAcHu", language: .en).map(\.id) == [25])
        #expect(catalog.search("皮卡丘", language: .zhHans).map(\.id) == [25])
        #expect(catalog.search("皮卡丘", language: .en).map(\.id) == [25])
        #expect(catalog.search("#025", language: .en).map(\.id) == [25])
        #expect(catalog.search("  025 \n", language: .zhHans).map(\.id) == [25])
        #expect(catalog.search("", language: .en).count == 151)
        #expect(catalog.search("not a pokemon", language: .en).isEmpty)
    }

    @Test func typeSearchAndSpokenEntriesUseSelectedLanguage() throws {
        let catalog = PokemonCatalog.shared
        let englishFire = catalog.search("fire", language: .en)
        let chineseFire = catalog.search("火", language: .zhHans)
        #expect(!englishFire.isEmpty)
        #expect(englishFire.allSatisfy { $0.types.contains("fire") })
        // Chinese 火 also occurs in 火爆猴 (Primeape), so broad name/type
        // search intentionally includes more than the Fire-type entries.
        #expect(Set(englishFire.map(\.id)).isSubset(of: Set(chineseFire.map(\.id))))
        #expect(chineseFire.contains { $0.id == 57 })
        let pikachu = try #require(catalog.pokemon(id: 25))
        #expect(pikachu.typeNames(in: .en) == ["ELECTRIC"])
        #expect(pikachu.typeNames(in: .zhHans) == ["电"])
        #expect(pikachu.spokenEntry(in: .en).contains("Pikachu"))
        #expect(pikachu.spokenEntry(in: .zhHans).contains("皮卡丘"))
        #expect(pikachu.height == 0.4)
        #expect(pikachu.weight == 6.0)
        #expect(catalog.pokemon(id: 0) == nil)
        #expect(catalog.pokemon(id: 152) == nil)
    }

    @Test func systemCameraPromptHasBothTranslations() throws {
        for (locale, expectedWord) in [("en", "camera"), ("zh-Hans", "相机")] {
            let path = try #require(Bundle.main.path(forResource: locale, ofType: "lproj"))
            let localizedBundle = try #require(Bundle(path: path))
            let text = localizedBundle.localizedString(forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist")
            #expect(text.contains(expectedWord))
        }
    }
}
