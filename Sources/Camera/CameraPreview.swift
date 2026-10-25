import AVFoundation
import SwiftUI
import UIKit

/// Displays local live video only. It never requests permission or starts capture.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.connect(to: session)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.connect(to: session)
    }

    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: ()) {
        uiView.disconnect()
    }
}

@MainActor
final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var notifications = CameraNotificationBag()
    private var cameraID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        isAccessibilityElement = true
        accessibilityLabel = "猜词伙伴的实时相机画面，仅预览，不录制"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func connect(to session: AVCaptureSession) {
        if previewLayer.session !== session {
            disconnect()
            previewLayer.session = session
            notifications.add(NotificationCenter.default.addObserver(
                forName: AVCaptureSession.didStartRunningNotification, object: session, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.configureRotation() }
            })
        }
        configureRotation()
    }

    func disconnect() {
        notifications = CameraNotificationBag()
        rotationObservation = nil
        rotationCoordinator = nil
        cameraID = nil
        previewLayer.session = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        configureRotation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The coordinator tracks the layer's display and physical camera rotation,
        // including transitions between Duo's inner and outer displays.
        applyRotation()
    }

    private func configureRotation() {
        guard let device = (previewLayer.session?.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        if cameraID != device.uniqueID {
            cameraID = device.uniqueID
            rotationObservation = nil
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            rotationCoordinator = coordinator
            rotationObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]
            ) { [weak self] _, _ in
                // AVFoundation documents delivery on the main queue; an explicit
                // actor hop also satisfies Swift 6's KVO callback isolation.
                Task { @MainActor [weak self] in self?.applyRotation() }
            }
        }
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            // This preview belongs to the clue giver on the inner display and
            // shows the partner across the device, rather than a selfie.
            connection.isVideoMirrored = false
        }
        applyRotation()
    }

    private func applyRotation() {
        guard let connection = previewLayer.connection,
              let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview,
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}
