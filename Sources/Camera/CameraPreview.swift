import AVFoundation
import SwiftUI
import UIKit

/// The controller owns connection and teardown timing. Dismantling never waits
/// for capture and never releases a layer that a capture operation is using.
struct CameraPreview: UIViewRepresentable {
    let controller: CameraController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        context.coordinator.controller.registerPreview(view)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        // Session inspection here would race a pending background start/stop.
    }

    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: Coordinator) {
        coordinator.controller.unregisterPreview(uiView)
    }

    @MainActor
    final class Coordinator {
        // Keep the controller alive through dismantle. Its reconciliation task
        // then retains both controller and view until the hardware has stopped.
        let controller: CameraController
        init(controller: CameraController) { self.controller = controller }
    }
}

@MainActor
final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var cameraID: String?
    private var rotationGeneration = 0
    private var sessionAccessSuspended = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        isAccessibilityElement = true
        accessibilityLabel = "猜词伙伴的实时相机画面，仅预览，不录制"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Called by CameraController with the capture worker idle and stopped.
    func attachStoppedSession(_ session: AVCaptureSession) {
        sessionAccessSuspended = true
        previewLayer.session = session
    }

    /// Called only between background operations, using the prepared device
    /// snapshot instead of reaching into session.inputs from the main thread.
    func configureStoppedRotation(device: AVCaptureDevice) {
        guard cameraID != device.uniqueID else { return }
        rotationGeneration += 1
        let observationGeneration = rotationGeneration
        rotationObservation = nil
        cameraID = device.uniqueID
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.rotationGeneration == observationGeneration else { return }
                self.applyRotation()
            }
        }
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    /// A pure main-actor flag change, safe even while stopRunning is blocked.
    /// Retain the coordinator and observer until capture has actually stopped.
    func suspendSessionAccess() { sessionAccessSuspended = true }

    func resumeSessionAccess() {
        sessionAccessSuspended = false
        applyRotation()
    }

    /// The controller strongly holds this view until the worker has returned
    /// from stopRunning, and prevents a new start until this method finishes.
    func detachStoppedSession() {
        sessionAccessSuspended = true
        rotationGeneration += 1
        rotationObservation = nil
        rotationCoordinator = nil
        cameraID = nil
        previewLayer.session = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        applyRotation()
    }

    private func applyRotation() {
        // Check the flag BEFORE touching connection, session, or coordinator.
        guard !sessionAccessSuspended, window != nil,
              let connection = previewLayer.connection,
              let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview,
              connection.isVideoRotationAngleSupported(angle),
              connection.videoRotationAngle != angle else { return }
        connection.videoRotationAngle = angle
    }
}
