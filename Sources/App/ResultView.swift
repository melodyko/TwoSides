import SwiftUI

struct ResultView: View {
    @Bindable var game: GameEngine
    var onNext: () -> Void
    var onLobby: () -> Void

    private var isFinished: Bool { game.phase == .finished }
    private var displayedRounds: [RoundResult] {
        isFinished ? game.roundHistory : Array(game.roundHistory.suffix(1))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                celebration
                ScoreStrip(scores: game.scores, activeTeam: isFinished ? game.winningTeamIndex : game.currentTeamIndex)

                if !isFinished {
                    HStack(spacing: 24) {
                        roundMetric(value: game.roundCorrectCount, title: "答对", symbol: "checkmark.circle.fill")
                        Divider().frame(height: 42)
                        roundMetric(value: game.roundSkipCount, title: "跳过", symbol: "arrow.right.circle")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }

                VStack(spacing: 10) {
                    Button(action: onNext) {
                        HStack {
                            Text(isFinished ? "再来一局" : "换\(PartyTheme.teamName(1 - game.currentTeamIndex))")
                            Spacer()
                            Image(systemName: isFinished ? "arrow.clockwise" : "arrow.right")
                        }
                    }
                    .buttonStyle(PartyButtonStyle())
                    .accessibilityIdentifier("nextTurn")
                    Button("回大厅", action: onLobby)
                        .buttonStyle(PartyButtonStyle(fill: PartyTheme.paper, foreground: PartyTheme.ink))
                        .accessibilityIdentifier("backToLobby")
                }

                VStack(alignment: .leading, spacing: 16) {
                    SectionCaption(title: isFinished ? "这一局的默契" : "刚才都猜了什么", trailing: "词条回顾")
                    ForEach(displayedRounds) { round in
                        roundReview(round)
                    }
                }
            }
            .frame(maxWidth: 680)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(PartyTheme.ink)
    }

    private var celebration: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text(isFinished ? "默契挑战完成" : "第 \(game.roundNumber) 轮 · 回合结束")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(PartyTheme.secondary)
                Spacer()
                Image(systemName: isFinished ? "flag.checkered" : "checkmark.seal")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(PartyTheme.green)
                    .accessibilityHidden(true)
            }
            Text(resultTitle)
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .fixedSize(horizontal: false, vertical: true)
            Text(resultSubtitle)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(PartyTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    private var resultTitle: String {
        if game.wordPoolExhausted { return "这组词已经猜完啦！" }
        if isFinished {
            if let winner = game.winningTeamIndex { return "\(PartyTheme.teamName(winner))赢啦！" }
            return "这局不分上下！"
        }
        return "\(game.currentTeamName)，好样的！"
    }

    private var resultSubtitle: String {
        if game.wordPoolExhausted {
            return "为保证整局不重复，本局提前结束，保留当前比分。可以回大厅增加分类，或再开一局。"
        }
        if isFinished {
            return game.winningTeamIndex == nil ? "默契势均力敌，再来一局分个胜负？" : "猜对的是词，收获的是默契。"
        }
        return "拿下 \(game.roundCorrectCount) 分，现在把描述机会交给\(PartyTheme.teamName(1 - game.currentTeamIndex))。"
    }

    private func roundMetric(value: Int, title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(.title2, design: .rounded))
                .foregroundStyle(PartyTheme.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)").font(.system(.title, design: .rounded).weight(.heavy)).monospacedDigit()
                Text(title).font(.system(.subheadline, design: .rounded)).foregroundStyle(PartyTheme.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func roundReview(_ round: RoundResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if isFinished {
                HStack(spacing: 8) {
                    Circle().fill(PartyTheme.teamColor(round.teamIndex)).frame(width: 10, height: 10)
                    Text("第 \((round.turnNumber + 1) / 2) 轮 · \(round.teamName)")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                    Spacer()
                    Text("+\(round.correctCount)")
                        .font(.system(.headline, design: .rounded)).monospacedDigit()
                }
                .padding(.bottom, 14)
            }
            if round.words.isEmpty {
                Text("这一回合没有作答记录，下回合继续加油。")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(PartyTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ForEach(round.words) { result in
                    HStack(spacing: 12) {
                        Image(systemName: result.outcome == .correct ? "checkmark.circle.fill" : "arrow.right.circle")
                            .font(.system(.title3, design: .rounded))
                            .foregroundStyle(result.outcome == .correct ? PartyTheme.green : PartyTheme.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.word.answer)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                            Text(result.word.category.title)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(PartyTheme.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(result.outcome == .correct ? "+1" : "跳过")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(result.outcome == .correct ? PartyTheme.green : PartyTheme.secondary)
                    }
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                    if result.id != round.words.last?.id {
                        Rectangle().fill(PartyTheme.line.opacity(0.6)).frame(height: 1)
                    }
                }
            }
        }
        .padding(18)
        .background(PartyTheme.paper, in: RoundedRectangle(cornerRadius: 22))
    }
}
