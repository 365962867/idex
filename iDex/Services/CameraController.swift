import AVFoundation
import CoreImage
import ImageIO
import Observation
import SwiftUI
import UIKit

enum CameraStatus: Equatable {
    case idle, requesting, ready, denied, unavailable
}

enum CameraError: LocalizedError {
    case notReady, noCamera, configurationFailed, captureInProgress, captureFailed, cancelled

    var errorDescription: String? {
        switch self {
        case .notReady: "The camera is not ready."
        case .noCamera: "No camera is available on this device."
        case .configurationFailed: "The camera could not be started."
        case .captureInProgress: "A capture is already in progress."
        case .captureFailed: "The photo could not be captured."
        case .cancelled: "The capture was cancelled."
        }
    }
}

/// Camera ownership stays outside the foldable layout so opening the device never
/// destroys or restarts the capture session. Present `CameraPreview` in a square.
@MainActor @Observable
final class CameraController {
    private(set) var status: CameraStatus = .idle
    private(set) var error: CameraError?
    @ObservationIgnored private let worker = CameraSessionWorker()
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var wantsCamera = false
    @ObservationIgnored private var captureRotation: CGFloat = 90
    @ObservationIgnored private var startGeneration = 0

    var session: AVCaptureSession { worker.session }

    func start() {
        wantsCamera = true
        guard startTask == nil, status != .ready else { return }
        status = .requesting
        error = nil
        startGeneration += 1
        let generation = startGeneration
        startTask = Task { [weak self] in
            guard let self else { return }
            let authorized: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: authorized = true
            case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
            default: authorized = false
            }
            guard self.wantsCamera, !Task.isCancelled, generation == self.startGeneration else {
                if generation == self.startGeneration { self.startTask = nil }
                return
            }
            guard authorized else {
                self.status = .denied
                self.startTask = nil
                return
            }
            do {
                try await self.worker.start()
                if self.wantsCamera, !Task.isCancelled, generation == self.startGeneration {
                    self.status = .ready
                } else if !self.wantsCamera {
                    self.worker.stop()
                }
            } catch {
                if self.wantsCamera, !Task.isCancelled, generation == self.startGeneration {
                    self.error = (error as? CameraError) ?? .configurationFailed
                    self.status = .unavailable
                }
            }
            if generation == self.startGeneration { self.startTask = nil }
        }
    }

    func stop() {
        wantsCamera = false
        startGeneration += 1
        startTask?.cancel()
        startTask = nil
        worker.stop()
        status = .idle
    }

    /// Returned pixels have their EXIF orientation applied, then the exact center
    /// square is cropped, matching the aspect-fill preview's visible region.
    func capture() async throws -> CGImage {
        guard status == .ready else { throw CameraError.notReady }
        return try await worker.capture(rotation: captureRotation)
    }

    fileprivate func updateCaptureRotation(_ angle: CGFloat) {
        captureRotation = angle
    }
}

/// All session configuration, start/stop, and capture work is serialized away
/// from the main thread. The delegate only transfers results back to this queue.
nonisolated private final class CameraSessionWorker: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.idex.camera", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var configured = false
    private var pendingCapture: CheckedContinuation<CGImage, Error>?
    private var pendingCaptureID: Int64?

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if !self.configured { try self.configure() }
                    if !self.session.isRunning { self.session.startRunning() }
                    guard self.session.isRunning else { throw CameraError.configurationFailed }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video) else { throw CameraError.noCamera }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            throw CameraError.configurationFailed
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .balanced
        configured = true
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            if let pending = self.pendingCapture {
                self.pendingCapture = nil
                self.pendingCaptureID = nil
                pending.resume(throwing: CameraError.cancelled)
            }
        }
    }

    func capture(rotation: CGFloat) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.session.isRunning else {
                    continuation.resume(throwing: CameraError.notReady)
                    return
                }
                guard self.pendingCapture == nil else {
                    continuation.resume(throwing: CameraError.captureInProgress)
                    return
                }
                guard let connection = self.photoOutput.connection(with: .video) else {
                    continuation.resume(throwing: CameraError.captureFailed)
                    return
                }
                if connection.isVideoRotationAngleSupported(rotation) {
                    connection.videoRotationAngle = rotation
                }
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .balanced
                self.pendingCapture = continuation
                self.pendingCaptureID = settings.uniqueID
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        let captureID = photo.resolvedSettings.uniqueID
        queue.async {
            guard let continuation = self.pendingCapture,
                  self.pendingCaptureID == captureID else { return }
            self.pendingCapture = nil
            self.pendingCaptureID = nil
            guard error == nil, let data,
                  let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
                continuation.resume(throwing: error ?? CameraError.captureFailed)
                return
            }
            let extent = image.extent
            let side = floor(min(extent.width, extent.height))
            let crop = CGRect(x: floor(extent.midX - side / 2), y: floor(extent.midY - side / 2), width: side, height: side)
            guard let result = self.imageContext.createCGImage(image, from: crop) else {
                continuation.resume(throwing: CameraError.captureFailed)
                return
            }
            continuation.resume(returning: result)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard let error else { return }
        let captureID = resolvedSettings.uniqueID
        queue.async {
            guard let continuation = self.pendingCapture,
                  self.pendingCaptureID == captureID else { return }
            self.pendingCapture = nil
            self.pendingCaptureID = nil
            continuation.resume(throwing: error)
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let controller: CameraController

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = controller.session
        view.onCaptureRotation = { [weak controller] in controller?.updateCaptureRotation($0) }
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        if uiView.previewLayer.session !== controller.session {
            uiView.previewLayer.session = controller.session
        }
        uiView.updateRotation()
    }
}

@MainActor final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onCaptureRotation: ((CGFloat) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black
        isAccessibilityElement = true
        accessibilityIdentifier = "camera.preview"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateRotation()
    }

    func updateRotation() {
        guard let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation else { return }
        let rotation: CGFloat
        switch orientation {
        case .portrait: rotation = 90
        case .portraitUpsideDown: rotation = 270
        case .landscapeLeft: rotation = 180
        case .landscapeRight: rotation = 0
        default: rotation = 90
        }
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(rotation) {
            connection.videoRotationAngle = rotation
        }
        onCaptureRotation?(rotation)
    }
}
