import Foundation
import Observation

struct GameSettings: Equatable, Sendable {
    var duration: Int = 60
    var roundsPerTeam: Int = 2
    var categories: Set<WordCategory> = Set(WordCategory.allCases)
}

enum GamePhase: String, Codable, Sendable {
    case lobby, countdown, playing, reveal, paused, roundSummary, finished
}

enum GuessFeedback: String, Codable, Sendable {
    case correct, skipped
}

struct WordResult: Identifiable, Sendable {
    let word: PromptWord
    let outcome: GuessFeedback
    let sequence: Int
    var id: Int { sequence }
}

struct RoundResult: Identifiable, Sendable {
    let teamIndex: Int
    let turnNumber: Int
    let correctCount: Int
    let skipCount: Int
    let words: [WordResult]
    var id: Int { turnNumber }
    var teamName: String { teamIndex == 0 ? "橘子队" : "薄荷队" }
}

/// The sole model supplied to the audience display. Keep answers and round history out.
struct AudienceState: Equatable, Codable, Sendable {
    let phase: GamePhase
    let category: WordCategory?
    let characterCount: Int?
    let remainingSeconds: Int
    let countdown: Int
    let currentTeamIndex: Int
    let scores: [Int]
    let turnNumber: Int
    let roundCorrectCount: Int
    let roundSkipCount: Int
    let lastFeedback: GuessFeedback?
    var wordPoolExhausted: Bool = false

    var currentTeamName: String { currentTeamIndex == 0 ? "橘子队" : "薄荷队" }
}

@MainActor
@Observable
final class GameEngine {
    var settings = GameSettings()
    private(set) var phase: GamePhase = .lobby
    private(set) var currentWord: PromptWord?
    private(set) var currentTeamIndex = 0
    private(set) var scores = [0, 0]
    /// One-based after a match starts; each turn belongs to one team.
    private(set) var turnNumber = 0
    private(set) var roundHistory: [RoundResult] = []
    private(set) var roundCorrectCount = 0
    private(set) var roundSkipCount = 0
    private(set) var remainingSeconds = 60
    private(set) var countdown = 3
    private(set) var lastFeedback: GuessFeedback?
    private(set) var validationMessage: String?
    /// True when missing unseen answers ends the match before its scheduled finish.
    private(set) var wordPoolExhausted = false

    @ObservationIgnored private let wordSource: [PromptWord]
    @ObservationIgnored private let shuffleWords: Bool
    @ObservationIgnored private let clock: () -> TimeInterval
    @ObservationIgnored private var deck: [PromptWord] = []
    private var matchSettings = GameSettings()
    @ObservationIgnored private var countdownDeadline: TimeInterval?
    @ObservationIgnored private var roundDeadline: TimeInterval?
    @ObservationIgnored private var revealDeadline: TimeInterval?
    @ObservationIgnored private var pausedAt: TimeInterval?
    @ObservationIgnored private var phaseBeforePause: GamePhase?
    @ObservationIgnored private var latestTime: TimeInterval = 0
    @ObservationIgnored private var turnWords: [WordResult] = []

    init(
        words: [PromptWord] = WordBank.all,
        shuffleWords: Bool = true,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.wordSource = words
        self.shuffleWords = shuffleWords
        self.clock = clock
    }

    var currentTeamName: String { currentTeamIndex == 0 ? "橘子队" : "薄荷队" }
    var roundNumber: Int { max(1, (turnNumber + 1) / 2) }
    var totalTurns: Int { matchSettings.roundsPerTeam * 2 }
    var winningTeamIndex: Int? {
        guard scores[0] != scores[1] else { return nil }
        return scores[0] > scores[1] ? 0 : 1
    }

    var audienceState: AudienceState {
        AudienceState(
            phase: phase,
            category: currentWord?.category,
            characterCount: currentWord?.characterCount,
            remainingSeconds: remainingSeconds,
            countdown: countdown,
            currentTeamIndex: currentTeamIndex,
            scores: scores,
            turnNumber: turnNumber,
            roundCorrectCount: roundCorrectCount,
            roundSkipCount: roundSkipCount,
            lastFeedback: lastFeedback,
            wordPoolExhausted: wordPoolExhausted
        )
    }

    func startMatch() {
        guard phase == .lobby || phase == .finished else { return }
        resetMatch()
        // An empty selection means all categories; invalid numeric input is bounded.
        settings.duration = min(600, max(1, settings.duration))
        settings.roundsPerTeam = min(10, max(1, settings.roundsPerTeam))
        if settings.categories.isEmpty { settings.categories = Set(WordCategory.allCases) }
        matchSettings = settings
        var seen = Set<String>()
        seen.reserveCapacity(wordSource.count)
        let eligibleWords = wordSource.filter { word in
            guard matchSettings.categories.contains(word.category) else { return false }
            let answerKey = Self.normalizedAnswer(word.answer)
            return !answerKey.isEmpty && seen.insert(answerKey).inserted
        }
        guard !eligibleWords.isEmpty else {
            validationMessage = "这个分类暂时没有词语，换一个分类试试。"
            phase = .lobby
            return
        }
        // One deck for the entire match. A word is consumed when drawn, even if
        // time expires before anyone answers it. Never refill within a match.
        deck = shuffleWords ? eligibleWords.shuffled() : Array(eligibleWords.reversed())
        validationMessage = nil
        turnNumber = 1
        startTurn(at: observeTime())
    }

