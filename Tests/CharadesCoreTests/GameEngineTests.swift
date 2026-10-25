import Foundation
import Testing
@testable import CharadesCore

@MainActor
private final class TestClock {
    var now: TimeInterval = 100
}

@MainActor
struct GameEngineTests {
    private let sampleWords = [
        PromptWord("小熊猫", category: .animals),
        PromptWord("长颈鹿", category: .animals),
        PromptWord("冰淇淋", category: .food),
        PromptWord("撑雨伞", category: .actions)
    ]

    private func makeGame(duration: Int = 10, rounds: Int = 1) -> (GameEngine, TestClock) {
        let clock = TestClock()
        let game = GameEngine(words: sampleWords, shuffleWords: false, clock: { clock.now })
        game.settings.duration = duration
        game.settings.roundsPerTeam = rounds
        return (game, clock)
    }

    private func beginPlaying(_ game: GameEngine, _ clock: TestClock) {
        game.startMatch()
        clock.now += 3
        game.tick()
    }

    @Test func countdownPreventsEarlyScoringAndUsesElapsedTime() {
        let (game, clock) = makeGame()
        game.startMatch()
        game.markCorrect()
        game.skip()
        #expect(game.phase == .countdown)
        #expect(game.scores == [0, 0])
        clock.now += 2.9
        game.tick()
        #expect(game.countdown == 1)
        clock.now += 2.1
        game.tick()
        #expect(game.phase == .playing)
        #expect(game.remainingSeconds == 8)
    }

    @Test func delayedTickExpiresRoundWithoutGivingExtraPlayTime() {
        let (game, clock) = makeGame()
        game.startMatch()
        clock.now += 90
        game.tick()
        game.tick()
        game.markCorrect()
        #expect(game.phase == .roundSummary)
        #expect(game.remainingSeconds == 0)
        #expect(game.roundHistory.count == 1)
        #expect(game.scores == [0, 0])
    }

    @Test func deadlineIsEnforcedEvenWithoutATimerTick() {
        let (game, clock) = makeGame()
        beginPlaying(game, clock)
        clock.now += 10
        game.markCorrect()
        #expect(game.scores == [0, 0])
        #expect(game.phase == .roundSummary)
        #expect(game.roundHistory.first?.words.isEmpty == true)
    }

    @Test func rapidButtonsRecordExactlyOneResultThenAdvance() {
        let (game, clock) = makeGame()
        beginPlaying(game, clock)
        let firstWord = game.currentWord
        game.markCorrect()
        game.markCorrect()
        game.skip()
        #expect(game.phase == .reveal)
        #expect(game.currentWord == firstWord)
        #expect(game.roundCorrectCount == 1)
        #expect(game.roundSkipCount == 0)
        #expect(game.lastFeedback == .correct)
        clock.now += 0.7
        game.tick()
        #expect(game.phase == .playing)
        #expect(game.currentWord != firstWord)
        #expect(game.lastFeedback == nil)
        game.skip()
        #expect(game.roundSkipCount == 1)
        #expect(game.scores == [1, 0])
    }

    @Test func pauseFreezesTimeAndPreservesFeedbackLock() {
        let (game, clock) = makeGame()
        beginPlaying(game, clock)
        clock.now += 2
        game.markCorrect()
        clock.now += 0.2
        game.pause()
        let remaining = game.remainingSeconds
        clock.now += 300
        game.tick()
        game.markCorrect()
        game.skip()
        #expect(game.phase == .paused)
        #expect(game.remainingSeconds == remaining)
        #expect(game.scores == [1, 0])
        game.resume()
        #expect(game.phase == .reveal)
        clock.now += 0.3
        game.tick()
        #expect(game.phase == .reveal)
        clock.now += 0.2
        game.tick()
        #expect(game.phase == .playing)
        clock.now += 7.4
        game.tick()
        #expect(game.phase == .roundSummary)
    }

