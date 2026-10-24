import Testing
import SwiftUI
import Foundation
@testable import iDex

@MainActor
struct iDexTests {
    @Test func openingDuoAddsOnlyLeadingSpace() {
        let folded = DuoGeometry(size: CGSize(width: 466, height: 678))
        let open = DuoGeometry(size: CGSize(width: 951, height: 669))
        #expect(!folded.isOpen)
        #expect(open.isOpen)
        #expect(folded.panelWidth == open.panelWidth)
        #expect(folded.size.width - folded.viewfinder.maxX == open.size.width - open.viewfinder.maxX)
        #expect(folded.viewfinder.size == open.viewfinder.size)
        #expect(folded.viewfinder.minY == open.viewfinder.minY)
        #expect(open.rightOrigin == 485)
    }

    @Test func rotatingTheClosedCoverDoesNotRevealTheInterior() {
        let rotatedCover = DuoGeometry(size: CGSize(width: 678, height: 466), hingeIsOpen: false)
        let openingBeforeDisplayTransition = DuoGeometry(size: CGSize(width: 466, height: 678), hingeIsOpen: true)
        #expect(!rotatedCover.isOpen)
        #expect(!openingBeforeDisplayTransition.isOpen)
    }

    @Test func appDeclaresOnlyTheNativeDuoOrientation() throws {
        let delegate = DexAppDelegate()
        #expect(delegate.application(.shared, supportedInterfaceOrientationsFor: nil) == .portrait)

        // Bundle's keyed lookup resolves device-qualified values. Read the
        // packaged plist itself to check every launch-time declaration.
        let url = try #require(Bundle.main.url(forResource: "Info", withExtension: "plist"))
        let info = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        for key in ["UISupportedInterfaceOrientations", "UISupportedInterfaceOrientations~iphone", "UISupportedInterfaceOrientations~ipad"] {
            let orientations = try #require(info[key] as? [String], "Missing orientation declaration: \(key)")
            #expect(orientations == ["UIInterfaceOrientationPortrait"], "Unexpected orientation support in \(key)")
        }
    }

    @Test func suspendedAppDoesNotScanOrNarrate() async {
        let store = DexStore()
        let originalSeen = store.seenIDs
        store.suspend()
        await store.scan()
        #expect(!store.isScanning)
        #expect(!store.identified)
        #expect(store.seenIDs == originalSeen)
        #expect(store.camera.status == .idle)
    }
}
