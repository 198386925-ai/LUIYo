import Foundation

/// LiquidUI 气泡包 · 文件名识别（Swift 版，LUBubbleNaming 的一比一移植）
///
/// 用途：把「作者上传的 zip 里的图片文件名」解析成具体槽位。
/// 纯 Foundation 实现，不依赖 UIKit，也不需要网络。
///
/// 规则依据：插件 1.98 / 微信 8.0.79
/// 数据来源：bundle 里的 bubble-naming-rules.json
///
/// 判定顺序（和 ObjC 版保持一致）：
///   0. 过滤非图片后缀
///   1. 取倍数 @3x / @2x / @1x
///   2. 判日夜（文件名 + 目录名）
///   3. 分三种写法：中文名 / 微信原生英文名 / 通用英文名
///   4. 查槽位表

enum BubbleSide: Int {
    case receiver = 0   // 对方（左）
    case sender = 1     // 自己（右）
}

enum BubblePosition: Int {
    case top = 0     // 连发第一条
    case middle = 1  // 连发中间
    case end = 2     // 连发最后一条
    case single = 3  // 单独一条
}

/// 一个槽位：聊天气泡里的一个具体位置
final class BubbleSlot {
    var identifier: String = ""   // @"text:receiver:top" / @"hb:sender:"
    var type: String = ""         // text / hb / aa / gift / app / common / voice
    var nativeName: String = ""   // 微信原生名，如 ChatRoom_Bubble_HB_Receiver
    var cnName: String = ""       // 中文名，仅文字气泡有，如「左上」（其它槽位为空串，对应 ObjC 的 nil）
    var side: BubbleSide = .receiver
    var position: BubblePosition = .single  // 仅文字气泡有意义
    var desc: String = ""         // 中文说明
    /// 参与匹配的 token（已去掉 chatroom/bubble/white/green）
    var tokensForMatch: [String] = []

    init() {}
}

/// 一次解析的结果
final class BubbleMatch {
    var slot: BubbleSlot?     // 认不出时为 nil（应放入「未分组」让用户手动摆）
    var isNight: Bool = false        // 是否夜间（深色模式）版本
    var isHighlighted: Bool = false  // 是否按下态 _HL
    var scale: Int = 0               // 倍数，0 表示文件名没写
    var reason: String?              // 认不出时说明原因，便于排查

    init() {}
}

final class BubbleNaming {
    static let shared = BubbleNaming()

    private var allTextSlots: [BubbleSlot] = []
    private var allOtherSlots: [BubbleSlot] = []
    private var tokenLookup: [String: BubbleSlot] = [:]  // 排序后的 token 串 -> slot
    private var noiseWords: Set<String> = []             // chatroom/bubble/white/green
    private var keywords: [String: Any] = [:]
    private var sideKeys = ["receiver", "sender"]
    private var positionKeys = ["top", "middle", "end", "single"]

    private init() {
        loadRules()
    }

    // MARK: - 载入规则

    private func loadRules() {
        // 找不到 json 时退化为空表（保证不崩，只是识别能力下降）
        var json: [String: Any] = [:]
        if let path = Bundle.main.path(forResource: "bubble-naming-rules", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let parsed = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            json = parsed
        }

        keywords = json["keywords"] as? [String: Any] ?? [:]
        let ignoreWords = (json["微信原生英文名"] as? [String: Any])?["忽略词"] as? [String]
        noiseWords = Set(ignoreWords ?? ["chatroom", "bubble", "white", "green"])

        var texts: [BubbleSlot] = []
        for d in json["textSlots"] as? [[String: Any]] ?? [] {
            let s = BubbleSlot()
            s.identifier = d["id"] as? String ?? ""
            s.nativeName = d["en"] as? String ?? ""
            s.cnName = d["cn"] as? String ?? ""
            s.desc = d["desc"] as? String ?? ""
            s.type = "text"
            s.side = (d["side"] as? String) == "sender" ? .sender : .receiver
            s.position = position(from: d["pos"] as? String ?? "")
            s.tokensForMatch = d["tokens"] as? [String] ?? []
            texts.append(s)
        }
        var others: [BubbleSlot] = []
        for d in json["otherSlots"] as? [[String: Any]] ?? [] {
            let s = BubbleSlot()
            s.identifier = d["id"] as? String ?? ""
            s.nativeName = d["en"] as? String ?? ""
            s.desc = d["desc"] as? String ?? ""
            s.type = d["cat"] as? String ?? ""
            s.side = (d["side"] as? String) == "sender" ? .sender : .receiver
            s.position = .single
            s.tokensForMatch = d["tokens"] as? [String] ?? []
            others.append(s)
        }
        allTextSlots = texts
        allOtherSlots = others

        // token 集合 -> 槽位（排序后拼成字符串做 key）
        var lookup: [String: BubbleSlot] = [:]
        for s in texts + others {
            let tokens = s.tokensForMatch
            if tokens.isEmpty { continue }
            lookup[tokens.sorted().joined(separator: "|")] = s
        }
        tokenLookup = lookup
    }

