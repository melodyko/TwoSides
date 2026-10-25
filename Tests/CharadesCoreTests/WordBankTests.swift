import Foundation
import Testing
@testable import CharadesCore

struct WordBankTests {
    @Test func bundledExpansionLoadsAtLeastFiftyThousandWords() {
        #expect(WordBank.loadError == nil, "\(WordBank.loadError?.localizedDescription ?? "")")
        #expect(WordBank.expanded.count >= 49_760)
        #expect(WordBank.all.count >= 50_000)
        #expect(WordBank.all.count == WordBank.classic.count + WordBank.expanded.count)
    }

    @Test func originalClassicWordsArePreserved() {
        #expect(WordBank.classic.count == 240)
        #expect(!WordBank.classic.contains { $0.category == .general })
        for category in WordCategory.allCases where category != .general {
            #expect(WordBank.classic.filter { $0.category == category }.count == 40)
        }
        #expect(Set(WordBank.classic).isSubset(of: Set(WordBank.all)))
    }

    @Test func answersAndIdentifiersAreUniqueAcrossTheEntireCatalog() {
        #expect(Set(WordBank.all.map(\.answer)).count == WordBank.all.count)
        #expect(Set(WordBank.all.map(\.id)).count == WordBank.all.count)
        let classicAnswers = Set(WordBank.classic.map(\.answer))
        let expandedAnswers = Set(WordBank.expanded.map(\.answer))
        #expect(classicAnswers.isDisjoint(with: expandedAnswers))
    }

    @Test(arguments: WordCategory.allCases)
    func everyCategoryIsPopulatedAndIndexedCorrectly(category: WordCategory) {
        let words = WordBank.words(in: category)
        #expect(words.count >= 30)
        #expect(WordBank.count(in: category) == words.count)
        #expect(words.allSatisfy { $0.category == category })
        #expect(words == WordBank.all.filter { $0.category == category })
    }

    @Test func categorySelectionsUseConsistentCountsAndWords() {
        let selections: [Set<WordCategory>] = [[], [.general], [.animals, .food, .general], Set(WordCategory.allCases)]
        for categories in selections {
            let expected = WordBank.all.filter { categories.contains($0.category) }
            #expect(WordBank.count(in: categories) == expected.count)
            #expect(Set(WordBank.words(in: categories)) == Set(expected))
        }
        #expect(WordCategory.general.title == "万象词语")
        #expect(WordCategory.general.symbol == "square.stack")
    }

    @Test func everyAnswerContainsTwoToEightHanCharacters() throws {
        let hanOnly = try NSRegularExpression(pattern: "\\A\\p{Han}{2,8}\\z")
        let invalidWords = WordBank.all.filter { word in
            let range = NSRange(word.answer.startIndex..<word.answer.endIndex, in: word.answer)
            return !(2...8).contains(word.characterCount)
                || hanOnly.firstMatch(in: word.answer, range: range)?.range != range
        }
        #expect(invalidWords.isEmpty, "Invalid answers: \(invalidWords.prefix(10).map(\.answer))")
    }

    @Test func parserAcceptsAllCategoriesAndStandardLineEndings() throws {
        let records = [
            "daily\t日历", "animals\t海獭", "food\t咖啡", "movies\t花木兰",
            "actions\t拍手", "idioms\t一见如故", "general\t星空"
        ]
        for newline in ["\n", "\r\n"] {
            for trailingNewline in [false, true] {
                let text = records.joined(separator: newline) + (trailingNewline ? newline : "")
                let words = try WordBank.parseExpandedWords(Data(text.utf8))
                #expect(words.count == 7)
                #expect(Set(words.map(\.category)) == Set(WordCategory.allCases))
                #expect(words.first?.answer == "日历")
                #expect(words.last?.answer == "星空")
            }
        }
    }

    @Test func parserRejectsMalformedDataWithoutReturningAPartialCatalog() {
        let invalidRecords: [(String, WordBank.LoadError)] = [
            ("", .emptyResource),
            ("general星空", .malformedLine(1)),
            ("general\t星空\t额外", .malformedLine(1)),
            ("category\tanswer", .unknownCategory(line: 1, value: "category")),
            ("unknown\t星空", .unknownCategory(line: 1, value: "unknown")),
            ("\t星空", .unknownCategory(line: 1, value: "")),
            ("general\t", .invalidLength(line: 1, answer: "")),
            ("general\t星", .invalidLength(line: 1, answer: "星")),
            ("general\t一二三四五六七八九", .invalidLength(line: 1, answer: "一二三四五六七八九")),
            ("general\t星 空", .nonHanCharacters(line: 1, answer: "星 空")),
            ("general\t星空A", .nonHanCharacters(line: 1, answer: "星空A")),
            ("general\t星空！", .nonHanCharacters(line: 1, answer: "星空！")),
            ("general\t星空🙂", .nonHanCharacters(line: 1, answer: "星空🙂")),
            ("general\t星空\ngeneral\t星空", .duplicateAnswer(line: 2, answer: "星空")),
            ("general\t星空\ndaily\t星空", .duplicateAnswer(line: 2, answer: "星空")),
            ("general\t长颈鹿", .classicConflict(line: 1, answer: "长颈鹿")),
            ("general\t星空\n\n", .malformedLine(2)),
            ("general\t星空\n损坏数据", .malformedLine(2))
        ]
        for (text, error) in invalidRecords {
            #expect(throws: error) { try WordBank.parseExpandedWords(Data(text.utf8)) }
        }
        #expect(throws: WordBank.LoadError.invalidUTF8) {
            try WordBank.parseExpandedWords(Data([0xFF, 0xFE, 0xFD]))
        }
    }

    @Test func fileLoaderRejectsMissingUnreadableAndTruncatedResources() throws {
        #expect(throws: WordBank.LoadError.missingResource) {
            try WordBank.loadExpandedWords(from: nil)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tsv")
        #expect(throws: WordBank.LoadError.self) {
            try WordBank.loadExpandedWords(from: url)
        }
        try Data("general\t星空\nfood\t咖啡\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: WordBank.LoadError.insufficientWords(expected: 49_760, actual: 2)) {
            try WordBank.loadExpandedWords(from: url)
        }
        let words = try WordBank.loadExpandedWords(from: url, minimumCount: 2)
        #expect(words.map(\.answer) == ["星空", "咖啡"])
    }
}
