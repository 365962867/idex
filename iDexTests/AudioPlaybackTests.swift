import Foundation
import Testing
import UIKit
@testable import iDex

@MainActor
@Suite("Nonblocking native audio", .serialized)
struct AudioPlaybackTests {
    @Test func stoppingUnusedAudioDoesNotInitializeSpeech() async {
        let worker = AudioPlaybackWorker(soundVolume: 0, speechVolume: 0)
        worker.stopSound()
        worker.stopSpeaking()
        let status = await worker.status()
        #expect(!status.hasSpeechSynthesizer)
        #expect(status.cachedSoundCount == 0)
        #expect(!status.isOnMainThread)
        #expect(!status.hasSwiftTask)
    }

    @Test func cancelledRequestsCannotStartSoundOrSpeech() async {
        let worker = AudioPlaybackWorker(soundVolume: 0, speechVolume: 0)
        let sound = AudioPlaybackRequest()
        let speech = AudioPlaybackRequest()
        sound.cancel()
        speech.cancel()
        worker.play(.scan, request: sound)
        worker.speak("Pikachu", languageCode: "en-US", request: speech)
        let status = await worker.status()
        #expect(!status.soundIsPlaying)
        #expect(!status.speechIsSpeaking)
        #expect(!status.hasSpeechSynthesizer)
        #expect(status.cachedSoundCount == 0)
    }

    @Test func scanSoundCanBeStoppedAndReusesItsPreparedPlayer() async throws {
        await DeviceAudio.shared.suspend()?.value
        defer { DeviceAudio.shared.resume() }
        let worker = AudioPlaybackWorker(soundVolume: 0, speechVolume: 0)
        #expect(await worker.activate())
        for _ in 0..<2 {
            let request = AudioPlaybackRequest()
            worker.play(.scan, request: request)
            let playing = await worker.status()
            #expect(playing.soundIsPlaying)
            #expect(playing.cachedSoundCount == DeviceSound.allCases.count)
            request.cancel()
            worker.stopSound()
            #expect(await !worker.status().soundIsPlaying)
        }
        await worker.deactivate()
    }

    @Test func silentNativeStartupAllowsTheMainActorToKeepRunning() async throws {
        await DeviceAudio.shared.suspend()?.value
        defer { DeviceAudio.shared.resume() }
        let worker = AudioPlaybackWorker(soundVolume: 0, speechVolume: 0)
        #expect(await worker.activate())
        var ticks = 0
        var maximumGap: Duration = .zero
        var lastTick = ContinuousClock.now
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                let now = ContinuousClock.now
                maximumGap = max(maximumGap, lastTick.duration(to: now))
                lastTick = now
                ticks += 1
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        let started = ContinuousClock.now
        worker.play(.success, request: AudioPlaybackRequest())
        worker.speak("Pikachu. Pokédex number 25.", languageCode: "en-US", request: AudioPlaybackRequest())
        let status = await worker.status()
        heartbeat.cancel()
        _ = try? await heartbeat.value
        print("AUDIO worker startup: \(started.duration(to: .now)); main actor ticks: \(ticks); maximum gap: \(maximumGap)")
        #expect(status.cachedSoundCount == DeviceSound.allCases.count)
        #expect(status.hasSpeechSynthesizer)
        #expect(!status.isOnMainThread)
        #expect(!status.hasSwiftTask)
        #expect(ticks > 0)
        worker.stopSound()
        worker.stopSpeaking()
        // The speech service acknowledges stopping asynchronously.
        var stopped = false
        for _ in 0..<100 {
            if await !worker.status().speechIsSpeaking { stopped = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(stopped)
        await worker.deactivate()
    }

    @Test func firstButtonAndScanPlayBeforeAnySpeech() async throws {
        await DeviceAudio.shared.suspend()?.value
        defer { DeviceAudio.shared.resume() }
        #if !targetEnvironment(simulator)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let camera = try #require((scene.delegate as? DexSceneDelegate)?.store.camera)
        for _ in 0..<100 {
            if camera.status == .ready { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(camera.status == .ready)
        print("FIRST AUDIO physical camera: \(camera.status)")
        #endif
        let worker = AudioPlaybackWorker(soundVolume: 0, speechVolume: 0)
        let defaults = UserDefaults(suiteName: "idex-first-audio-\(UUID())")!
        defaults.setVolatileDomain(["idex.soundEnabled": true], forName: UserDefaults.registrationDomain)
        let audio = DeviceAudio(worker: worker, defaults: defaults)
        audio.resume()
        #expect(await audio.prepare())
        let prepared = await worker.status()
        #expect(prepared.cachedSoundCount == DeviceSound.allCases.count)
        #expect(!prepared.hasSpeechSynthesizer)
        #expect(prepared.renderedFrames > 0)
        for cue in [DeviceSound.button, .scan] {
            let beforeSignal = await worker.status().renderedSignalFrames
            let started = ContinuousClock.now
            audio.play(cue)
            var playing = await worker.status()
            for _ in 0..<100 {
                if playing.soundIsPlaying { break }
                try await Task.sleep(for: .milliseconds(5))
                playing = await worker.status()
            }
            print("FIRST AUDIO prepared \(cue) start: \(started.duration(to: .now)); route=\(playing.outputPorts)")
            #expect(playing.soundIsPlaying)
            #expect(!playing.hasSpeechSynthesizer)
            var progressed = await worker.status()
            for _ in 0..<200 {
                if progressed.renderedSignalFrames > beforeSignal { break }
                try await Task.sleep(for: .milliseconds(5))
                progressed = await worker.status()
            }
            print("FIRST AUDIO \(cue) rendered signal frames: \(progressed.renderedSignalFrames - beforeSignal)")
            #expect(progressed.renderedSignalFrames > beforeSignal)
            #expect(!progressed.hasSpeechSynthesizer)
            worker.stopSound()
        }
        await audio.suspend()?.value
    }
}
