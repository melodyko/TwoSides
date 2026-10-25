import Foundation

enum WordCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case daily, animals, food, movies, actions, idioms, general
    var id: String { rawValue }
    var title: String {
        switch self {
        case .daily: "生活日常"
        case .animals: "动物世界"
        case .food: "吃点什么"
        case .movies: "影视角色"
        case .actions: "动作挑战"
        case .idioms: "成语接招"
        case .general: "万象词语"
        }
    }
    var symbol: String {
        switch self {
        case .daily: "sun.max"
        case .animals: "pawprint"
        case .food: "fork.knife"
        case .movies: "film"
        case .actions: "figure.dance"
        case .idioms: "text.book.closed"
        case .general: "square.stack"
        }
    }
}

struct PromptWord: Identifiable, Hashable, Codable, Sendable {
    let answer: String
    let category: WordCategory
    var id: String { category.rawValue + ":" + answer }
    var characterCount: Int { answer.filter { !$0.isWhitespace }.count }
    init(_ answer: String, category: WordCategory) {
        self.answer = answer
        self.category = category
    }
}
