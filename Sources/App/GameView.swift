import SwiftUI

struct GameView: View {
    @Bindable var game: GameEngine
    var onPause: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var answerSize: CGFloat = 56

    var body: some View {
        GeometryReader { geometry in
            if #available(iOS 27.1, *),
               let division = geometry.reservedRegions(
                kind: .division,
                options: [.includeInactive],
                layoutDirectionBehavior: .fixed
               ).first,
               let panes = divisionPanes(frame: division.frame, size: geometry.size) {
                // The API reports local coordinates and already includes safety margins.
                // Each independently scrolling pane is clipped before the reserved region.
                ZStack {
                    promptPane(size: panes.first.size)
                        .position(x: panes.first.midX, y: panes.first.midY)
                    controlPane(size: panes.second.size)
                        .position(x: panes.second.midX, y: panes.second.midY)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                standardLayout(size: geometry.size)
            }
        }
        .foregroundStyle(PartyTheme.ink)
    }

    private func standardLayout(size: CGSize) -> some View {
        let wide = size.width > 650 && !typeSize.isAccessibilitySize
        return ScrollView {
            if wide && size.height < 520 {
                HStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        wordCard(minHeight: 200, compact: true)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 14) {
                        ScoreStrip(scores: game.scores, activeTeam: game.currentTeamIndex)
                        controls(compact: true)
                    }
                    .frame(width: min(320, size.width * 0.40))
                }
                .frame(maxWidth: 1080)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: size.height)
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    ScoreStrip(scores: game.scores, activeTeam: game.currentTeamIndex)
                    if wide {
                        HStack(alignment: .center, spacing: 28) {
                            wordCard(minHeight: 330)
                                .frame(maxWidth: .infinity)
                            controls()
                                .frame(width: min(320, size.width * 0.34))
                        }
                    } else {
                        wordCard(minHeight: 280)
                        controls()
                    }
                }
                .frame(maxWidth: 1080)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func promptPane(size: CGSize) -> some View {
        let compact = size.height < 420 && !typeSize.isAccessibilitySize
        return ScrollView {
            VStack(alignment: .leading, spacing: compact ? 12 : 20) {
                header
                wordCard(minHeight: compact ? 180 : max(260, size.height - 170), compact: compact)
            }
            .padding(compact ? 16 : 24)
            .frame(minHeight: size.height, alignment: .center)
        }
        .scrollIndicators(.hidden)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func controlPane(size: CGSize) -> some View {
        let horizontalButtons = size.width > 500 && !typeSize.isAccessibilitySize
        return ScrollView {
            VStack(spacing: 20) {
                ScoreStrip(scores: game.scores, activeTeam: game.currentTeamIndex)
                controls(horizontalButtons: horizontalButtons)
            }
            .frame(maxWidth: 680)
            .padding(size.height < 420 ? 16 : 24)
            .frame(maxWidth: .infinity, minHeight: size.height, alignment: .center)
        }
        .scrollIndicators(.hidden)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// Keep calculations in the same local coordinates as the querying GeometryReader.
    /// Inactive divisions may have zero thickness, so CGRect.intersection would lose them.
    private func divisionPanes(frame: CGRect, size: CGSize) -> (first: CGRect, second: CGRect)? {
        let first: CGRect
        let second: CGRect
        if frame.height > frame.width {
            let leftEnd = min(size.width, max(0, frame.minX))
            let rightStart = min(size.width, max(0, frame.maxX))
            first = CGRect(x: 0, y: 0, width: leftEnd, height: size.height)
            second = CGRect(x: rightStart, y: 0, width: size.width - rightStart, height: size.height)
        } else {
            let topEnd = min(size.height, max(0, frame.minY))
            let bottomStart = min(size.height, max(0, frame.maxY))
            first = CGRect(x: 0, y: 0, width: size.width, height: topEnd)
            second = CGRect(x: 0, y: bottomStart, width: size.width, height: size.height - bottomStart)
        }
        guard first.width > 1, first.height > 1, second.width > 1, second.height > 1 else { return nil }
        return (first, second)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("第 \(game.roundNumber) / \(game.totalTurns / 2) 轮")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(PartyTheme.secondary)
                Text("\(game.currentTeamName)，接招！")
                    .font(.system(.title2, design: .rounded).weight(.heavy))
            }
            Spacer(minLength: 0)
            Button(action: onPause) {
                Image(systemName: "pause.fill")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .frame(width: 48, height: 48)
                    .background(PartyTheme.paper, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(game.phase == .paused)
            .accessibilityLabel("暂停游戏")
            .accessibilityIdentifier("gamePause")
        }
    }

    private func wordCard(minHeight: CGFloat, compact: Bool = false) -> some View {
        VStack(spacing: compact ? 12 : 20) {
            switch game.phase {
            case .countdown:
                Label("准备好描述了吗？", systemImage: "hand.wave")
                    .font(.system(.headline, design: .rounded))
                Text("\(game.countdown)")
                    .font(.system(size: compact ? 76 : 104, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .accessibilityLabel("准备倒计时 \(game.countdown)")
                Text("让队友看向另一面")
                    .font(.system(.subheadline, design: .rounded))
            case .playing, .reveal:
                if let word = game.currentWord {
                    HStack(spacing: 8) {
                        Label(word.category.title, systemImage: word.category.symbol)
                        Text("·")
                        Text("\(word.characterCount) 个字")
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))

                    Text(word.answer)
                        .font(.system(size: answerSize, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.65)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("描述者词卡：\(word.answer)")
                        .accessibilityIdentifier("promptAnswer")

                    if let feedback = game.lastFeedback {
                        Label(
                            feedback == .correct ? "漂亮，+1！" : "换一个，再来！",
                            systemImage: feedback == .correct ? "checkmark.circle.fill" : "arrow.forward.circle.fill"
                        )
                        .font(.system(.headline, design: .rounded))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(PartyTheme.paper.opacity(0.72), in: Capsule())
                    } else {
                        Text("可以描述、比划，别说出词里的字哦")
                            .font(.system(.subheadline, design: .rounded))
                            .multilineTextAlignment(.center)
                    }
                }
            case .paused:
                Image(systemName: "pause.circle")
                    .font(.system(size: 64, weight: .light))
                    .accessibilityHidden(true)
                Text("暂停中")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                Text("词卡已收好，准备好了再继续。")
                    .font(.system(.subheadline, design: .rounded))
                    .multilineTextAlignment(.center)
            default:
                TwoFacesMark(size: 70)
                Text("词卡准备中")
                    .font(.system(.title2, design: .rounded).weight(.bold))
            }
        }
        .padding(compact ? 18 : 24)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 28))
    }

    private var cardColor: Color {
        switch game.phase {
        case .countdown: PartyTheme.mint
        case .paused: PartyTheme.paper
        default: PartyTheme.orange
        }
    }

    private func controls(horizontalButtons: Bool = false, compact: Bool = false) -> some View {
        VStack(spacing: compact ? 10 : 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "timer")
                    .font(.system(.title2, design: .rounded))
                    .accessibilityHidden(true)
                Text("\(game.remainingSeconds)")
                    .font(.system(size: compact ? 32 : 42, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("秒")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("本回合")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(PartyTheme.secondary)
                    Text("答对 \(game.roundCorrectCount) 题")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                }
            }
            .foregroundStyle(game.remainingSeconds <= 10 && game.phase != .countdown ? PartyTheme.danger : PartyTheme.ink)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("剩余 \(game.remainingSeconds) 秒，本回合答对 \(game.roundCorrectCount) 题")

            if horizontalButtons {
                HStack(spacing: 14) {
                    correctButton()
                    skipButton(minHeight: 88)
                }
            } else {
                correctButton(minHeight: compact ? 64 : 88)
                skipButton(minHeight: compact ? 48 : 64)
            }

            if !compact {
                Text("跳过不扣分，放轻松！")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(PartyTheme.secondary)
            }
        }
    }

    private func correctButton(minHeight: CGFloat = 88) -> some View {
        Button { game.markCorrect() } label: {
            Label("答对了  +1", systemImage: "checkmark")
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .frame(minHeight: minHeight)
        }
        .buttonStyle(PartyButtonStyle())
        .disabled(game.phase != .playing)
        .accessibilityLabel("答对了，加一分")
        .accessibilityIdentifier("gameCorrect")
    }

    private func skipButton(minHeight: CGFloat) -> some View {
        Button { game.skip() } label: {
            Label("跳过这一题", systemImage: "arrow.right")
                .frame(minHeight: minHeight)
        }
        .buttonStyle(PartyButtonStyle(fill: PartyTheme.paper, foreground: PartyTheme.ink))
        .disabled(game.phase != .playing)
        .accessibilityIdentifier("gameSkip")
    }
}
