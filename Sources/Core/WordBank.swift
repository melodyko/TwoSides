import Foundation

enum WordBank {
    static let classic: [PromptWord] = [
        (.daily, [
            "牙刷", "雨伞", "闹钟", "冰箱", "洗衣机", "吹风机", "遥控器", "充电宝",
            "耳机", "眼镜", "书包", "拖鞋", "枕头", "被子", "衣架", "镜子",
            "台灯", "沙发", "电梯", "地铁", "红绿灯", "斑马线", "快递", "外卖",
            "钥匙", "钱包", "水杯", "保温杯", "垃圾桶", "扫地机器人", "空调", "风扇",
            "自拍杆", "行李箱", "购物车", "便利店", "电影院", "游乐园", "摩天轮", "旋转木马"
        ]),
        (.animals, [
            "熊猫", "长颈鹿", "大象", "狮子", "老虎", "斑马", "袋鼠", "考拉",
            "企鹅", "海豚", "鲸鱼", "海豹", "章鱼", "水母", "海星", "海马",
            "乌龟", "鳄鱼", "蜥蜴", "青蛙", "蝴蝶", "蜜蜂", "蜻蜓", "瓢虫",
            "蚂蚁", "蜗牛", "刺猬", "松鼠", "兔子", "仓鼠", "狐狸", "河马",
            "犀牛", "骆驼", "孔雀", "鹦鹉", "猫头鹰", "啄木鸟", "火烈鸟", "北极熊"
        ]),
        (.food, [
            "火锅", "烧烤", "饺子", "包子", "馄饨", "汤圆", "粽子", "月饼",
            "油条", "豆浆", "煎饼", "小笼包", "螺蛳粉", "酸辣粉", "牛肉面", "蛋炒饭",
            "麻婆豆腐", "宫保鸡丁", "糖醋排骨", "番茄炒蛋", "烤鸭", "烤红薯", "臭豆腐", "麻辣烫",
            "汉堡", "披萨", "薯条", "寿司", "三明治", "意大利面", "冰淇淋", "爆米花",
            "棉花糖", "糖葫芦", "巧克力", "珍珠奶茶", "蛋挞", "榴莲", "西瓜", "草莓"
        ]),
        (.movies, [
            "孙悟空", "猪八戒", "唐僧", "沙僧", "哪吒", "二郎神", "葫芦娃", "黑猫警长",
            "哆啦梦", "大雄", "皮卡丘", "小智", "柯南", "蜡笔小新", "樱桃小丸子", "海绵宝宝",
            "派大星", "章鱼哥", "白雪公主", "灰姑娘", "小美人鱼", "长发公主", "艾莎", "米老鼠",
            "唐老鸭", "史迪奇", "小黄人", "功夫熊猫", "疯狂动物城", "熊出没", "熊大", "光头强",
            "哈利波特", "蜘蛛侠", "钢铁侠", "蝙蝠侠", "超人", "奥特曼", "喜羊羊", "灰太狼"
        ]),
        (.actions, [
            "刷牙", "洗脸", "梳头", "扎头发", "刮胡子", "打哈欠", "打喷嚏", "打嗝",
            "伸懒腰", "揉眼睛", "敷面膜", "照镜子", "吹蜡烛", "拧瓶盖", "剥香蕉", "吃西瓜",
            "嗑瓜子", "擀面条", "炒菜", "洗碗", "扫地", "拖地", "晾衣服", "叠被子",
            "骑自行车", "划船", "游泳", "跳绳", "踢足球", "打篮球", "打羽毛球", "打乒乓球",
            "举重", "滑雪", "放风筝", "钓鱼", "拍照", "弹钢琴", "拉小提琴", "指挥交通"
        ]),
        (.idioms, [
            "画蛇添足", "守株待兔", "掩耳盗铃", "亡羊补牢", "刻舟求剑", "井底之蛙", "狐假虎威", "对牛弹琴",
            "拔苗助长", "叶公好龙", "盲人摸象", "滥竽充数", "杯弓蛇影", "惊弓之鸟", "鸡飞狗跳", "鸡犬不宁",
            "狼吞虎咽", "眉飞色舞", "手舞足蹈", "抓耳挠腮", "目瞪口呆", "哭笑不得", "捧腹大笑", "垂头丧气",
            "东张西望", "左顾右盼", "蹑手蹑脚", "摇头晃脑", "昂首挺胸", "七手八脚", "一心二用", "一箭双雕",
            "大海捞针", "水中捞月", "海底捞月", "望梅止渴", "画饼充饥", "胸有成竹", "闻鸡起舞", "愚公移山"
        ])
    ].flatMap { (category: WordCategory, answers: [String]) in
        answers.map { PromptWord($0, category: category) }
    }

    static let minimumExpandedCount = 49_760