    @Test func countdownCanPauseAndResumeWithoutStartingTheRound() {
        let (game, clock) = makeGame()
        game.startMatch()
        clock.now += 1
        game.pause()
        clock.now += 30
        game.resume()
        #expect(game.phase == .countdown)
        #expect(game.countdown == 2)
        clock.now += 2
        game.tick()
        #expect(game.phase == .playing)
        #expect(game.remainingSeconds == 10)
    }

    @Test func teamsAlternateAndBothGetEqualRounds() {
        let (game, clock) = makeGame(duration: 1, rounds: 2)
        game.startMatch()
        for turn in 1...4 {
            #expect(game.turnNumber == turn)
            #expect(game.currentTeamIndex == (turn - 1) % 2)
            clock.now += 3
            game.tick()
            if game.currentTeamIndex == 1 { game.markCorrect() }
            clock.now += 1
            game.tick()
            if turn < 4 {
                #expect(game.phase == .roundSummary)
                game.startNextTurn()
            }
        }
        #expect(game.phase == .finished)
        #expect(game.roundHistory.map(\.teamIndex) == [0, 1, 0, 1])
        #expect(game.scores == [0, 2])
        #expect(game.winningTeamIndex == 1)
        #expect(!game.wordPoolExhausted)
        game.startNextTurn()
        #expect(game.turnNumber == 4)
    }

    @Test func settingsChangesDuringPlayDoNotChangeTheMatch() {
        let (game, clock) = makeGame(duration: 10, rounds: 1)
        beginPlaying(game, clock)
        game.settings.duration = 600
        game.settings.roundsPerTeam = 10
        game.settings.categories = [.idioms]
        clock.now += 10
        game.tick()
        #expect(game.phase == .roundSummary)
        #expect(game.totalTurns == 2)
        game.startNextTurn()
        #expect(game.remainingSeconds == 10)
        #expect(game.currentWord != nil)
    }

    @Test func exhaustingThePoolEndsTheMatchWithoutRecyclingWords() {
        let (game, clock) = makeGame(duration: 60)
        beginPlaying(game, clock)
        var drawn: [PromptWord] = []
        for _ in sampleWords.indices {
            if let word = game.currentWord { drawn.append(word) }
            game.skip()
            clock.now += 0.7
            game.tick()
        }
        #expect(drawn == sampleWords)
        #expect(game.phase == .finished)
        #expect(game.wordPoolExhausted)
        #expect(game.audienceState.wordPoolExhausted)
        #expect(game.currentWord == nil)
        #expect(game.roundHistory.count == 1)
        #expect(game.roundHistory.first?.skipCount == sampleWords.count)

        // Repeated ticks or old input events cannot add an empty turn or refill.
        for _ in 0..<10 {
            clock.now += 1
            game.tick()
            game.skip()
            game.markCorrect()
            game.startNextTurn()
        }
        #expect(game.phase == .finished)
        #expect(game.roundHistory.count == 1)
        #expect(game.scores == [0, 0])
    }

    @Test func singleWordPoolPreservesFeedbackAndPauseBeforeEnding() {
        let clock = TestClock()
        let word = sampleWords[0]
        let game = GameEngine(words: [word, PromptWord(word.answer, category: .daily)], clock: { clock.now })
        beginPlaying(game, clock)
        #expect(game.currentWord == word)
        game.markCorrect()
        game.markCorrect()
        game.skip()
        clock.now += 0.3
        game.pause()
        clock.now += 200
        game.resume()
        #expect(game.phase == .reveal)
        #expect(game.lastFeedback == .correct)
        #expect(!game.wordPoolExhausted)
        clock.now += 0.4
        game.tick()
        #expect(game.phase == .finished)
        #expect(game.wordPoolExhausted)
        #expect(game.currentWord == nil)
        #expect(game.scores == [1, 0])
        #expect(game.roundHistory.first?.words.count == 1)
    }

