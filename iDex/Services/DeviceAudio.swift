import AVFoundation
import Observation
import UIKit

enum DeviceSound {
    case button, scan, success, error, open
}

/// Local PCM chimes and Apple's on-device speech synthesis. No sound files or
/// network requests are needed. A selected system voice may need to be installed
/// in iOS Settings before its first offline use.
@MainActor @Observable
final class DeviceAudio {
    static let shared = DeviceAudio()

    var isSoundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSoundEnabled, forKey: "idex.soundEnabled")
            if !isSoundEnabled {
                stopAll()
            }
        }
    }

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var soundPlayer: AVAudioPlayer?
    @ObservationIgnored private var sessionConfigured = false
    @ObservationIgnored private var activationTask: Task<Bool, Never>?
    @ObservationIgnored private var deactivationTask: Task<Void, Never>?
    @ObservationIgnored private var soundTask: Task<Void, Never>?
    @ObservationIgnored private var speechTask: Task<Void, Never>?
    @ObservationIgnored private var soundGeneration = 0
    @ObservationIgnored private var speechGeneration = 0

    private init() {
        let defaults = UserDefaults.standard
        isSoundEnabled = defaults.object(forKey: "idex.soundEnabled") != nil
            ? defaults.bool(forKey: "idex.soundEnabled") : true
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    func play(_ cue: DeviceSound) {
        switch cue {
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .scan: UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
        case .open: UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.6)
        case .button: UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        }
        guard isSoundEnabled else { return }
        soundGeneration += 1
        let generation = soundGeneration
        soundTask?.cancel()
        soundPlayer?.stop()
        soundTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            guard await self.ensureSession(),
                  !Task.isCancelled, self.isSoundEnabled,
                  generation == self.soundGeneration,
                  UIApplication.shared.applicationState != .background else { return }
            do {
                let player = try AVAudioPlayer(data: Self.wave(for: cue))
                player.volume = 0.32
                player.prepareToPlay()
                self.soundPlayer = player
                player.play()
            } catch {
                // Unavailable audio must not prevent scanning or haptics.
            }
        }
    }

    func speak(_ text: String, languageCode: String) {
        guard isSoundEnabled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        stopSpeaking()
        let generation = speechGeneration
        speechTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            guard await self.ensureSession(),
                  !Task.isCancelled, self.isSoundEnabled,
                  generation == self.speechGeneration,
                  UIApplication.shared.applicationState != .background else { return }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
            utterance.rate = languageCode.hasPrefix("zh") ? 0.43 : 0.46
            utterance.pitchMultiplier = 0.84
            utterance.volume = 0.9
            utterance.preUtteranceDelay = 0.28
            self.synthesizer.speak(utterance)
        }
    }

    func stopSpeaking() {
        speechGeneration += 1
        speechTask?.cancel()
        speechTask = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    func stopAll() {
        soundGeneration += 1
        soundTask?.cancel()
        soundTask = nil
        soundPlayer?.stop()
        soundPlayer = nil
        stopSpeaking()
        releaseSession()
    }

    /// Coalesce simultaneous chime/speech requests onto a single nonblocking
    /// activation. A pending release always finishes before another activation.
    private func ensureSession() async -> Bool {
        if let release = deactivationTask { await release.value }
        if sessionConfigured { return true }
        if let activation = activationTask { return await activation.value }
        let activation = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            } catch {
                self.activationTask = nil
                return false
            }
            let active = await withCheckedContinuation { continuation in
                session.activate(options: []) { activated, error in
                    continuation.resume(returning: activated && error == nil)
                }
            }
            self.sessionConfigured = active
            self.activationTask = nil
            return active
        }
        activationTask = activation
        return await activation.value
    }

    private func releaseSession() {
        guard deactivationTask == nil,
              sessionConfigured || activationTask != nil else { return }
        let pendingActivation = activationTask
        deactivationTask = Task { @MainActor [weak self] in
            // If mute/background arrives mid-activation, release it afterward.
            // Cancelled play/speech requests cannot emit a delayed sound.
            if let activation = pendingActivation { _ = await activation.value }
            guard let self else { return }
            await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().deactivate(options: [.notifyOthersOnDeactivation]) { _, _ in
                    continuation.resume()
                }
            }
            self.sessionConfigured = false
            self.deactivationTask = nil
        }
    }

    nonisolated private static func wave(for cue: DeviceSound) -> Data {
        let notes: [(frequency: Double, duration: Double)]
        switch cue {
        case .button: notes = [(1_046.5, 0.045), (1_568, 0.045)]
        case .scan: notes = [(523.25, 0.065), (783.99, 0.065), (1_046.5, 0.11)]
        case .success: notes = [(659.25, 0.075), (783.99, 0.075), (1_046.5, 0.075), (1_318.5, 0.18)]
        case .error: notes = [(329.63, 0.10), (246.94, 0.15)]
        case .open: notes = [(392, 0.05), (523.25, 0.05), (659.25, 0.10)]
        }
        let sampleRate = 22_050
        var samples = [Int16]()
        for note in notes {
            let count = Int(note.duration * Double(sampleRate))
            for index in 0..<count {
                let time = Double(index) / Double(sampleRate)
                let phase = (time * note.frequency).truncatingRemainder(dividingBy: 1)
                let square = phase < 0.5 ? 0.65 : -0.65
                let triangle = 1 - 4 * abs(phase - 0.5)
                let attack = min(1, Double(index) / 100)
                let release = min(1, Double(count - index) / 200)
                let value = (square * 0.6 + triangle * 0.4) * attack * release
                samples.append(Int16(value * 16_000))
            }
        }
        let byteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        var data = Data()
        func appendString(_ string: String) { data.append(contentsOf: string.utf8) }
        func appendInteger<T: FixedWidthInteger>(_ integer: T) {
            var value = integer.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        appendString("RIFF")
        appendInteger(UInt32(36) + byteCount)
        appendString("WAVEfmt ")
        appendInteger(UInt32(16))
        appendInteger(UInt16(1)) // Linear PCM.
        appendInteger(UInt16(1)) // Mono.
        appendInteger(UInt32(sampleRate))
        appendInteger(UInt32(sampleRate * 2))
        appendInteger(UInt16(2))
        appendInteger(UInt16(16))
        appendString("data")
        appendInteger(byteCount)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
