import Foundation
import Testing
@testable import iDex

@MainActor
@Suite("Audio startup and lifecycle", .serialized)
struct DeviceAudioTests {
    @Test func speakingStateFollowsPlaybackAndIgnoresReplacedUtterances() async throws {
        let backend = AudioPlaybackSpy()
        let audio = DeviceAudio(worker: backend, defaults: isolatedDefaults())
        audio.resume()
        audio.speak("Pikachu", languageCode: "en-US")
        #expect(await waitUntil { backend.spokenCount == 1 })
        let first = try #require(backend.latestSpeechRequest)
        // Queuing speech and its pre-utterance delay must leave the bulb off.
        #expect(!audio.isSpeaking)
        first.reportSpeechActivity(true)
        #expect(await waitUntil { audio.isSpeaking })
        first.reportSpeechActivity(false)
        #expect(await waitUntil { !audio.isSpeaking })

        audio.speak("Bulbasaur", languageCode: "en-US")
        #expect(await waitUntil { backend.spokenCount == 2 })
        let second = try #require(backend.latestSpeechRequest)
        second.reportSpeechActivity(true)
        #expect(await waitUntil { audio.isSpeaking })
        first.reportSpeechActivity(false)
        await Task.yield()
        #expect(audio.isSpeaking)
        // Also reject an already queued callback after an explicit stop.
        second.reportSpeechActivity(true)
        audio.stopSpeaking()
        await Task.yield()
        #expect(!audio.isSpeaking)
        audio.suspend()
    }

    @Test(arguments: [true, false])
    func mutingOrSuspendingExtinguishesSpeechImmediately(mute: Bool) async throws {
        let backend = AudioPlaybackSpy()
        let audio = DeviceAudio(worker: backend, defaults: isolatedDefaults())
        audio.resume()
        audio.speak("Pikachu", languageCode: "en-US")
        #expect(await waitUntil { backend.spokenCount == 1 })
        let request = try #require(backend.latestSpeechRequest)
        request.reportSpeechActivity(true)
        #expect(await waitUntil { audio.isSpeaking })
        if mute { audio.isSoundEnabled = false }
        else { audio.suspend() }
        #expect(!audio.isSpeaking)
        request.reportSpeechActivity(true)
        await Task.yield()
        #expect(!audio.isSpeaking)
        audio.suspend()
    }

    @Test func becomingActivePreparesSoundBeforeTheFirstScanOrSpeech() async {
        let backend = AudioPlaybackSpy()
        let defaults = isolatedDefaults()
        let audio = DeviceAudio(worker: backend, defaults: defaults)
        audio.resume()
        #expect(await audio.prepare())
        #expect(backend.activationCount == 1)
        #expect(backend.spokenCount == 0)
        audio.play(.button)
        #expect(await waitUntil { backend.played == [.button] })
        audio.play(.scan)
        #expect(await waitUntil { backend.played == [.button, .scan] })
        #expect(backend.activationCount == 1)
        #expect(backend.spokenCount == 0)
        audio.suspend()
        #expect(await waitUntil { backend.deactivationCount == 1 })
    }

    @Test func firstButtonJoinsStartupAndDoesNotNeedRecognitionToEnableAudio() async {
        let backend = AudioPlaybackSpy(deferredActivation: true)
        let audio = DeviceAudio(worker: backend, defaults: isolatedDefaults())
        audio.resume()
        #expect(await waitUntil { backend.activationCount == 1 })
        audio.play(.button)
        #expect(backend.played.isEmpty)
        backend.completeActivation()
        #expect(await waitUntil { backend.played == [.button] })
        #expect(backend.spokenCount == 0)
        audio.suspend()
        #expect(await waitUntil { backend.deactivationCount == 1 })
    }

    @Test func mutingDuringStartupCancelsTheOldCueAndUnmutingPreparesAgain() async {
        let backend = AudioPlaybackSpy(deferredActivation: true)
        let audio = DeviceAudio(worker: backend, defaults: isolatedDefaults())
        audio.resume()
        #expect(await waitUntil { backend.activationCount == 1 })
        audio.play(.scan)
        audio.isSoundEnabled = false
        backend.completeActivation()
        #expect(await waitUntil { backend.deactivationCount == 1 })
        #expect(backend.played.isEmpty)
        audio.isSoundEnabled = true
        #expect(await waitUntil { backend.activationCount == 2 })
        audio.play(.button)
        backend.completeActivation()
        #expect(await waitUntil { backend.played == [.button] })
        #expect(backend.spokenCount == 0)
        audio.suspend()
        #expect(await waitUntil { backend.deactivationCount == 2 })
    }

    @Test func foregroundingAfterSuspendRestoresTheFirstCueWithoutSpeech() async {
        let backend = AudioPlaybackSpy()
        let audio = DeviceAudio(worker: backend, defaults: isolatedDefaults())
        audio.resume()
        #expect(await audio.prepare())
        audio.suspend()
        #expect(await waitUntil { backend.deactivationCount == 1 })
        audio.play(.button)
        #expect(backend.played.isEmpty)
        audio.resume()
        #expect(await audio.prepare())
        audio.play(.button)
        #expect(await waitUntil { backend.played == [.button] })
        #expect(backend.activationCount == 2)
        #expect(backend.spokenCount == 0)
        audio.suspend()
        #expect(await waitUntil { backend.deactivationCount == 2 })
    }

    private func isolatedDefaults() -> UserDefaults {
        // A volatile domain avoids changing the phone's actual sound setting.
        let defaults = UserDefaults(suiteName: "idex-audio-tests-\(UUID())")!
        defaults.setVolatileDomain(["idex.soundEnabled": true], forName: UserDefaults.registrationDomain)
        return defaults
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

nonisolated private final class AudioPlaybackSpy: DeviceAudioPlayback, @unchecked Sendable {
    private let lock = NSLock()
    private let deferredActivation: Bool
    private var activations = 0
    private var deactivations = 0
    private var cues: [DeviceSound] = []
    private var speechCount = 0
    private var speechRequest: AudioPlaybackRequest?
    private var pending: [CheckedContinuation<Bool, Never>] = []

    init(deferredActivation: Bool = false) { self.deferredActivation = deferredActivation }
    var activationCount: Int { lock.withLock { activations } }
    var deactivationCount: Int { lock.withLock { deactivations } }
    var played: [DeviceSound] { lock.withLock { cues } }
    var spokenCount: Int { lock.withLock { speechCount } }
    var latestSpeechRequest: AudioPlaybackRequest? { lock.withLock { speechRequest } }

    func activate() async -> Bool {
        await withCheckedContinuation { continuation in
            let immediate = lock.withLock {
                activations += 1
                if deferredActivation { pending.append(continuation) }
                return !deferredActivation
            }
            if immediate { continuation.resume(returning: true) }
        }
    }

    func completeActivation() {
        let continuations = lock.withLock {
            let saved = pending
            pending = []
            return saved
        }
        for continuation in continuations { continuation.resume(returning: true) }
    }

    func deactivate() async { lock.withLock { deactivations += 1 } }
    func play(_ cue: DeviceSound, request: AudioPlaybackRequest) {
        guard !request.isCancelled else { return }
        lock.withLock { cues.append(cue) }
    }
    func speak(_ text: String, languageCode: String, request: AudioPlaybackRequest) {
        guard !request.isCancelled else { return }
        lock.withLock {
            speechCount += 1
            speechRequest = request
        }
    }
    func stopSound() {}
    func stopSpeaking() {}
}