    @Test func equivalentAnswersDeduplicateAcrossCategoriesAndUnicodeForms() {
        let clock = TestClock()
        let words = [
            PromptWord(" 咖 啡 ", category: .daily),
            PromptWord("咖啡", category: .food),
            PromptWord("ＣＡＦÉ", category: .daily),
            PromptWord("cafe\u{301}", category: .food),
            PromptWord("红烧肉", category: .food),
            PromptWord("\n\t　", category: .daily)
        ]
        let game = GameEngine(words: words, shuffleWords: false, clock: { clock.now })
        beginPlaying(game, clock)
        var answers: [String] = []
        for _ in 0..<3 {
            if let word = game.currentWord { answers.append(word.answer) }
            game.skip()
            clock.now += 0.7
            game.tick()
        }
        #expect(answers == [" 咖 啡 ", "ＣＡＦÉ", "红烧肉"])
        #expect(game.phase == .finished)
        #expect(game.wordPoolExhausted)
        #expect(game.roundHistory.first?.words.count == 3)
    }

    @Test func duplicateInExcludedCategoryDoesNotRemoveSelectedAnswer() {
        let clock = TestClock()
        let game = GameEngine(words: [
            PromptWord("咖啡", category: .daily),
            PromptWord("咖啡", category: .food)
        ], clock: { clock.now })
        game.settings.categories = [.food]
        beginPlaying(game, clock)
        #expect(game.currentWord?.answer == "咖啡")
        #expect(game.currentWord?.category == .food)
        game.skip()
        clock.now += 0.7
        game.tick()
        #expect(game.phase == .finished)
        #expect(game.wordPoolExhausted)
    }

    @Test func unansweredWordsAreConsumedAcrossTurnsIncludingShuffledDecks() {
        let clock = TestClock()
        let game = GameEngine(words: sampleWords, clock: { clock.now })
        game.settings.duration = 1
        game.settings.roundsPerTeam = 3
        game.startMatch()
        var seenAnswers = Set<String>()
        for turn in 1...sampleWords.count {
            clock.now += 3
            game.tick()
            if let word = game.currentWord {
                #expect(seenAnswers.insert(word.answer).inserted)
            }
            // No answer or skip: even this displayed word cannot appear again.
            clock.now += 1
            game.tick()
            if turn < sampleWords.count {
                #expect(game.phase == .roundSummary)
                game.startNextTurn()
            }
        }
        #expect(seenAnswers == Set(sampleWords.map(\.answer)))
        #expect(game.phase == .finished)
        #expect(game.wordPoolExhausted)
        #expect(game.turnNumber == 4)
        #expect(game.totalTurns == 6)
        #expect(game.roundHistory.count == 4)
        #expect(game.roundHistory.allSatisfy { $0.words.isEmpty })
    }

    @Test func expirationDuringLastFeedbackFinishesOnlyOnce() {
        let clock = TestClock()
        let game = GameEngine(words: [sampleWords[0]], clock: { clock.now })
        game.settings.duration = 1
        beginPlaying(game, clock)
        clock.now += 0.6
        game.markCorrect()
        clock.now += 0.4
        game.tick()
        clock.now += 1
        game.tick()
        #expect(game.phase == .finished)
        #expect(game.wordPoolExhausted)
        #expect(game.roundHistory.count == 1)
        #expect(game.scores == [1, 0])
    }

    @Test(arguments: [false, true])
    func finalTurnOnlyReportsExhaustionWhenItEndsEarly(finishBeforeDeadline: Bool) {
        let clock = TestClock()
        let game = GameEngine(words: Array(sampleWords.prefix(2)), shuffleWords: false, clock: { clock.now })
        game.settings.duration = 1
        game.settings.roundsPerTeam = 1
        beginPlaying(game, clock)
        clock.now += 1
        game.tick()
        #expect(game.phase == .roundSummary)
        game.startNextTurn()
        clock.now += 3
        game.tick()
        #expect(game.currentWord == sampleWords[1])
        if finishBeforeDeadline {
            game.markCorrect()
            clock.now += 0.7
        } else {
            clock.now += 1
        }
        game.tick()
        #expect(game.phase == .finished)
        #expect(game.wordPoolExhausted == finishBeforeDeadline)
        #expect(game.audienceState.wordPoolExhausted == finishBeforeDeadline)
        #expect(game.roundHistory.count == 2)
    }

