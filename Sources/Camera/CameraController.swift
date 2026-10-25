import AVFoundation
import Foundation
import Observation

enum CameraStatus: Equatable, Sendable {
    case idle
    case requestingPermission
    case starting
    case running
    case stopped
    case failed
}

/// Owns a preview-only camera session. Call start only after an explicit user action.
/// No audio input, recording output, photo output, or persistent media is created.
@MainActor
@Observable
final class CameraController {
    private(set) var authorization: AVAuthorizationStatus
    private(set) var status: CameraStatus = .idle
    private(set) var isRunning = false
    private(set) var error: String?

    /// For CameraPreview only. Configuration and start/stop belong to the worker.
    var session: AVCaptureSession { worker.session }

    @ObservationIgnored private let worker = CameraSessionWorker()
    @ObservationIgnored private let notifications = CameraNotificationBag()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var wantsRunning = false

    init() {
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        observeFailures()
    }

    func start() async {
        guard !wantsRunning else { return }
        generation += 1
        let request = generation
        wantsRunning = true
        error = nil
        authorization = AVCaptureDevice.authorizationStatus(for: .video)

        #if targetEnvironment(simulator)
        fail("模拟器没有可用相机。请在 iPhone Duo 真机上开启双面模式；模拟器可先体验演示模式。")
        return
        #else
        if authorization == .notDetermined {
            status = .requestingPermission
            _ = await AVCaptureDevice.requestAccess(for: .video)
            authorization = AVCaptureDevice.authorizationStatus(for: .video)
            // A close/background action during the permission sheet cancels this request.
            guard request == generation, wantsRunning else { return }
        }

        guard !Task.isCancelled else {
            stop()
            return
        }

        guard authorization == .authorized else {
            let message = authorization == .restricted
                ? "这台设备的相机访问受到限制，暂时无法开启双面模式。"
                : "尚未获得相机权限。请在系统设置中允许「两面猜」使用相机，再开启双面模式。"
            fail(message)
            return
        }

        status = .starting
        let result: CameraStartResult = await withCheckedContinuation { continuation in
            // Enqueue synchronously on the main actor before suspension. A subsequent
            // stop is therefore always queued after this start, never before it.
            worker.start { continuation.resume(returning: $0) }
        }
        guard request == generation, wantsRunning else { return }
        guard !Task.isCancelled else {
            stop()
            return
        }
        switch result {
        case .running:
            isRunning = true
            status = .running
        case .failure(let message):
            fail(message)
        }
        #endif
    }

    /// Invalidates pending permission/start work immediately, then drains the
    /// serial capture queue. A late completion cannot reopen the session/UI.
    func stop() {
        generation += 1
        wantsRunning = false
        isRunning = false
        status = .stopped
        worker.stop()
    }

    private func fail(_ message: String) {
        generation += 1
        wantsRunning = false
        isRunning = false
        error = message
        status = .failed
        worker.stop()
    }

    private func observeFailures() {
        let center = NotificationCenter.default
        notifications.add(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main
        ) { [weak self] notification in
            let detail = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.wantsRunning else { return }
                self.fail(detail.map { "相机暂时不可用：\($0)" } ?? "相机暂时不可用，请重新开启双面模式。")
            }
        })
        notifications.add(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.wantsRunning else { return }
                self.fail("相机被其他应用或系统中断。请恢复应用后重新开启双面模式。")
            }
        })
    }
}

private enum CameraStartResult: Sendable {
    case running
    case failure(String)
}

/// AVFoundation session configuration is serialized on this queue. The only
/// cross-queue access is attaching its preview layer on the main actor, as
/// required by UIKit. The session is not exposed for callers to mutate.
private final class CameraSessionWorker: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.twosides.camera", qos: .userInitiated)
    private var configured = false

    func start(completion: @escaping @Sendable (CameraStartResult) -> Void) {
        queue.async { [self] in
            do {
                if !configured { try configure() }
                if !session.isRunning { session.startRunning() }
                completion(session.isRunning ? .running : .failure("相机启动失败，请稍后重试。"))
            } catch {
                completion(.failure(error.localizedDescription))
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() throws {
        dispatchPrecondition(condition: .onQueue(queue))
        // On Duo's inner display the rear camera points towards the guesser.
        // A virtual front camera would switch to the inner camera when unfolded
        // and show the clue giver instead. The same rear choice works on iPhone.
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraConfigurationError.noCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }
        guard session.canAddInput(input) else { throw CameraConfigurationError.cannotAddInput }
        session.addInput(input)
        configured = true
    }
}

private enum CameraConfigurationError: LocalizedError {
    case noCamera
    case cannotAddInput

    var errorDescription: String? {
        switch self {
        case .noCamera: "没有找到可用的后置相机。请使用 iPhone Duo 真机开启双面模式。"
        case .cannotAddInput: "无法连接相机，请关闭其他正在使用相机的应用后再试。"
        }
    }
}

/// Keeps observer cleanup out of the main-actor controller's deinitializer.
final class CameraNotificationBag {
    private var tokens: [NSObjectProtocol] = []

    func add(_ token: NSObjectProtocol) { tokens.append(token) }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}