    func startNextTurn() {
        guard phase == .roundSummary else { return }
        turnNumber += 1
        currentTeamIndex = (turnNumber - 1) % 2
        startTurn(at: observeTime())
    }

    /// A monotonic absolute clock makes a delayed tick consume elapsed time correctly.
    func tick(now: TimeInterval? = nil) {
        let now = observeTime(now)
        guard phase != .paused else { return }

        if phase == .countdown, let deadline = countdownDeadline {
            countdown = max(0, Int(ceil(deadline - now)))
            if now >= deadline {
                countdownDeadline = nil
                roundDeadline = deadline + TimeInterval(matchSettings.duration)
                phase = .playing
            }
        }

        guard phase == .playing || phase == .reveal, let deadline = roundDeadline else { return }
        remainingSeconds = max(0, Int(ceil(deadline - now)))
        if now >= deadline {
            finishTurn()
            return
        }
        if phase == .reveal, let revealDeadline, now >= revealDeadline {
            self.revealDeadline = nil
            lastFeedback = nil
            guard let nextWord = drawWord() else {
                finishTurn(exhaustedBeforeDeadline: true)
                return
            }
            currentWord = nextWord
            phase = .playing
        }
    }

    func markCorrect() { record(.correct) }
    func skip() { record(.skipped) }

    func pause() {
        let now = observeTime()
        tick(now: now)
        guard [.countdown, .playing, .reveal].contains(phase) else { return }
        phaseBeforePause = phase
        pausedAt = now
        phase = .paused
    }

    func resume() {
        guard phase == .paused, let pausedAt, let previousPhase = phaseBeforePause else { return }
        let elapsed = observeTime() - pausedAt
        countdownDeadline = countdownDeadline.map { $0 + elapsed }
        roundDeadline = roundDeadline.map { $0 + elapsed }
        revealDeadline = revealDeadline.map { $0 + elapsed }
        self.pausedAt = nil
        phaseBeforePause = nil
        phase = previousPhase
        tick()
    }

    func returnToLobby() {
        resetMatch()
        phase = .lobby
        validationMessage = nil
    }

    private func record(_ feedback: GuessFeedback) {
        let now = observeTime()
        tick(now: now)
        guard phase == .playing, let currentWord else { return }
        if feedback == .correct {
            scores[currentTeamIndex] += 1
            roundCorrectCount += 1
        } else {
            roundSkipCount += 1
        }
        turnWords.append(WordResult(word: currentWord, outcome: feedback, sequence: turnWords.count))
        lastFeedback = feedback
        revealDeadline = now + 0.65
        phase = .reveal
    }

    private func startTurn(at now: TimeInterval) {
        guard let nextWord = drawWord() else {
            wordPoolExhausted = true
            currentWord = nil
            phase = .finished
            return
        }
        roundCorrectCount = 0
        roundSkipCount = 0
        turnWords = []
        lastFeedback = nil
        remainingSeconds = matchSettings.duration
        countdown = 3
        countdownDeadline = now + 3
        roundDeadline = nil
        revealDeadline = nil
        currentWord = nextWord
        phase = .countdown
    }

    private func finishTurn(exhaustedBeforeDeadline: Bool = false) {
        roundHistory.append(RoundResult(
            teamIndex: currentTeamIndex,
            turnNumber: turnNumber,
            correctCount: roundCorrectCount,
            skipCount: roundSkipCount,
            words: turnWords
        ))
        currentWord = nil
        lastFeedback = nil
        roundDeadline = nil
        revealDeadline = nil
        // The last scheduled turn timing out is a normal finish, even if its
        // final displayed word also happened to empty the deck.
        wordPoolExhausted = exhaustedBeforeDeadline || (deck.isEmpty && turnNumber < totalTurns)
        phase = wordPoolExhausted || turnNumber >= totalTurns ? .finished : .roundSummary
    }

    private func drawWord() -> PromptWord? {
        deck.popLast()
    }

    /// Category is deliberately excluded: an answer in two categories is still
    /// the same prompt. Preserve accents and Chinese spelling, but normalize
    /// compatibility characters, letter case, full-width forms, and whitespace.
    private static func normalizedAnswer(_ answer: String) -> String {
        answer.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { !$0.isWhitespace }
    }

    private func observeTime(_ supplied: TimeInterval? = nil) -> TimeInterval {
        let value = supplied ?? clock()
        if value.isFinite { latestTime = max(latestTime, value) }
        return latestTime
    }

    private func resetMatch() {
        scores = [0, 0]
        currentTeamIndex = 0
        turnNumber = 0
        roundHistory = []
        roundCorrectCount = 0
        roundSkipCount = 0
        turnWords = []
        currentWord = nil
        lastFeedback = nil
        deck = []
        wordPoolExhausted = false
        countdownDeadline = nil
        roundDeadline = nil
        revealDeadline = nil
        phaseBeforePause = nil
        pausedAt = nil
        countdown = 3
        remainingSeconds = max(1, settings.duration)
    }
}