    @Test func newMatchCanUseThePoolAgainAndClearsExhaustion() {
        let clock = TestClock()
        let game = GameEngine(words: [sampleWords[0]], clock: { clock.now })
        beginPlaying(game, clock)
        game.markCorrect()
        clock.now += 0.7
        game.tick()
        #expect(game.wordPoolExhausted)
        game.startMatch()
        #expect(!game.wordPoolExhausted)
        #expect(!game.audienceState.wordPoolExhausted)
        #expect(game.phase == .countdown)
        #expect(game.currentWord == sampleWords[0])
        #expect(game.scores == [0, 0])
        #expect(game.roundHistory.isEmpty)
        game.returnToLobby()
        #expect(!game.wordPoolExhausted)
    }

    @Test func categorySelectionAndEmptySelectionAreUsable() {
        let (game, _) = makeGame()
        game.settings.categories = [.food]
        game.startMatch()
        #expect(game.currentWord?.category == .food)
        game.returnToLobby()
        game.settings.categories = []
        game.startMatch()
        #expect(game.phase == .countdown)
        #expect(game.settings.categories == Set(WordCategory.allCases))
    }

    @Test func missingCategoryAndEmptySourceReturnUsefulError() {
        let (game, _) = makeGame()
        game.settings.categories = [.idioms]
        game.startMatch()
        #expect(game.phase == .lobby)
        #expect(game.validationMessage != nil)
        #expect(game.currentWord == nil)

        let empty = GameEngine(words: [])
        empty.startMatch()
        #expect(empty.phase == .lobby)
        #expect(empty.validationMessage != nil)
    }

    @Test func audiencePayloadContainsOnlySafeMetadataAcrossPhases() throws {
        let (game, clock) = makeGame()
        func assertSafe() throws {
            let data = try JSONEncoder().encode(game.audienceState)
            let json = String(decoding: data, as: UTF8.self)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let allowedKeys: Set<String> = ["phase", "category", "characterCount", "remainingSeconds", "countdown", "currentTeamIndex", "scores", "turnNumber", "roundCorrectCount", "roundSkipCount", "lastFeedback", "wordPoolExhausted"]
            #expect(Set(object.keys).isSubset(of: allowedKeys))
            for word in sampleWords { #expect(!json.contains(word.answer)) }
            #expect(object["answer"] == nil)
            #expect(object["words"] == nil)
            #expect(object["roundHistory"] == nil)
        }
        try assertSafe()
        game.startMatch()
        try assertSafe()
        clock.now += 3
        game.tick()
        try assertSafe()
        game.markCorrect()
        try assertSafe()
        game.pause()
        try assertSafe()
        game.resume()
        clock.now += 10
        game.tick()
        try assertSafe()
        #expect(game.roundHistory.first?.words.first?.word.answer == sampleWords[0].answer)
    }

    @Test func returningToLobbyClearsEveryPreviousAnswerAndScore() {
        let (game, clock) = makeGame()
        beginPlaying(game, clock)
        game.markCorrect()
        game.pause()
        game.returnToLobby()
        game.resume()
        game.tick()
        #expect(game.phase == .lobby)
        #expect(game.currentWord == nil)
        #expect(game.roundHistory.isEmpty)
        #expect(game.scores == [0, 0])
        #expect(game.lastFeedback == nil)
        #expect(game.audienceState.category == nil)
        game.startMatch()
        #expect(game.turnNumber == 1)
        #expect(game.phase == .countdown)
    }
}
