import SwiftUI

enum PartyTheme {
    static let canvas = Color(red: 0.965, green: 0.953, blue: 0.918)
    static let paper = Color(red: 1, green: 0.996, blue: 0.976)
    static let ink = Color(red: 0.125, green: 0.224, blue: 0.180)
    static let secondary = Color(red: 0.349, green: 0.400, blue: 0.369)
    static let orange = Color(red: 0.898, green: 0.639, blue: 0.239)
    static let green = Color(red: 0.125, green: 0.345, blue: 0.251)
    static let mint = Color(red: 0.828, green: 0.900, blue: 0.804)
    static let line = Color(red: 0.820, green: 0.835, blue: 0.788)
    static let danger = Color(red: 0.651, green: 0.235, blue: 0.208)
    static func teamColor(_ index: Int) -> Color { index == 0 ? orange : mint }
    static func teamName(_ index: Int) -> String { index == 0 ? "橘子队" : "薄荷队" }
}

struct PartyButtonStyle: ButtonStyle {
    var fill: Color = PartyTheme.green
    var foreground: Color = .white
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 16)
            .foregroundStyle(foreground)
            .background(fill, in: RoundedRectangle(cornerRadius: 18))
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct TwoFacesMark: View {
    var size: CGFloat = 100
    var body: some View {
        ZStack {
            face(color: PartyTheme.mint, happy: false)
                .rotationEffect(.degrees(-13)).offset(x: -size * 0.21, y: size * 0.04)
            face(color: PartyTheme.orange, happy: true)
                .rotationEffect(.degrees(12)).offset(x: size * 0.21, y: -size * 0.04)
        }
        .frame(width: size * 1.45, height: size * 1.2)
        .accessibilityHidden(true)
    }
    private func face(color: Color, happy: Bool) -> some View {
        VStack(spacing: size * 0.15) {
            HStack(spacing: size * 0.22) {
                Capsule().frame(width: size * 0.055, height: size * 0.12)
                Capsule().frame(width: size * 0.055, height: size * 0.12)
            }
            if happy {
                UnevenRoundedRectangle(bottomLeadingRadius: size * 0.13, bottomTrailingRadius: size * 0.13)
                    .frame(width: size * 0.27, height: size * 0.12)
            } else {
                Capsule().frame(width: size * 0.19, height: size * 0.04)
            }
        }
        .foregroundStyle(PartyTheme.ink)
        .frame(width: size * 0.76, height: size)
        .background(color, in: RoundedRectangle(cornerRadius: size * 0.15))
        .overlay(RoundedRectangle(cornerRadius: size * 0.15).stroke(PartyTheme.ink, lineWidth: 2))
    }
}

struct ScoreStrip: View {
    let scores: [Int]
    var activeTeam: Int? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 10) { team(0); team(1) }
        } else {
            HStack(spacing: 12) {
                team(0)
                Text("VS").font(.system(.caption, design: .rounded).weight(.heavy)).foregroundStyle(PartyTheme.secondary)
                team(1)
            }
        }
    }
    private func team(_ index: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(PartyTheme.teamColor(index)).frame(width: 10, height: 10)
            Text(PartyTheme.teamName(index)).font(.system(.subheadline, design: .rounded).weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 6)
            Text("\(scores.indices.contains(index) ? scores[index] : 0)")
                .font(.system(.title2, design: .rounded).weight(.heavy)).monospacedDigit()
        }
        .foregroundStyle(PartyTheme.ink)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(activeTeam == index ? PartyTheme.teamColor(index).opacity(0.38) : PartyTheme.paper, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct SectionCaption: View {
    let title: String
    var trailing: String = ""
    var body: some View {
        HStack {
            Text(title).font(.system(.headline, design: .rounded))
            Spacer()
            Text(trailing).font(.system(.caption, design: .rounded)).foregroundStyle(PartyTheme.secondary)
        }.foregroundStyle(PartyTheme.ink)
    }
}
