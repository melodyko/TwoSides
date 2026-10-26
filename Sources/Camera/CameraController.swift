import AVFoundation
import Foundation
import Observation

enum CameraStatus: Equatable, Sendable {
    case idle
    case requestingPermission
    case starting
    case running
    case stopping
    case stopped
    case failed
}

/// Coordinates the preview and capture queue. Only this object may attach or
/// detach a preview; neither operation overlaps a background capture operation.
@MainActor
@Observable
final class CameraController {
    private(set) var authorization: AVAuthorizationStatus
    private(set) var status: CameraStatus = .idle
    /// Remains true during shutdown until stopRunning has actually returned.
    private(set) var isRunning = false
    private(set) var error: String?

    @ObservationIgnored private let worker = CameraSessionWorker()
    @ObservationIgnored private let notifications = CameraNotificationBag()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var wantsRunning = false
    @ObservationIgnored private var mustStop = false
    @ObservationIgnored private var backendRunning = false
    @ObservationIgnored private var backendBusy = false
    @ObservationIgnored private var preparedDevice: CameraDeviceReference?
    @ObservationIgnored private var previews: [ObjectIdentifier: PreviewRegistration] = [:]
    @ObservationIgnored private var reconciliationTask: Task<Void, Never>?
    @ObservationIgnored private var reconciliationNeeded = false
    @ObservationIgnored private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init() {
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        observeFailures()
    }

    /// Call only after an explicit user action. A registered CameraPreview must
    /// be mounted while starting. Closing or dismantling it cancels this request.
    func start() async {
        if wantsRunning {
            await waitForStart(generation)
            return
        }
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
            guard request == generation, wantsRunning else { return }
        }
        guard !Task.isCancelled else {
            cancelStart(request)
            return
        }
        guard authorization == .authorized else {
            fail(authorization == .restricted
                 ? "这台设备的相机访问受到限制，暂时无法开启双面模式。"
                 : "尚未获得相机权限。请在系统设置中允许「两面猜」使用相机，再开启双面模式。")
            return
        }
        if !mustStop { status = .starting }
        await waitForStart(request)
        #endif
    }

    /// Records the latest intent immediately. Preview teardown and the final
    /// stopped state wait for the serialized background stop to finish.
    func stop() {
        guard wantsRunning || backendBusy || backendRunning || status == .requestingPermission else { return }
        generation += 1
        wantsRunning = false
        mustStop = backendBusy || backendRunning
        status = mustStop ? .stopping : .stopped
        suspendPreviews()
        finishStartWaiters()
        scheduleReconciliation()
    }

    /// Strong ownership is intentional: SwiftUI may discard a UIView while
    /// stopRunning is still in flight. Keep its layer and KVO objects alive.
    func registerPreview(_ view: CameraPreviewView) {
        let id = ObjectIdentifier(view)
        guard previews[id] == nil else { return }
        previews[id] = PreviewRegistration(view: view)
        scheduleReconciliation()
    }

    /// No AVFoundation graph mutation or KVO destruction occurs in dismantle.
    func unregisterPreview(_ view: CameraPreviewView) {
        let id = ObjectIdentifier(view)
        guard var entry = previews[id], entry.wanted else { return }
        entry.wanted = false
        previews[id] = entry
        view.suspendSessionAccess()
        if !previews.values.contains(where: \.wanted) {
            // Losing the last visible preview also cancels permission/start work.
            stop()
        }
        scheduleReconciliation()
    }

    private func waitForStart(_ request: Int) async {
        guard request == generation, wantsRunning, !isRunning || mustStop else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard request == generation, wantsRunning else {
                    continuation.resume()
                    return
                }
                startWaiters.append((request, continuation))
                scheduleReconciliation()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelStart(request) }
        }
    }

    private func cancelStart(_ request: Int) {
        if request == generation { stop() }
    }

    private func finishStartWaiters() {
        let waiters = startWaiters
        startWaiters.removeAll()
        for (_, continuation) in waiters { continuation.resume() }
    }

    private func scheduleReconciliation() {
        reconciliationNeeded = true
        guard reconciliationTask == nil else { return }
        reconciliationTask = Task { @MainActor in
            while self.reconciliationNeeded {
                self.reconciliationNeeded = false
                await self.reconcile()
            }
            self.reconciliationTask = nil
        }
    }

    /// The only driver of prepare/start/stop. Main-actor preview changes happen
    /// only between completed worker operations, never while one is in flight.
    private func reconcile() async {
        while true {
            let graphChanged = previews.values.contains { !$0.wanted || !$0.connected }
            let hasPreview = previews.values.contains(where: \.wanted)
            if backendRunning && (mustStop || !wantsRunning || graphChanged || !hasPreview) {
                backendBusy = true
                status = .stopping
                suspendPreviews()
                await withCheckedContinuation { continuation in
                    worker.stop { continuation.resume() }
                }
                backendBusy = false
                backendRunning = false
                isRunning = false
                mustStop = false
                continue
            }

            if !backendRunning {
                // This pass runs synchronously on the main actor. No queued
                // start can begin until the entire preview graph change finishes.
                reconcileStoppedPreviews()
                mustStop = false
                guard wantsRunning else {
                    status = error == nil ? .stopped : .failed
                    finishStartWaiters()
                    return
                }
                guard authorization == .authorized else { return }
                guard previews.values.contains(where: \.wanted) else {
                    status = .starting
                    return
                }
                if preparedDevice == nil {
                    let request = generation
                    status = .starting
                    backendBusy = true
                    suspendPreviews()
                    let result: CameraPreparationResult = await withCheckedContinuation { continuation in
                        worker.prepare(generation: request) { continuation.resume(returning: $0) }
                    }
                    backendBusy = false
                    switch result {
                    case .prepared(let device): preparedDevice = device
                    case .failure(let message):
                        if request == generation, wantsRunning { fail(message) }
                    }
                    continue
                }
                for entry in previews.values where entry.wanted {
                    entry.view.configureStoppedRotation(device: preparedDevice!.device)
                }
                let request = generation
                status = .starting
                backendBusy = true
                suspendPreviews()
                let result: CameraStartResult = await withCheckedContinuation { continuation in
                    worker.start(generation: request) { continuation.resume(returning: $0) }
                }
                backendBusy = false
                switch result {
                case .running: backendRunning = true
                case .failure(let message):
                    if request == generation, wantsRunning { fail(message) }
                }
                continue
            }

            // Only publish success after applying the latest intent and removing
            // retired views. A cancelled start never briefly reopens the UI.
            for entry in previews.values where entry.wanted {
                entry.view.resumeSessionAccess()
            }
            isRunning = true
            status = .running
            finishStartWaiters()
            return
        }
    }

    private func reconcileStoppedPreviews() {
        assert(!backendBusy && !backendRunning, "Preview graph changes require an idle, stopped capture worker")
        for (id, entry) in previews where !entry.wanted {
            entry.view.detachStoppedSession()
            previews.removeValue(forKey: id)
        }
        for (id, var entry) in previews where entry.wanted && !entry.connected {
            entry.view.attachStoppedSession(worker.session)
            entry.connected = true
            previews[id] = entry
        }
    }

    private func suspendPreviews() {
        for entry in previews.values { entry.view.suspendSessionAccess() }
    }

    private func fail(_ message: String) {
        error = message
        generation += 1
        wantsRunning = false
        mustStop = backendBusy || backendRunning
        status = mustStop ? .stopping : .failed
        suspendPreviews()
        finishStartWaiters()
        scheduleReconciliation()
    }

    private func observeFailures() {
        let center = NotificationCenter.default
        let worker = worker
        // A non-nil OperationQueue can make the posting AVFoundation thread
        // wait for main. Receive inline, copy values, and hop asynchronously.
        notifications.add(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: worker.session, queue: nil
        ) { [weak self] notification in
            let request = worker.eventGeneration
            let detail = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.wantsRunning, request == self.generation else { return }
                self.fail(detail.map { "相机暂时不可用：\($0)" } ?? "相机暂时不可用，请重新开启双面模式。")
            }
        })
        notifications.add(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification, object: worker.session, queue: nil
        ) { [weak self] _ in
            let request = worker.eventGeneration
            Task { @MainActor [weak self] in
                guard let self, self.wantsRunning, request == self.generation else { return }
                self.fail("相机被其他应用或系统中断。请恢复应用后重新开启双面模式。")
            }
        })
    }

    private struct PreviewRegistration {
        let view: CameraPreviewView
        var wanted = true
        var connected = false
    }
}

