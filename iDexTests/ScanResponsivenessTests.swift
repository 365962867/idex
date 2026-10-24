import Foundation
import SwiftUI
import Testing
import UIKit
@testable import iDex

@MainActor
@Suite("Scan and speech responsiveness", .serialized)
struct ScanResponsivenessTests {
    @Test(arguments: [AppLanguage.en, .zhHans])
    func fullScanKeepsRenderingThroughSpeechStartup(language: AppLanguage) async throws {
        try await exerciseScan(language: language, useCamera: false)
    }

    #if !targetEnvironment(simulator)
    @Test func cameraScanKeepsRenderingThroughSpeechStartup() async throws {
        try await exerciseScan(language: .zhHans, useCamera: true)
    }
    #endif

    private func exerciseScan(language: AppLanguage, useCamera: Bool) async throws {
        await DeviceAudio.shared.suspend()?.value
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let sceneStore = (scene.delegate as? DexSceneDelegate)?.store
        sceneStore?.suspend()
        let savedLanguage = UserDefaults.standard.object(forKey: "idex.language")
        let savedViewed = UserDefaults.standard.object(forKey: "idex.lastViewed")
        let savedSeen = UserDefaults.standard.object(forKey: "idex.seen")
        let defaults = UserDefaults(suiteName: "idex-responsiveness-\(UUID())")!
        defaults.setVolatileDomain(["idex.soundEnabled": true], forName: UserDefaults.registrationDomain)
        let worker = AudioPlaybackWorker(soundVolume: 0, speechVolume: 0)
        let audio = DeviceAudio(worker: worker, defaults: defaults)
        let store = DexStore(audio: audio)
        store.useSample = !useCamera
        store.language = language
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = DexHostingController(rootView: ContentView(store: store))
        window.makeKeyAndVisible()
        defer {
            store.suspend()
            window.isHidden = true
            previousWindow?.makeKey()
            UserDefaults.standard.set(savedLanguage, forKey: "idex.language")
            UserDefaults.standard.set(savedViewed, forKey: "idex.lastViewed")
            UserDefaults.standard.set(savedSeen, forKey: "idex.seen")
            DeviceAudio.shared.resume()
            sceneStore?.resume()
        }
        store.resume()
        if useCamera {
            for _ in 0..<200 {
                if store.camera.status == .ready { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            try #require(store.camera.status == .ready)
        }
        let probe = DisplayFrameProbe()
        let displayLink = CADisplayLink(target: probe, selector: #selector(DisplayFrameProbe.tick))
        displayLink.add(to: .main, forMode: .common)
        defer { displayLink.invalidate() }
        try await Task.sleep(for: .milliseconds(100))

        let started = ContinuousClock.now
        await store.scan()
        try #require(store.scanResult != nil)
        print("SCAN RESPONSE \(language.rawValue) camera=\(useCamera) result: \(started.duration(to: .now))")
        if !useCamera { #expect(store.identified) }
        // A live scene may abstain. Exercise the explicit Read action in that
        // case, preserving the rule against automatically narrating uncertainty.
        if !store.identified { store.speak() }
        for _ in 0..<500 {
            if audio.isSpeaking { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        print("SCAN RESPONSE \(language.rawValue) speech start: \(started.duration(to: .now)); speaking=\(audio.isSpeaking)")
        #expect(audio.isSpeaking)
        try await Task.sleep(for: .seconds(2))
        store.rescan()
        if useCamera {
            for _ in 0..<200 {
                if store.camera.status == .ready { break }
                try await Task.sleep(for: .milliseconds(25))
            }
        }
        await store.scan()
        try #require(store.scanResult != nil)
        if !store.identified { store.speak() }
        for _ in 0..<500 {
            if audio.isSpeaking { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(audio.isSpeaking)
        try await Task.sleep(for: .seconds(2))
        audio.stopSpeaking()
        #expect(!audio.isSpeaking)
        try await Task.sleep(for: .milliseconds(250))
        print("SCAN RESPONSE \(language.rawValue) frames=\(probe.frames), max gap=\(probe.maximumGap), gaps over 100ms=\(probe.longGaps)")
        #expect(probe.frames > 30)
        #expect(probe.maximumGap < 0.1)
        await audio.suspend()?.value
    }
}

@MainActor
private final class DisplayFrameProbe: NSObject {
    private var last = CACurrentMediaTime()
    private(set) var frames = 0
    private(set) var maximumGap: TimeInterval = 0
    private(set) var longGaps = 0

    @objc func tick() {
        let now = CACurrentMediaTime()
        let gap = now - last
        maximumGap = max(maximumGap, gap)
        if gap > 0.1 { longGaps += 1 }
        frames += 1
        last = now
    }
}