    private func position(from str: String) -> BubblePosition {
        if str == "top" { return .top }
        if str == "middle" { return .middle }
        if str == "end" { return .end }
        return .single
    }

    // MARK: - 工具

    /// 是否含中文字符
    private static func hasCJK(_ s: String) -> Bool {
        for scalar in s.unicodeScalars {
            if scalar.value >= 0x4E00 && scalar.value <= 0x9FFF { return true }
        }
        return false
    }

    /// 按非字母数字切分成 token（全小写）
    private static func tokens(_ s: String) -> [String] {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    // MARK: - 解析

    /// 解析：文件名 + 所在目录（相对 zip 根，如 ["夜间"]）
    /// 返回的 match.slot 为 nil 表示认不出，应放入「未分组」让用户手动摆
    func matchFileName(_ fileName: String, directories: [String]) -> BubbleMatch {
        let m = BubbleMatch()
        m.scale = 0

        // 0. 后缀过滤
        let ext = (fileName as NSString).pathExtension.lowercased()
        let okExt: Set<String> = ["png", "jpg", "jpeg", "webp", "heic"]
        if !okExt.contains(ext) {
            m.reason = "不是图片格式"
            return m
        }

        // 1. 取倍数
        var stem = (fileName as NSString).deletingPathExtension
        let stemNS = stem as NSString
        let at = stemNS.range(of: "@", options: .backwards)
        if at.location != NSNotFound && stemNS.length > at.location + 2 {
            let tail = stemNS.substring(from: at.location + 1).lowercased()
            if tail.hasSuffix("x") && tail.count >= 2 {
                let num = String(tail.dropLast())
                if !num.isEmpty && num.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil {
                    m.scale = Int(num) ?? 0
                    stem = stemNS.substring(to: at.location)
                }
            }
        }

        // 2. 日夜：文件名和目录名都看
        let nightByFile = isNightInText(stem)
        let dayByFile = isDayInText(stem)
        var nightByDir = false
        var dayByDir = false
        for d in directories {
            if isNightInDirectoryName(d) { nightByDir = true }
            if isDayInDirectoryName(d) { dayByDir = true }
        }
        let night = nightByFile || nightByDir
        let day = dayByFile || dayByDir
        if night && day {
            m.reason = "同时出现夜间和日间，认不出"
            return m
        }
        m.isNight = night

        // 3. 按下态（仅英文名）
        let tokens = BubbleNaming.tokens(stem)
        m.isHighlighted = tokens.contains("hl")

        // 4. 分支解析
        var slot: BubbleSlot?
        if !BubbleNaming.hasCJK(stem) {
            // 微信原生英文名：去掉 noise / dark / hl 后比较 token 集合
            var clean: [String] = []
            for t in tokens {
                if t == "dark" || t == "hl" { continue }
                if noiseWords.contains(t) { continue }
                clean.append(t)
            }
            let sorted = clean.sorted()
            slot = tokenLookup[sorted.joined(separator: "|")]
            if slot == nil && !clean.isEmpty {
                m.reason = "原生名拼错或槽位不存在"
            }
        }
        if slot == nil {
            // 中文名 / 通用英文名：按关键词找侧别和位置
            let side = sideInText(stem, tokens: tokens)
            let pos = positionInText(stem, tokens: tokens)
            if side == "dup" { m.reason = "侧别冲突（同时有左和右）"; return m }
            if pos == "dup" { m.reason = "位置冲突（同时有两个位置词）"; return m }
            if side == nil { m.reason = "认不出是对方还是自己"; return m }
            for s in allTextSlots {
                let sideStr = s.side == .sender ? "sender" : "receiver"
                let p = position(from: pos ?? "single")
                if sideStr == side && s.position == p { slot = s; break }
            }
        }

        m.slot = slot
        return m
    }

    private func isNightInText(_ text: String) -> Bool {
        let night = (keywords["主题"] as? [String: Any])?["night"] as? [String: Any] ?? [:]
        for w in night["中文"] as? [String] ?? [] { if text.contains(w) { return true } }
        let tokens = BubbleNaming.tokens(text)
        for w in night["英文"] as? [String] ?? [] { if tokens.contains(w) { return true } }
        return false
    }

    private func isDayInText(_ text: String) -> Bool {
        let day = (keywords["主题"] as? [String: Any])?["day"] as? [String: Any] ?? [:]
        for w in day["中文"] as? [String] ?? [] { if text.contains(w) { return true } }
        let tokens = BubbleNaming.tokens(text)
        for w in day["英文"] as? [String] ?? [] { if tokens.contains(w) { return true } }
        return false
    }

    // 注意：单字「黑」「日」在文件夹名上不算（防「黑名单」「日期」误伤）
    // —— 文件夹名表里本身就没有单字项，这里只按表匹配，和 ObjC 版一致
    private func isNightInDirectoryName(_ name: String) -> Bool {
        let night = (keywords["主题"] as? [String: Any])?["night"] as? [String: Any] ?? [:]
        for w in night["文件夹名"] as? [String] ?? [] {
            if name.contains(w) { return true }
        }
        return false
    }

    private func isDayInDirectoryName(_ name: String) -> Bool {
        let day = (keywords["主题"] as? [String: Any])?["day"] as? [String: Any] ?? [:]
        for w in day["文件夹名"] as? [String] ?? [] {
            if name.contains(w) { return true }
        }
        return false
    }

    private func sideInText(_ text: String, tokens: [String]) -> String? {
        var found: String?
        let cjk = BubbleNaming.hasCJK(text)
        for key in sideKeys {
            let kw = ((keywords["侧别"] as? [String: Any])?[sideJSONKey(key)] as? [String: Any]) ?? [:]
            let words = cjk ? (kw["中文"] as? [String] ?? []) : (kw["英文"] as? [String] ?? [])
            for w in words {
                let hit = cjk ? text.contains(w) : tokens.contains(w)
                if hit {
                    if found != nil { return "dup" }
                    found = key
                }
            }
        }
        return found
    }

    private func sideJSONKey(_ key: String) -> String {
        key == "sender" ? "sender(自己/右)" : "receiver(对方/左)"
    }

    private func positionInText(_ text: String, tokens: [String]) -> String? {
        var found: String?
        let cjk = BubbleNaming.hasCJK(text)
        for key in positionKeys {
            let kw = ((keywords["位置"] as? [String: Any])?[key] as? [String: Any]) ?? [:]
            let words = cjk ? (kw["中文"] as? [String] ?? []) : (kw["英文"] as? [String] ?? [])
            for w in words {
                let hit = cjk ? text.contains(w) : tokens.contains(w)
                if hit {
                    if found != nil { return "dup" }
                    found = key
                }
            }
        }
        return found
    }

    // MARK: - 输出

    func textSlots() -> [BubbleSlot] { allTextSlots }
    func otherSlots() -> [BubbleSlot] { allOtherSlots }

    /// 生成导出用的文件名，如「左上@3x.png」或「夜间/左上@3x.png」
    /// mode: "cn" 中文名 / "en" 微信原生名
    /// scale: 3 写 @3x，2 写 @2x，0 不写
    func outputName(for slot: BubbleSlot, night: Bool, scale: Int, mode: String) -> String {
        let useCN = mode == "cn" && !slot.cnName.isEmpty
        var base: String
        var prefix = ""
        if useCN {
            base = slot.cnName
            if night { prefix = "夜间/" }   // 中文名：夜间版放进「夜间」文件夹
        } else {
            base = slot.nativeName
            if night { base += "_Dark" }
        }
        var suffix = ""
        if scale == 3 { suffix = "@3x" }
        else if scale == 2 { suffix = "@2x" }
        return "\(prefix)\(base)\(suffix).png"
    }
}
