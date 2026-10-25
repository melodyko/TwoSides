import SwiftUI

struct LobbyView: View {
    @Bindable var game: GameEngine
    var onStart: () -> Void
    var onPreview: () -> Void
    var onCamera: () -> Void
    var cameraEnabled: Bool
    var cameraStatus: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showWordSources = false

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PARTY FOR TWO SIDES").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(2)
                                .foregroundStyle(PartyTheme.secondary)
                            Text("两面猜").font(.system(size: 44, weight: .heavy, design: .rounded))
                            Text("你来比划，我来猜。")
                                .font(.system(.title3, design: .rounded)).foregroundStyle(PartyTheme.secondary)
                        }
                        Spacer(minLength: 0)
                        TwoFacesMark(size: geo.size.width < 400 ? 70 : 92).padding(.top, 4)
                    }
                    .padding(.top, 12)

                    HStack(spacing: 16) {
                        Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 28))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("一台手机，两种视角").font(.system(.headline, design: .rounded))
                            Text("内屏看答案 · 外屏看提示")
                                .font(.system(.subheadline, design: .rounded)).foregroundStyle(PartyTheme.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(20).background(PartyTheme.mint.opacity(0.6), in: RoundedRectangle(cornerRadius: 22))

                    VStack(spacing: 14) {
                        SectionCaption(title: "今天猜什么", trailing: "可多选 · \(selectedWordCount) 个词")
                        LazyVGrid(columns: Array(
                            repeating: GridItem(.flexible(), spacing: 12),
                            count: typeSize.isAccessibilitySize ? 1 : geo.size.width < 600 ? 2 : 3
                        ), spacing: 12) {
                            ForEach(WordCategory.allCases) { category in categoryButton(category) }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Label("整局不重复，跳过的词也不会再出现", systemImage: "checkmark.seal")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            Text("海量词库含生僻和抽象词，遇到不熟悉的可以跳过。")
                                .font(.system(.caption, design: .rounded)).foregroundStyle(PartyTheme.secondary)
                            Button("词库来源与说明") { showWordSources = true }
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("wordSources")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let error = WordBank.loadError {
                            Text(error.localizedDescription)
                                .font(.caption).foregroundStyle(PartyTheme.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    VStack(spacing: 16) {
                        SectionCaption(title: "游戏节奏")
                        optionsRow(title: "每回合", values: [30, 60, 90], value: game.settings.duration, suffix: "秒") { game.settings.duration = $0 }
                        optionsRow(title: "每队", values: [1, 2, 3], value: game.settings.roundsPerTeam, suffix: "轮") { game.settings.roundsPerTeam = $0 }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: cameraEnabled ? "camera.fill" : "camera").font(.title3).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cameraEnabled ? "面对面模式已开启" : "面对面模式").font(.system(.headline, design: .rounded))
                                Text(cameraStatus).font(.system(.caption, design: .rounded))
                                    .foregroundStyle(PartyTheme.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Button(cameraEnabled ? "关闭" : "开启", action: onCamera)
                                .font(.system(.subheadline, design: .rounded).bold())
                                .padding(.horizontal, 16).frame(minHeight: 44)
                                .background(PartyTheme.paper, in: Capsule())
                                .accessibilityIdentifier("cameraToggle")
                        }
                        Button(action: onPreview) {
                            Label("先看看双方画面", systemImage: "eye")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityIdentifier("previewButton")
                    }
                    .padding(18)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(PartyTheme.line, lineWidth: 1))

                    if let message = game.validationMessage {
                        Text(message).foregroundStyle(PartyTheme.danger).font(.callout)
                    }
                }
                .frame(maxWidth: 680).padding(24).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
        }
        .foregroundStyle(PartyTheme.ink)
        .sheet(isPresented: $showWordSources) { WordSourcesView() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Button(action: onStart) {
                    HStack { Text("开一局"); Spacer(); Text("橘子队先来").font(.subheadline); Image(systemName: "arrow.right") }
                }
                .buttonStyle(PartyButtonStyle()).accessibilityIdentifier("startGame")
                Text("答对 +1 · 跳过不扣分 · 两队轮流上场")
                    .font(.system(.caption, design: .rounded)).foregroundStyle(PartyTheme.secondary)
            }
            .frame(maxWidth: 680).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
            .frame(maxWidth: .infinity).background(PartyTheme.canvas)
        }
    }

    private var selectedWordCount: Int { game.settings.categories.reduce(0) { $0 + WordBank.count(in: $1) } }
    private func categoryButton(_ category: WordCategory) -> some View {
        let selected = game.settings.categories.contains(category)
        return Button {
            if selected && game.settings.categories.count > 1 { game.settings.categories.remove(category) }
            else { game.settings.categories.insert(category) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: category.symbol).font(.system(size: 18)).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title).font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.8)
                    Text("\(WordBank.count(in: category)) 个词")
                        .font(.system(.caption2, design: .rounded)).foregroundStyle(PartyTheme.secondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 16))
            }
            .foregroundStyle(selected ? PartyTheme.ink : PartyTheme.secondary)
            .padding(14).frame(minHeight: 54)
            .background(selected ? PartyTheme.orange.opacity(0.29) : PartyTheme.paper, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? PartyTheme.orange : PartyTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.title).accessibilityValue(selected ? "已选择" : "未选择")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func optionsRow(title: String, values: [Int], value: Int, suffix: String, select: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(.subheadline, design: .rounded)).frame(width: 56, alignment: .leading)
            ForEach(values, id: \.self) { option in
                Button { select(option) } label: {
                    Text("\(option) \(suffix)").font(.system(.subheadline, design: .rounded).weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(value == option ? PartyTheme.ink : PartyTheme.paper, in: RoundedRectangle(cornerRadius: 13))
                        .foregroundStyle(value == option ? .white : PartyTheme.ink)
                }.buttonStyle(.plain).accessibilityAddTraits(value == option ? .isSelected : [])
            }
        }
    }
}

private struct WordSourcesView: View {
    @Environment(\.dismiss) private var dismiss
    private let sourceText: String = {
        guard let url = Bundle.main.url(forResource: "WordSources", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "词库说明未能加载，请查看项目中的 WORD_BANK.md。"
        }
        return text
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(sourceText).font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
            .navigationTitle("词库来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
