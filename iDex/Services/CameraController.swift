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
    case notReady, noCamera, configurationFailed, captureFailed, cancelled

    var errorDescription: String? {
        switch self {
        case .notReady: "The camera is not ready."
        case .noCamera: "No camera is available on this device."
        case .configurationFailed: "The camera could not be started."
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
    private(set) var device: AVCaptureDevice?
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
                let device = try await self.worker.start()
                if self.wantsCamera, !Task.isCancelled, generation == self.startGeneration {
                    self.device = device
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

    /// Retain the latest viewfinder frame before suspending. Moving the camera
    /// after the tap cannot change the image being scanned.
    func capture() async throws -> CGImage {
        guard status == .ready else { throw CameraError.notReady }
        let frame = try worker.snapshot()
        return try await worker.render(frame, rotation: captureRotation)
    }

    fileprivate func updateCaptureRotation(_ angle: CGFloat) {
        captureRotation = angle
    }
}

/// Retain just one sensor frame. Rendering happens only on a scan, away from the
/// UI actor; there is no still-photo shutter, autofocus, or encoding delay.
nonisolated private final class CameraSessionWorker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.idex.camera", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "app.idex.camera.frames", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let frames = CameraFrameBuffer()
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var configured = false
    private var device: AVCaptureDevice?
    private var pendingStart: CheckedContinuation<AVCaptureDevice, Error>?

    func start() async throws -> AVCaptureDevice {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if !self.configured { try self.configure() }
                    self.frameQueue.sync { self.frames.clear() }
                    self.pendingStart = continuation
                    if !self.session.isRunning { self.session.startRunning() }
                    guard self.session.isRunning else { throw CameraError.configurationFailed }
                } catch {
                    self.pendingStart = nil
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
        session.sessionPreset = .high
        guard session.canAddInput(input), session.canAddOutput(videoOutput) else {
            throw CameraError.configurationFailed
        }
        session.addInput(input)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
        session.addOutput(videoOutput)
        // Keep sensor pixels unrotated; apply the tap-time capture angle once.
        if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }
        self.device = device
        configured = true
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.frameQueue.sync { self.frames.clear() }
            if let pending = self.pendingStart {
                self.pendingStart = nil
                pending.resume(throwing: CameraError.cancelled)
            }
        }
    }

    func snapshot() throws -> CameraFrame {
        try frames.snapshot()
    }

    func render(_ frame: CameraFrame, rotation: CGFloat) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let result = CameraFrameRenderer.squareImage(
                    CIImage(cvPixelBuffer: frame.pixels), rotation: rotation, context: self.imageContext
                ) else {
                    continuation.resume(throwing: CameraError.captureFailed)
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if frames.update(pixels) {
            queue.async {
                guard let pending = self.pendingStart else { return }
                self.pendingStart = nil
                if let device = self.device { pending.resume(returning: device) }
                else { pending.resume(throwing: CameraError.noCamera) }
            }
        }
    }
}

// Captures own their retained buffer; replacing or clearing the live frame
// cannot mutate a snapshot already handed to recognition.
nonisolated struct CameraFrame: @unchecked Sendable {
    let pixels: CVPixelBuffer
}

nonisolated final class CameraFrameBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CameraFrame?

    @discardableResult func update(_ pixels: CVPixelBuffer) -> Bool {
        lock.withLock {
            let isFirstFrame = latest == nil
            latest = CameraFrame(pixels: pixels)
            return isFirstFrame
        }
    }

    func clear() {
        lock.withLock { latest = nil }
    }

    func snapshot() throws -> CameraFrame {
        try lock.withLock {
            guard let latest else { throw CameraError.notReady }
            return latest
        }
    }
}

nonisolated enum CameraFrameRenderer {
    static func squareImage(_ image: CIImage, rotation: CGFloat, context: CIContext) -> CGImage? {
        // AVFoundation angles are clockwise; Core Image coordinates point up.
        let upright = image.transformed(by: CGAffineTransform(rotationAngle: -rotation * .pi / 180))
        let extent = upright.extent
        let side = floor(min(extent.width, extent.height))
        guard side > 0 else { return nil }
        let crop = CGRect(x: floor(extent.midX - side / 2), y: floor(extent.midY - side / 2), width: side, height: side)
        return context.createCGImage(upright, from: crop)
    }
}

struct CameraPreview: UIViewRepresentable {
    let controller: CameraController

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.onCaptureRotation = { [weak controller] in controller?.updateCaptureRotation($0) }
        view.updateCamera(session: controller.session, device: controller.device)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.updateCamera(session: controller.session, device: controller.device)
    }

    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: ()) {
        uiView.disconnectCamera()
    }
}

@MainActor final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onCaptureRotation: ((CGFloat) -> Void)?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var captureRotationObservation: NSKeyValueObservation?

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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateRotation()
    }

    func updateCamera(session: AVCaptureSession, device: AVCaptureDevice?) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        if let device, rotationCoordinator?.device !== device {
            previewRotationObservation = nil
            captureRotationObservation = nil
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            rotationCoordinator = coordinator
            // AVFoundation delivers both observations on the main queue. Apply
            // them immediately, including display changes with no UI rotation.
            previewRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateRotation() }
            }
            captureRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateRotation() }
            }
        }
        updateRotation()
    }

    func disconnectCamera() {
        previewRotationObservation = nil
        captureRotationObservation = nil
        rotationCoordinator = nil
        onCaptureRotation = nil
        previewLayer.session = nil
    }

    func updateRotation() {
        guard let coordinator = rotationCoordinator else { return }
        // Duo reports .portrait on both displays, but their native rotations
        // differ. The coordinator accounts for the camera and preview layer.
        let rotation = coordinator.videoRotationAngleForHorizonLevelPreview
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(rotation) {
            connection.videoRotationAngle = rotation
        }
        // Photo rotation is relative to the sensor, independently of the layer.
        onCaptureRotation?(coordinator.videoRotationAngleForHorizonLevelCapture)
    }
}
