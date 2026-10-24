import Testing
import SwiftUI
import Foundation
@testable import iDex

@MainActor
@Suite(.serialized)
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
        let controller = DexHostingController(rootView: ContentView())
        #expect(controller.prefersInterfaceOrientationLocked)
        #expect(controller.supportedInterfaceOrientations == .portrait)
        #expect(controller.preferredInterfaceOrientationForPresentation == .portrait)
        #expect(controller.prefersStatusBarHidden)
        #expect(controller.prefersHomeIndicatorAutoHidden)

        // Bundle's keyed lookup resolves device-qualified values. Read the
        // packaged plist itself to check every launch-time declaration.
        let url = try #require(Bundle.main.url(forResource: "Info", withExtension: "plist"))
        let info = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        for key in ["UISupportedInterfaceOrientations", "UISupportedInterfaceOrientations~iphone", "UISupportedInterfaceOrientations~ipad"] {
            let orientations = try #require(info[key] as? [String], "Missing orientation declaration: \(key)")
            #expect(orientations == ["UIInterfaceOrientationPortrait"], "Unexpected orientation support in \(key)")
        }
    }

    @Test func connectedSceneUsesTheExplicitOrientationLock() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let delegate = try #require(scene.delegate as? DexSceneDelegate)
        #expect(delegate.supportedInterfaceOrientations(for: scene) == .portrait)
        #expect(delegate.window?.rootViewController is DexHostingController)
        #expect(scene.effectiveGeometry.isInterfaceOrientationLocked)
    }

    @Test func presentationsKeepTheSceneOrientationLocked() async throws {
        let soundWasEnabled = DeviceAudio.shared.isSoundEnabled
        DeviceAudio.shared.isSoundEnabled = false
        defer { DeviceAudio.shared.isSoundEnabled = soundWasEnabled }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let delegate = try #require(scene.delegate as? DexSceneDelegate)
        let root = try #require(delegate.window?.rootViewController)
        for keyPath in [\DexStore.showingCompactEntry, \.showingCatalog, \.showingSettings] {
            delegate.store[keyPath: keyPath] = true
            defer { delegate.store[keyPath: keyPath] = false }
            for _ in 0..<50 {
                if let presented = root.presentedViewController, presented.viewIfLoaded?.window != nil, presented.transitionCoordinator == nil { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(root.presentedViewController != nil)
            #expect(scene.effectiveGeometry.isInterfaceOrientationLocked)
            #expect(root.presentedViewController?.childForHomeIndicatorAutoHidden == nil)
            #expect(root.presentedViewController?.prefersHomeIndicatorAutoHidden == true)
            delegate.store[keyPath: keyPath] = false
            for _ in 0..<50 {
                if root.presentedViewController == nil { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(root.presentedViewController == nil)
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
