import SwiftUI
import PhotosUI
import Observation

@MainActor @Observable
final class DexStore {
    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "idex.language")
            DeviceAudio.shared.stopSpeaking()
            message = nil
        }
    }
    var selected: Pokemon? {
        didSet { if let selected { UserDefaults.standard.set(selected.id, forKey: "idex.lastViewed") } }
    }
    var isScanning = false
    var message: String?
    var candidates: [RecognitionCandidate] = []
    var capturedImage: UIImage?
    #if targetEnvironment(simulator)
    var useSample = true
    #else
    var useSample = false
    #endif
    var sampleID = 25
    var showingCatalog = false
    var showingSettings = false
    var showingCompactEntry = false
    var confidence: Double?
    var identified = false
    var seenIDs: Set<Int> = []
    let camera = CameraController()
    private let classifier = PokemonClassifier()
    private var operationID = UUID()
    private var isActive = true

    init() {
        PixelFont.register()
        language = UserDefaults.standard.string(forKey: "idex.language").flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
        selected = PokemonCatalog.shared.pokemon(id: UserDefaults.standard.integer(forKey: "idex.lastViewed")) ?? PokemonCatalog.shared.pokemon(id: 25)
        seenIDs = Set(UserDefaults.standard.array(forKey: "idex.seen") as? [Int] ?? [])
    }

    func text(_ en: String, _ zh: String) -> String { language.text(en, zh) }
    var sample: Pokemon? { PokemonCatalog.shared.pokemon(id: sampleID) }
    var entryStatusTitle: String {
        if identified { return text("IDENTIFIED", "已识别") }
        if confidence != nil { return text("BEST MATCH", "最可能匹配") }
        return text("ARCHIVE", "档案")
    }

    func chooseCamera() {
        DeviceAudio.shared.stopSpeaking()
        cancelScan()
        useSample = false
        capturedImage = nil
        confidence = nil
        candidates = []
        message = nil
        identified = false
        camera.start()
        DeviceAudio.shared.play(.button)
    }

    func scan() async {
        guard !isScanning, isActive else { return }
        let operation = UUID()
        operationID = operation
        isScanning = true
        confidence = nil
        message = nil
        candidates = []
        identified = false
        DeviceAudio.shared.stopSpeaking()
        DeviceAudio.shared.play(.scan)
        defer { if operation == operationID { isScanning = false } }
        do {
            let image: CGImage
            if useSample {
                guard let name = sample?.spriteName, let sprite = UIImage(named: name), let cg = sprite.cgImage else { throw ScanError.imageUnavailable }
                // Composite transparent game sprites onto the same neutral background used by image classifiers.
                image = Self.opaqueImage(cg)
            } else {
                image = try await camera.capture()
                guard operation == operationID, isActive else { return }
                capturedImage = UIImage(cgImage: image)
            }
            try await recognize(image, operation: operation)
        } catch {
            guard operation == operationID, isActive else { return }
            message = error is RecognitionError
                ? text("Recognition is unavailable. Restart iDex and try again.", "识别暂不可用，请重启 iDex 后重试。")
                : text("Couldn't scan. Try a photo or enable the camera.", "未能扫描，请导入照片或启用相机。")
            DeviceAudio.shared.play(.error)
        }
    }

    func importPhoto(_ item: PhotosPickerItem) async {
        guard !isScanning, isActive else { return }
        let operation = UUID()
        operationID = operation
        isScanning = true
        confidence = nil
        message = nil
        candidates = []
        identified = false
        DeviceAudio.shared.stopSpeaking()
        DeviceAudio.shared.play(.scan)
        defer { if operation == operationID { isScanning = false } }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let source = UIImage(data: data), let image = Self.orientedImage(source) else { throw ScanError.imageUnavailable }
            guard operation == operationID, isActive else { return }
            camera.stop()
            useSample = false
            capturedImage = UIImage(cgImage: image)
            try await recognize(image, operation: operation)
        } catch {
            guard operation == operationID, isActive else { return }
            message = text("This photo couldn't be read. Choose another image.", "无法读取这张照片，请选择其他图片。")
            DeviceAudio.shared.play(.error)
        }
    }

    private func recognize(_ image: CGImage, operation: UUID) async throws {
        let result = try await classifier.classify(image: image)
        guard operation == operationID, isActive else { return }
        try applyRecognition(result)
    }

    func applyRecognition(_ result: RecognitionResult) throws {
        guard let match = result.candidates.first,
              let pokemon = PokemonCatalog.shared.pokemon(id: match.dexID) else {
            throw RecognitionError.invalidOutput
        }
        candidates = result.candidates
        selected = pokemon
        confidence = match.confidence
        identified = result.accepted != nil
        guard identified else {
            message = text("Best match; low confidence.", "最可能的匹配，置信度较低。")
            DeviceAudio.shared.play(.button)
            return
        }
        message = nil
        seenIDs.insert(pokemon.id)
        UserDefaults.standard.set(seenIDs.sorted(), forKey: "idex.seen")
        DeviceAudio.shared.play(.success)
        speak()
    }

    func browse(_ pokemon: Pokemon) {
        DeviceAudio.shared.stopSpeaking()
        cancelScan()
        selected = pokemon
        confidence = nil
        identified = false
        showingCatalog = false
        DeviceAudio.shared.play(.button)
    }

    func step(_ delta: Int) {
        DeviceAudio.shared.stopSpeaking()
        cancelScan()
        guard let selected else { return }
        let id = ((selected.id - 1 + delta + 151) % 151) + 1
        self.selected = PokemonCatalog.shared.pokemon(id: id)
        confidence = nil
        identified = false
        DeviceAudio.shared.play(.button)
    }

    func cancelScan() {
        operationID = UUID()
        isScanning = false
    }

    func suspend() {
        isActive = false
        cancelScan()
        camera.stop()
        DeviceAudio.shared.stopAll()
    }

    func resume() {
        isActive = true
        if !useSample && capturedImage == nil { camera.start() }
    }

    func speak() {
        guard isActive, let selected else { return }
        DeviceAudio.shared.speak(selected.spokenEntry(in: language), languageCode: language.speechLocale)
    }

    private static func orientedImage(_ image: UIImage) -> CGImage? {
        let side = min(image.size.width, image.size.height)
        let scale = min(1, 1200 / max(1, side))
        let size = CGSize(width: side * scale, height: side * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(x: (side - image.size.width) * scale / 2, y: (side - image.size.height) * scale / 2, width: image.size.width * scale, height: image.size.height * scale))
        }.cgImage
    }

    private static func opaqueImage(_ image: CGImage) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 384, height: 384), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 384, height: 384))
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage: image).draw(in: CGRect(x: 0, y: 0, width: 384, height: 384))
        }.cgImage ?? image
    }
}

enum ScanError: Error { case imageUnavailable }
