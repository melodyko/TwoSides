import SwiftUI

@main
struct TwoSidesApp: App {
    var body: some Scene {
        WindowGroup {
            PartyRootView()
        }
    }
}

struct PartyRootView: View {
    @State private var game: GameEngine
    @State private var camera = CameraController()
    @State private var accessoryEnabled = false
    @State private var accessoryAvailable = false
    @State private var cameraRequested = false
    @State private var deviceClosed = false
    @State private var showPreview = false
    @State private var showExitConfirmation = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        let isTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let engine = isTesting
            ? GameEngine(words: [
                PromptWord("长颈鹿", category: .animals), PromptWord("咖啡", category: .food),
                PromptWord("自拍", category: .actions), PromptWord("雨伞", category: .daily),
                PromptWord("火锅", category: .food), PromptWord("企鹅", category: .animals)
            ], shuffleWords: false)
            : GameEngine()
        if isTesting { engine.settings.duration = 20; engine.settings.roundsPerTeam = 1 }
        if ProcessInfo.processInfo.arguments.contains("--show-game") {
            engine.settings.duration = 90
            engine.startMatch()
        }
        _game = State(initialValue: engine)
        #else
        _game = State(initialValue: GameEngine())
        #endif
    }

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-audience") {
                AudienceView(state: DemoData.audience)
            } else {
                connectedContent
            }
            #else
            connectedContent
            #endif
        }
        .background(PartyTheme.canvas.ignoresSafeArea())
        .preferredColorScheme(isAudienceDisplay ? .dark : .light)
        .tint(PartyTheme.green)
        .sheet(isPresented: $showPreview) { PerspectivePreview() }
        .confirmationDialog("结束这一局？当前比分不会保留。", isPresented: $showExitConfirmation, titleVisibility: .visible) {
            Button("结束并回大厅", role: .destructive) { game.returnToLobby() }
        }
        .task {
            while !Task.isCancelled {
                game.tick()
                do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { game.pause() }
            // Permission prompts temporarily make the scene inactive. Do not cancel
            // their pending camera request; stop only when actually backgrounded.
            if phase == .background { stopCamera() }
            if phase == .active { accessoryEnabled = camera.isRunning && !deviceClosed }
            updateIdleTimer()
        }
        .onChange(of: game.phase) { _, _ in updateIdleTimer() }
        .onChange(of: camera.isRunning) { wasRunning, running in
            if wasRunning && !running { game.pause() }
            accessoryEnabled = running && scenePhase == .active && !deviceClosed
        }
        .onChange(of: accessoryEnabled) { wasEnabled, enabled in
            if wasEnabled && !enabled { game.pause() }
        }
        .onDisappear {
            stopCamera()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    @ViewBuilder private var connectedContent: some View {
        if #available(iOS 27.1, *) {
            mainContent
                .sceneAccessory {
                    CameraCaptureAccessory(isEnabled: $accessoryEnabled) {
                        AudienceView(state: game.audienceState)
                            .preferredColorScheme(.dark)
                    }
                    .onAvailabilityChange { available in
                        if accessoryAvailable && !available { game.pause() }
                        accessoryAvailable = available
                    }
                }
                .onHingeChange { _, context in
                    let closed = context.hinge?.status == .closed
                    deviceClosed = closed
                    if closed {
                        game.pause()
                        stopCamera()
                    } else {
                        // A preview may have been started from the closed-screen
                        // lobby. Opening the inner display makes it eligible again.
                        accessoryEnabled = camera.isRunning && scenePhase == .active
                    }
                }
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        ZStack {
            PartyTheme.canvas.ignoresSafeArea()
            if deviceClosed && game.phase != .lobby {
                VStack(spacing: 0) {
                    AudienceView(state: game.audienceState)
                    Text("展开手机后继续，答案已收好。")
                        .font(.callout).foregroundStyle(PartyTheme.secondary).padding(20)
                }
            } else {
                VStack(spacing: 0) {
                    switch game.phase {
                    case .lobby:
                        LobbyView(game: game, onStart: startMatch, onPreview: { showPreview = true },
                                  onCamera: toggleCamera, cameraEnabled: camera.isRunning, cameraStatus: cameraStatus)
                    case .countdown, .playing, .reveal, .paused:
                        if game.phase == .paused { pauseScreen }
                        else { GameView(game: game, onPause: { game.pause() }) }
                    case .roundSummary, .finished:
                        ResultView(game: game, onNext: {
                            if game.phase == .finished { startMatch() }
                            else { game.startNextTurn() }
                        }, onLobby: { game.returnToLobby() })
                    }
                    if cameraRequested || camera.isRunning { cameraBar }
                }
            }
            if scenePhase != .active && game.phase != .lobby {
                PartyTheme.canvas.ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 20) {
                            TwoFacesMark(size: 90)
                            Text("答案先收好").font(.title2.bold()).foregroundStyle(PartyTheme.ink)
                        }
                    }
            }
        }
    }

    private var pauseScreen: some View {
        ScrollView {
            VStack(spacing: 24) {
                ScoreStrip(scores: game.scores, activeTeam: game.currentTeamIndex)
                Image(systemName: "pause.circle.fill").font(.system(size: 70)).foregroundStyle(PartyTheme.green).padding(.top, 32)
                Text("歇一下，时间停住了").font(.system(.title, design: .rounded).bold()).multilineTextAlignment(.center)
                    .accessibilityIdentifier("pausedTitle")
                Text("还剩 \(game.remainingSeconds) 秒\n把内屏交给比划的人，再继续。")
                    .foregroundStyle(PartyTheme.secondary).multilineTextAlignment(.center).lineSpacing(5)
                Button("继续这一轮") { game.resume() }
                    .buttonStyle(PartyButtonStyle()).accessibilityIdentifier("resumeGame")
                if !camera.isRunning {
                    Button("开启面对面模式", action: toggleCamera)
                        .buttonStyle(PartyButtonStyle(fill: PartyTheme.mint, foreground: PartyTheme.ink))
                }
                if let error = camera.error { Text(error).font(.caption).foregroundStyle(PartyTheme.secondary) }
                Button("结束并回大厅") { showExitConfirmation = true }
                    .frame(minHeight: 44).foregroundStyle(PartyTheme.secondary)
            }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.foregroundStyle(PartyTheme.ink)
    }

    private var cameraBar: some View {
        HStack(spacing: 12) {
            CameraPreview(session: camera.session)
                .frame(width: 76, height: 64)
                .background(PartyTheme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("相机实时预览，不录制")
            VStack(alignment: .leading, spacing: 4) {
                Label(accessoryAvailable && camera.isRunning ? "外屏已就绪" : "面对面模式", systemImage: "camera.fill")
                    .font(.system(.caption, design: .rounded).bold())
                Text(cameraStatus).font(.caption2).foregroundStyle(PartyTheme.secondary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { stopCamera() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel("关闭相机与外屏")
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(PartyTheme.paper)
        .overlay(alignment: .top) { Rectangle().fill(PartyTheme.line).frame(height: 1) }
    }

    private var cameraStatus: String {
        if let error = camera.error { return error }
        if camera.status == .requestingPermission { return "等待相机授权…" }
        if camera.status == .starting { return "正在开启实时预览…" }
        if camera.isRunning {
            return accessoryAvailable
                ? "猜词方看外屏 · 仅实时预览，不录制"
                : "预览已开启；Duo 内屏全屏时可连接外屏。"
        }
        return "Duo 双屏需要相机权限；仅实时预览，不录制。也可先玩单屏版。"
    }

    private func toggleCamera() {
        if camera.isRunning || cameraRequested { stopCamera(); return }
        cameraRequested = true
        Task {
            await camera.start()
            cameraRequested = camera.isRunning
            accessoryEnabled = camera.isRunning && scenePhase == .active && !deviceClosed
        }
    }

    private func startMatch() {
        game.startMatch()
        // A match may be started from the lobby while Duo is already closed;
        // there will be no new hinge event to pause the freshly started timer.
        if deviceClosed || scenePhase != .active { game.pause() }
    }

    private func stopCamera() {
        accessoryEnabled = false
        cameraRequested = false
        camera.stop()
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = scenePhase == .active
            && [.countdown, .playing, .reveal].contains(game.phase)
    }

    private var isAudienceDisplay: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-audience") { return true }
        #endif
        return deviceClosed && game.phase != .lobby
    }
}

enum DemoData {
    static var audience: AudienceState {
        AudienceState(phase: .playing, category: .animals, characterCount: 3,
                      remainingSeconds: 42, countdown: 0, currentTeamIndex: 0,
                      scores: [3, 2], turnNumber: 1, roundCorrectCount: 3,
                      roundSkipCount: 1, lastFeedback: nil)
    }
}

struct PerspectivePreview: View {
    @Environment(\.dismiss) private var dismiss
    @State private var audience = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("选择视角", selection: $audience) {
                    Text("内屏 · 比划方").tag(false)
                    Text("外屏 · 猜词方").tag(true)
                }.pickerStyle(.segmented).padding(20)
                if audience {
                    AudienceView(state: DemoData.audience)
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            TwoFacesMark(size: 70).padding(.top, 20)
                            Text("只有你看得到答案").font(.headline)
                            VStack(spacing: 14) {
                                Text("动物世界 · 3 个字").font(.subheadline)
                                Text("长颈鹿").font(.system(size: 64, weight: .heavy, design: .rounded))
                                Text("用语言或动作描述，别说出题目里的字。")
                                    .font(.callout).multilineTextAlignment(.center)
                            }.padding(28).frame(maxWidth: .infinity)
                                .background(PartyTheme.orange, in: RoundedRectangle(cornerRadius: 28))
                            Text("切换到「外屏 · 猜词方」看看对面的画面。")
                                .font(.callout).foregroundStyle(PartyTheme.secondary)
                        }.padding(24)
                    }
                }
                Text("画面演示 · 不会启动相机")
                    .font(.caption).foregroundStyle(PartyTheme.secondary).padding(16)
            }
            .foregroundStyle(PartyTheme.ink).background(PartyTheme.canvas)
            .navigationTitle("两种视角").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("明白了") { dismiss() } } }
        }
    }
}
