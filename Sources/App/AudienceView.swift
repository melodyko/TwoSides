import SwiftUI

/// The outward-facing screen can only receive this answer-free value snapshot.
/// Never give this view a GameEngine, PromptWord, or round history.
struct AudienceView: View {
    let state: AudienceState

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLive: Bool {
        [.countdown, .playing, .reveal, .paused].contains(state.phase)
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontal = geometry.size.width > geometry.size.height * 1.2
                && !typeSize.isAccessibilitySize
            let compact = geometry.size.height < 800
            ScrollView {
                VStack(spacing: horizontal ? 16 : compact ? 14 : 18) {
                    header
                    if horizontal {
                        HStack(spacing: 28) {
                            cue(compact: true)
                                .frame(maxWidth: .infinity)
                            VStack(spacing: 18) {
                                timer(compact: true)
                                scoreBoard
                            }
                            .frame(width: max(180, min(260, geometry.size.width * 0.33)))
                        }
                    } else {
                        Spacer(minLength: 0)
                        cue(compact: compact)
                            .frame(maxWidth: .infinity)
                        Spacer(minLength: 0)
                        timer(compact: compact)
                        scoreBoard
                    }
                    Text(footerText)
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(PartyTheme.mint)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, horizontal ? 28 : 22)
                .padding(.vertical, horizontal ? 18 : 24)
                .frame(maxWidth: 850)
                .frame(minHeight: max(0, geometry.size.height))
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(PartyTheme.paper)
        .background(PartyTheme.ink.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("audienceScreen")
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: state.phase)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                audienceLabel
                Spacer(minLength: 8)
                teamBadge
            }
            VStack(spacing: 10) {
                audienceLabel
                teamBadge
            }
        }
    }

    private var audienceLabel: some View {
        Label("猜词这一面", systemImage: "eye")
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(PartyTheme.mint)
            .fixedSize()
    }

    private var teamBadge: some View {
        HStack(spacing: 7) {
            Circle().fill(PartyTheme.teamColor(state.currentTeamIndex)).frame(width: 8, height: 8)
            Text(state.currentTeamName)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(PartyTheme.paper.opacity(0.09), in: Capsule())
        .accessibilityLabel("当前队伍：\(state.currentTeamName)")
    }

    @ViewBuilder
    private func cue(compact: Bool) -> some View {
        switch state.phase {
        case .playing:
            wordHint(compact: compact)
        case .countdown:
            VStack(spacing: compact ? 8 : 14) {
                Text("看好你的搭档")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text("\(max(1, state.countdown))")
                    .font(.system(size: compact ? 100 : 148, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PartyTheme.orange)
                    .contentTransition(.numericText())
                    .accessibilityLabel("准备倒计时，\(max(1, state.countdown))")
                Text("马上开始猜！")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(PartyTheme.mint)
            }
        case .reveal:
            message(
                symbol: state.lastFeedback == .correct ? "checkmark" : "arrow.right",
                title: state.lastFeedback == .correct ? "答对啦！" : "换个词！",
                subtitle: state.lastFeedback == .correct ? "漂亮，拿下 1 分" : "没关系，跳过不扣分",
                compact: compact,
                highlight: state.lastFeedback == .correct
            )
        case .paused:
            message(symbol: "pause.fill", title: "歇一小会儿", subtitle: "时间已暂停，等搭档继续", compact: compact)
        case .lobby:
            VStack(spacing: compact ? 16 : 24) {
                TwoFacesMark(size: compact ? 72 : 96)
                Text("你来猜\n搭档来比划")
                    .font(.system(size: compact ? 32 : 40, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                Text("只管大胆说出你的答案")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(PartyTheme.mint)
            }
        case .roundSummary:
            message(
                symbol: "hands.clap.fill", title: "这一轮，漂亮！",
                subtitle: "猜对 \(state.roundCorrectCount) 个 · 跳过 \(state.roundSkipCount) 个\n换下一队上场吧",
                compact: compact, highlight: true
            )
        case .finished:
            message(
                symbol: "flag.checkered",
                title: state.wordPoolExhausted ? "这组词猜完啦！" : winnerTitle,
                subtitle: state.wordPoolExhausted ? "本局提前结束，已出现的词不会重复" : "默契已收获，下次再来！",
                compact: compact, highlight: true
            )
        }
    }

    private func wordHint(compact: Bool) -> some View {
        VStack(spacing: compact ? 16 : 24) {
            Text("这一题的线索是")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(PartyTheme.mint)
            VStack(spacing: compact ? 14 : 20) {
                Image(systemName: state.category?.symbol ?? "questionmark")
                    .font(.system(size: compact ? 32 : 42, weight: .medium))
                    .accessibilityHidden(true)
                Text(state.category?.title ?? "准备猜词")
                    .font(.system(size: compact ? 35 : 44, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                    .accessibilityIdentifier("audienceCategory")
                if let count = state.characterCount, count > 0 {
                    VStack(spacing: 10) {
                        // Dots communicate length without ever receiving the answer.
                        if count <= 8 {
                            HStack(spacing: 9) {
                                ForEach(0..<count, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(PartyTheme.ink.opacity(0.5))
                                        .frame(width: compact ? 14 : 18, height: 5)
                                }
                            }
                            .accessibilityHidden(true)
                        }
                        Text("\(count) 个字")
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .accessibilityIdentifier("audienceCharacterCount")
                    }
                }
            }
            .foregroundStyle(PartyTheme.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, compact ? 22 : 30)
            .frame(maxWidth: .infinity)
            .background(PartyTheme.orange, in: RoundedRectangle(cornerRadius: 28))
            Text("听描述 · 看动作 · 放心猜")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(PartyTheme.mint)
        }
    }

    private func message(symbol: String, title: String, subtitle: String, compact: Bool, highlight: Bool = false) -> some View {
        VStack(spacing: compact ? 14 : 22) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 38 : 52, weight: .bold))
                .foregroundStyle(highlight ? PartyTheme.orange : PartyTheme.mint)
                .frame(width: compact ? 76 : 102, height: compact ? 76 : 102)
                .background(PartyTheme.paper.opacity(0.08), in: RoundedRectangle(cornerRadius: 28))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: compact ? 32 : 40, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(PartyTheme.mint)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func timer(compact: Bool) -> some View {
        if isLive {
            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(max(0, state.remainingSeconds))")
                        .font(.system(size: compact ? 52 : 72, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text("秒").font(.system(.title3, design: .rounded).weight(.bold))
                }
                .foregroundStyle(state.remainingSeconds <= 10 && state.phase != .countdown ? PartyTheme.orange : PartyTheme.paper)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(state.phase == .paused ? "已暂停，剩余时间" : "剩余时间")
                .accessibilityValue("\(max(0, state.remainingSeconds)) 秒")
                .accessibilityIdentifier("audienceTimer")
                Text(state.phase == .paused ? "等搭档继续" : state.phase == .countdown ? "本轮猜词时间" : "还有时间，继续猜")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(PartyTheme.mint)
            }
        }
    }

    private var scoreBoard: some View {
        HStack(spacing: 10) {
            teamScore(0)
            Text(":")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(PartyTheme.mint)
                .accessibilityHidden(true)
            teamScore(1)
        }
        .padding(.vertical, 16).padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(PartyTheme.paper.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
    }

    private func teamScore(_ index: Int) -> some View {
        VStack(spacing: 6) {
            Text(PartyTheme.teamName(index))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(PartyTheme.teamColor(index))
            Text("\(score(index))")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(PartyTheme.teamName(index))，\(score(index)) 分")
    }

    private func score(_ index: Int) -> Int {
        state.scores.indices.contains(index) ? state.scores[index] : 0
    }

    private var winnerTitle: String {
        if score(0) == score(1) { return "平分秋色！" }
        return "\(PartyTheme.teamName(score(0) > score(1) ? 0 : 1))赢啦！"
    }

    private var footerText: String {
        switch state.phase {
        case .lobby: "等搭档在另一面点击「开一局」"
        case .paused: "两面猜 · 默契不着急"
        case .roundSummary: "等搭档在另一面开启下一回合"
        case .finished: "两面猜 · 一台手机，两个人的快乐"
        default: "这里是提示，答案在搭档那一面"
        }
    }
}