    private static let expandedResult: Result<[PromptWord], LoadError> = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        do {
            return .success(try loadExpandedWords(from: bundle.url(forResource: "ExpandedWords", withExtension: "tsv")))
        } catch let error as LoadError {
            return .failure(error)
        } catch {
            return .failure(.unreadableResource(error.localizedDescription))
        }
    }()

    static let expanded: [PromptWord] = {
        guard case .success(let words) = expandedResult else { return [] }
        return words
    }()

    static var loadError: LoadError? {
        guard case .failure(let error) = expandedResult else { return nil }
        return error
    }

    static let all: [PromptWord] = {
        var answers = Set<String>()
        return (classic + expanded).filter { answers.insert($0.answer).inserted }
    }()

    private static let wordsByCategory = Dictionary(grouping: all, by: \.category)

    static func words(in category: WordCategory) -> [PromptWord] {
        wordsByCategory[category] ?? []
    }

    static func words(in categories: Set<WordCategory>) -> [PromptWord] {
        WordCategory.allCases.filter { categories.contains($0) }.flatMap { words(in: $0) }
    }

    static func count(in category: WordCategory) -> Int {
        wordsByCategory[category]?.count ?? 0
    }

    static func count(in categories: Set<WordCategory>) -> Int {
        categories.reduce(0) { $0 + count(in: $1) }
    }

    static func loadExpandedWords(from url: URL?, minimumCount: Int = minimumExpandedCount) throws(LoadError) -> [PromptWord] {
        guard let url else { throw .missingResource }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .unreadableResource(error.localizedDescription)
        }
        let words = try parseExpandedWords(data)
        guard words.count >= minimumCount else {
            throw .insufficientWords(expected: minimumCount, actual: words.count)
        }
        return words
    }

    static func parseExpandedWords(_ data: Data) throws(LoadError) -> [PromptWord] {
        guard let text = String(data: data, encoding: .utf8) else { throw .invalidUTF8 }
        guard !text.isEmpty else { throw .emptyResource }
        var lines = text.components(separatedBy: "\n")
        if lines.last?.isEmpty == true { lines.removeLast() }
        let classicAnswers = Set(classic.map(\.answer))
        var answers = Set<String>()
        var words: [PromptWord] = []
        words.reserveCapacity(lines.count)
        for (offset, originalLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = originalLine.last == "\r" ? String(originalLine.dropLast()) : originalLine
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2 else { throw .malformedLine(lineNumber) }
            guard let category = WordCategory(rawValue: String(fields[0])) else {
                throw .unknownCategory(line: lineNumber, value: String(fields[0]))
            }
            let answer = String(fields[1])
            guard (2...8).contains(answer.count) else { throw .invalidLength(line: lineNumber, answer: answer) }
            guard answer.unicodeScalars.allSatisfy(isHan) else { throw .nonHanCharacters(line: lineNumber, answer: answer) }
            guard !classicAnswers.contains(answer) else { throw .classicConflict(line: lineNumber, answer: answer) }
            guard answers.insert(answer).inserted else { throw .duplicateAnswer(line: lineNumber, answer: answer) }
            words.append(PromptWord(answer, category: category))
        }
        guard !words.isEmpty else { throw .emptyResource }
        return words
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
             0x20000...0x2A6DF, 0x2A700...0x2B73F, 0x2B740...0x2B81F,
             0x2B820...0x2CEAF, 0x2CEB0...0x2EBEF, 0x2EBF0...0x2EE5F,
             0x2F800...0x2FA1F, 0x30000...0x3134F, 0x31350...0x323AF:
            true
        default:
            false
        }
    }

    enum LoadError: Error, Equatable, Sendable, LocalizedError {
        case missingResource
        case unreadableResource(String)
        case invalidUTF8
        case emptyResource
        case malformedLine(Int)
        case unknownCategory(line: Int, value: String)
        case invalidLength(line: Int, answer: String)
        case nonHanCharacters(line: Int, answer: String)
        case classicConflict(line: Int, answer: String)
        case duplicateAnswer(line: Int, answer: String)
        case insufficientWords(expected: Int, actual: Int)

        var errorDescription: String? {
            let detail: String
            switch self {
            case .missingResource: detail = "未找到扩展词库文件。"
            case .unreadableResource(let reason): detail = "无法读取扩展词库：\(reason)"
            case .invalidUTF8: detail = "扩展词库不是有效的 UTF-8 文本。"
            case .emptyResource: detail = "扩展词库为空。"
            case .malformedLine(let line): detail = "第 \(line) 行不是类别与词语两列。"
            case .unknownCategory(let line, let value): detail = "第 \(line) 行包含未知类别「\(value)」。"
            case .invalidLength(let line, let answer): detail = "第 \(line) 行词语「\(answer)」不符合 2–8 字限制。"
            case .nonHanCharacters(let line, let answer): detail = "第 \(line) 行词语「\(answer)」含有非汉字字符。"
            case .classicConflict(let line, let answer): detail = "第 \(line) 行词语「\(answer)」与基础词库重复。"
            case .duplicateAnswer(let line, let answer): detail = "第 \(line) 行词语「\(answer)」重复。"
            case .insufficientWords(let expected, let actual): detail = "扩展词库只有 \(actual) 个词，少于要求的 \(expected) 个。"
            }
            return "扩展词库加载失败：\(detail)当前仅保留基础词库。"
        }
    }
}