/// The device handle is shared only for main-actor RotationCoordinator reads.
/// All capture configuration remains owned by CameraSessionWorker's queue.
private struct CameraDeviceReference: @unchecked Sendable {
    let device: AVCaptureDevice
}

private enum CameraPreparationResult: Sendable {
    case prepared(CameraDeviceReference)
    case failure(String)
}

private enum CameraStartResult: Sendable {
    case running
    case failure(String)
}

/// Mutable session state is owned by this serial queue. The controller attaches
/// previews on main only while this worker is idle. The generation lock is used
/// solely to tag notifications at their posting time; it never spans AV calls.
private final class CameraSessionWorker: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.twosides.camera", qos: .userInitiated)
    private let generationLock = NSLock()
    private var operationGeneration = 0
    private var device: AVCaptureDevice?

    var eventGeneration: Int { generationLock.withLock { operationGeneration } }

    func prepare(generation: Int, completion: @escaping @Sendable (CameraPreparationResult) -> Void) {
        queue.async { [self] in
            generationLock.withLock { operationGeneration = generation }
            do {
                if device == nil { try configure() }
                guard let device else { throw CameraConfigurationError.noCamera }
                completion(.prepared(CameraDeviceReference(device: device)))
            } catch {
                completion(.failure(error.localizedDescription))
            }
        }
    }

    func start(generation: Int, completion: @escaping @Sendable (CameraStartResult) -> Void) {
        queue.async { [self] in
            generationLock.withLock { operationGeneration = generation }
            if !session.isRunning { session.startRunning() }
            completion(session.isRunning ? .running : .failure("相机启动失败，请稍后重试。"))
        }
    }

    func stop(completion: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            completion()
        }
    }

    private func configure() throws {
        dispatchPrecondition(condition: .onQueue(queue))
        // Rear wide points towards the guesser when Duo's inner display is open.
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraConfigurationError.noCamera
        }
        let input = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard session.canAddInput(input) else { throw CameraConfigurationError.cannotAddInput }
        session.addInput(input)
        device = camera
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

final class CameraNotificationBag {
    private var tokens: [NSObjectProtocol] = []
    func add(_ token: NSObjectProtocol) { tokens.append(token) }
    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}
