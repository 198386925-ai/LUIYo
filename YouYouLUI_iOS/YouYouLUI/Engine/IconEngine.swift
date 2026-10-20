import CoreGraphics
import Foundation
import UIKit

/// One uploaded image as the engine sees it.
struct EngineFile {
let id = UUID()
let name: String
let data: Data
}

struct EngineItem: Decodable {
var title: String = ""
var file: String = ""
var files: [String] = []
var selectedFiles: [String] = []
var section: String = ""
var sections: [String] = []
var aliases: [String] = []
var category: String = ""
var alsoLiquidUI: Bool = false

enum CodingKeys: String, CodingKey {
case title, file, files, selectedFiles, section, sections, aliases, category, alsoLiquidUI
}

init(from decoder: Decoder) throws {
let box = try decoder.container(keyedBy: CodingKeys.self)
title = try box.decodeIfPresent(String.self, forKey:.title)?? ""
file = try box.decodeIfPresent(String.self, forKey:.file)?? ""
files = try box.decodeIfPresent([String].self, forKey:.files)?? []
selectedFiles = try box.decodeIfPresent([String].self, forKey:.selectedFiles)?? []
section = try box.decodeIfPresent(String.self, forKey:.section)?? ""
sections = try box.decodeIfPresent([String].self, forKey:.sections)?? []
aliases = try box.decodeIfPresent([String].self, forKey:.aliases)?? []
category = try box.decodeIfPresent(String.self, forKey:.category)?? ""
alsoLiquidUI = try box.decodeIfPresent(Bool.self, forKey:.alsoLiquidUI)?? false
}
}

struct EngineExtraRule: Decodable {
var file: String = ""
var targetFile: String?
var mode: String = "normal"
var titles: [String] = []

enum CodingKeys: String, CodingKey { case file, targetFile, mode, titles}

init(from decoder: Decoder) throws {
let box = try decoder.container(keyedBy: CodingKeys.self)
file = try box.decodeIfPresent(String.self, forKey:.file)?? ""
targetFile = try box.decodeIfPresent(String.self, forKey:.targetFile)
mode = try box.decodeIfPresent(String.self, forKey:.mode)?? "normal"
titles = try box.decodeIfPresent([String].self, forKey:.titles)?? []
}
}

/// Colour-processing configuration, read from the same persisted dictionary
/// the native colour editor writes.
struct EngineColorConfig {
var selectedLightEnabled = false
var selectedColor = "#1677ff"
var selectedLightCustom = false
var selectedDarkEnabled = false
var selectedDarkColor = "#ffffff"
var selectedDarkCustom = false
var allColorEnabled = false
var allColor = "#222222"
var darkModeInvertEnabled = false
var darkModeColor = "#ffffff"

init(_ values: [String: Any]) {
func bool(_ key: String) -> Bool { values[key] as? Bool?? false}
func color(_ key: String, _ fallback: String) -> String {
if let text = values[key] as? String,!text.isEmpty { return text}
return fallback
}
selectedLightEnabled = bool("selectedLightEnabled")
selectedDarkEnabled = bool("selectedDarkEnabled")
allColorEnabled = bool("allColorEnabled")
darkModeInvertEnabled = bool("darkModeInvertEnabled")
selectedLightCustom = bool("selectedLightCustom")
selectedDarkCustom = bool("selectedDarkCustom")
selectedColor = color("selectedColor", "#1677ff")
selectedDarkColor = color("selectedDarkColor", "#ffffff")
allColor = color("allColor", "#222222")
darkModeColor = color("darkModeColor", "#ffffff")
}
}

/// The app's work layer, fully native: catalog state, keyword batch import,
/// dual-category fill, colour processing and ZIP export. It reports state in
/// the same payload shape the homepage model has always consumed.
final class IconEngine {
var onState: (([String: Any]) -> Void)?
var onNotice: ((String) -> Void)?
var onExportReady: (() -> Void)?
var onShareZip: ((Data, String) -> Void)?

private(set) var items: [EngineItem] = []
private var extraRules: [EngineExtraRule] = []
private var fileToEntry: [String: Int] = [:]

private var chosenOrder: [Int] = []
private var chosen: [Int: EngineFile] = [:]
private var excluded: Set<Int> = []
private var fillFile: EngineFile?
private var extraFillApplied = false
private var activeCategory = "wechat"
private var statusOverride: String?
private var preparedZip: Data?

private var thumbnailCache: [UUID: Data] = [:]
private var imageCache: [UUID: CGImage] = [:]

private static let noInvertFiles: Set<String> = [
"icons_outlined_colorful_moment@3x.png", "icons_outlined_colorful_favorites@3x.png",
"icons_outlined_colorful_cards@3x.png", "icons_outlined_colorful_game@3x.png",
"icons_outlined_colorful_menu_browser@3x.png", "icons_filled_colorful_man@3x.png",
"icons_filled_colorful_female@3x.png", "Miniprogram_Icon_Default@3x.png",
"Miniprogram_Icon_DefaultDM@3x.png", "empty_album_music@3x.png", "ContactIndexShape@3x.png",
]
private static let canvasFiles: [String: (Int, Int)] = [
"arrow_left_regular@3x.png": (64, 128),
"arrow_right_regular@3x.png": (64, 128),
"arrow_right_filled@3x.png": (64, 128),
"weapp_capsule_more@3x.png": (190, 70),
]

init() {
loadBundledData()
}

private func loadBundledData() {
let decoder = JSONDecoder()
if let url = Bundle.main.url(forResource: "items", withExtension: "json", subdirectory: nil),
let data = try? Data(contentsOf: url),
let decoded = try? decoder.decode([EngineItem].self, from: data) {
items = decoded
}
if let url = Bundle.main.url(forResource: "extra-rules", withExtension: "json", subdirectory: nil),
let data = try? Data(contentsOf: url),
let decoded = try? decoder.decode([EngineExtraRule].self, from: data) {
extraRules = decoded
}
for (index, item) in items.enumerated() {
for name in item.files + item.selectedFiles { fileToEntry[name] = index}
}
}

// MARK: - State publishing

func start() { publish()}

private func currentStatus() -> String {
if let statusOverride { return statusOverride}
let total = items.filter { $0.category == activeCategory}.count
let done = chosenOrder.filter { items[$0].category == activeCategory}.count
return "已上传 \(done) / \(total) 项"
}

private func publish() {
var uploaded: [String: String] = [:]
var images: [String: String] = [:]
for index in chosenOrder {
guard let file = chosen[index] else { continue}
let key = file.id.uuidString
uploaded[String(index)] = key
if let thumbnail = thumbnail(for: file) {
images[key] = "data:image/png;base64," + thumbnail.base64EncodedString()
}
}
onState?(["uploadedCount": uploaded.count,
"uploaded": uploaded,
"images": images,
"status": currentStatus()])
}

private func thumbnail(for file: EngineFile) -> Data? {
if let cached = thumbnailCache[file.id] { return cached}
guard let image = decodedImage(file) else { return nil}
let data = EngineImageProcessing.thumbnailPNG(for: image)
if let data { thumbnailCache[file.id] = data}
return data
}

private func decodedImage(_ file: EngineFile) -> CGImage? {
if let cached = imageCache[file.id] { return cached}
let image = EngineImageProcessing.decodeImage(file.data)
if let image { imageCache[file.id] = image}
return image
}

// MARK: - Commands

func setCategory(_ category: String) {
activeCategory = category
statusOverride = nil
publish()
}

func remove(index: Int) {
chosen[index] = nil
chosenOrder.removeAll { $0 == index}
excluded.insert(index)
statusOverride = nil
publish()
}

func clear() {
chosen.removeAll()
chosenOrder.removeAll()
excluded.removeAll()
fillFile = nil
extraFillApplied = false
preparedZip = nil
statusOverride = nil
publish()
}

func colorsUpdated() { publish()}

private func setChosen(_ index: Int, _ file: EngineFile) {
if chosen[index] == nil { chosenOrder.append(index)}
chosen[index] = file
excluded.remove(index)
}

func receiveSingle(index: Int, file: EngineFile) {
guard items.indices.contains(index) else {
onNotice?("图标入口无效")
return
}
setChosen(index, file)
statusOverride = nil
publish()
}

func receiveFillImage(_ file: EngineFile) {
fillFile = file
statusOverride = "补全图片已选择：\(file.name)"
publish()
}

func applyFill(query: String) {
guard let fill = fillFile else {
onNotice?("请先选择一张\u{201C}一键补全图片\u{201D}")
return
}
extraFillApplied = true
let needle = query.trimmingCharacters(in:.whitespaces).lowercased()
var filled = 0
for (index, item) in items.enumerated() {
if!needle.isEmpty &&!item.title.lowercased().contains(needle) { continue}
if chosen[index] == nil &&!excluded.contains(index) {
setChosen(index, fill)
filled += 1
}
}
statusOverride = nil
publish()
var message = "已同时补全 LiquidUI + 原版微信，共 \(filled) 个空缺图标；没有网页关键词对应的命名规则也会使用这张补全图片"
if!excluded.isEmpty { message += "；已排除的图标保持不补全"}
onNotice?(message)
}

// MARK: - Batch import (keyword matching)

func receiveBatch(_ files: [EngineFile]) {
var matched = 0
var unmatched: [String] = []
var tooShort: [String] = []
for file in files {
let result = findItemByKeyword(file.name)
if result.index >= 0 {
setChosen(result.index, file)
matched += 1
} else if result.tooShort {
tooShort.append(file.name)
} else {
unmatched.append(file.name)
}
}
statusOverride = nil
publish()
if matched > 0 {
var message = "已按网页标题模糊关键词自动匹配 \(matched) 张图片"
if!unmatched.isEmpty {
message += "\n\n未匹配 \(unmatched.count) 张：\n" + unmatched.prefix(8).joined(separator: "\n")
if unmatched.count > 8 { message += "\n…还有 \(unmatched.count - 8) 张"}
message += "\n\n可使用网页标题中的模糊关键词，例如：底栏微信.png、扫一扫.png、转账.png、scan_filled.png；模糊关键词至少 3 个字，两个字请使用完整标题。"
}
if!tooShort.isEmpty {
message += "\n\n关键词少于 2 个字，已跳过 \(tooShort.count) 张：\n" + tooShort.prefix(8).joined(separator: "\n")
}
onNotice?(message)
} else {
var message = "没有匹配到网页标题关键词。\n\n模糊关键词至少 3 个字，例如：\n底栏微信.png\n扫一扫.png\nscan_filled.png\n两个字请使用完整标题，如：转账.png"
if!tooShort.isEmpty {
message += "\n\n其中 \(tooShort.count) 张图片的关键词少于 2 个字，已跳过。"
}
onNotice?(message)
}
}

private struct MatchResult {
var index = -1
var ambiguous = false
var tooShort = false
}

private func findItemByKeyword(_ filename: String) -> MatchResult {
let rawStem = Self.importFileStem(filename)
if!rawStem.isEmpty && rawStem.unicodeScalars.allSatisfy({ $0.value < 128}) {
if rawStem.count < 2 { return MatchResult(index: -1, ambiguous: false, tooShort: true)}
var hits: [Int] = []
for (index, item) in items.enumerated() {
if (item.files + item.selectedFiles).contains(where: { Self.importFileStem($0) == rawStem}) {
hits.append(index)
}
}
if hits.count == 1 { return MatchResult(index: hits[0], ambiguous: false, tooShort: false)}
return MatchResult(index: -1, ambiguous: hits.count > 1, tooShort: false)
}
let stem = Self.importKeywordNormalize(filename)
if stem.count < 2 { return MatchResult(index: -1, ambiguous: false, tooShort: true)}
struct Scored { let index: Int; let score: Int; let keyword: String; let own: Bool}
var scored: [Scored] = []
for (index, item) in items.enumerated() {
let titleKey = Self.importKeywordNormalize(Self.stripLiquidPrefix(item.title))
for keyword in Self.importKeywords(of: item) {
if keyword.count < 2 { continue}
var score = 0
if stem == keyword {
score = 20000 + keyword.count
} else if keyword.count >= 3 && stem.contains(keyword) {
score = 15000 + keyword.count
} else if stem.count >= 3 && keyword.contains(stem) {
score = 12000 + stem.count
} else {
let fuzzy = Self.longestCommonSubstringLength(stem, keyword)
if fuzzy >= 3 { score = 5000 + fuzzy * 100 - abs(stem.count - keyword.count)}
}
if score!= 0 { scored.append(Scored(index: index, score: score, keyword: keyword, own: keyword == titleKey))}
}
}
if scored.isEmpty { return MatchResult(index: -1, ambiguous: false, tooShort: false)}
scored.sort {
if $0.score!= $1.score { return $0.score > $1.score}
if $0.keyword.count!= $1.keyword.count { return $0.keyword.count > $1.keyword.count}
return $0.index < $1.index
}
let best = scored[0]
let top = scored.filter { $0.score == best.score}
let tied = Set(top.map { $0.index})
if tied.count > 1 {
let own = Set(top.filter { $0.own}.map { $0.index})
if own.count == 1, let only = own.first { return MatchResult(index: only, ambiguous: false, tooShort: false)}
return MatchResult(index: -1, ambiguous: true, tooShort: false)
}
return MatchResult(index: best.index, ambiguous: false, tooShort: false)
}

private static func stripLiquidPrefix(_ title: String) -> String {
var text = title
if text.hasPrefix("LiquidUI") { text = String(text.dropFirst("LiquidUI".count))}
return text.trimmingCharacters(in:.whitespaces)
}

private static var keywordStripSet: CharacterSet = {
var set = CharacterSet(charactersIn: "「」『』[]()（）<>《》·•—–_-+.,，。:：;；'\"“”‘’/\\|")
set.formUnion(.whitespaces)
return set
}()

static func importKeywordNormalize(_ value: String) -> String {
var text = value
text = regexReplace(text, pattern: "\\.[a-z0-9]{1,8}$", options: [.caseInsensitive])
text = regexReplace(text, pattern: "liquid\\s*ui", options: [.caseInsensitive])
text = regexReplace(text, pattern: "\\blui\\b", options: [.caseInsensitive])
text = regexReplace(text, pattern: "@\\d+x", options: [.caseInsensitive])
text = text.components(separatedBy: keywordStripSet).joined()
return text.lowercased()
}

static func importFileStem(_ name: String) -> String {
var text = regexReplace(name, pattern: "\\.[a-z0-9]{1,8}$", options: [.caseInsensitive])
text = regexReplace(text, pattern: "@\\d+x", options: [.caseInsensitive])
text = regexReplace(text, pattern: "_dark$", options: [.caseInsensitive])
return text.trimmingCharacters(in:.whitespaces).lowercased()
}

private static func regexReplace(_ value: String, pattern: String, options: NSRegularExpression.Options) -> String {
guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return value}
let range = NSRange(value.startIndex..., in: value)
return regex.stringByReplacingMatches(in: value, range: range, withTemplate: "")
}

private static func importKeywords(of item: EngineItem) -> [String] {
var seen: Set<String> = []
var out: [String] = []
for title in [item.title] + item.aliases {
let keyword = importKeywordNormalize(stripLiquidPrefix(title))
if!keyword.isEmpty && seen.insert(keyword).inserted { out.append(keyword)}
}
return out
}

private static func longestCommonSubstringLength(_ a: String, _ b: String) -> Int {
let first = Array(a), second = Array(b)
if first.isEmpty || second.isEmpty { return 0}
var dp = [Int](repeating: 0, count: second.count + 1)
var best = 0
for i in 1...first.count {
var previous = 0
for j in 1...second.count {
let old = dp[j]
if first[i - 1] == second[j - 1] {
dp[j] = previous + 1
if dp[j] > best { best = dp[j]}
} else {
dp[j] = 0
}
previous = old
}
}
return best
}
}

// MARK: - Export

extension IconEngine {
    func startExport() {
        guard !chosen.isEmpty else {
            onNotice?("请先上传至少一张图片")
            return
        }
        statusOverride = "正在生成 ZIP，请稍候…"
        publish()
        let snapshot = ExportSnapshot(order: chosenOrder,
                                      chosen: chosen,
                                      excluded: excluded,
                                      extraFillApplied: extraFillApplied,
                                      fillFile: fillFile,
                                      config: EngineColorConfig(ThemePreferences.shared.nativeIconColors))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data = self?.buildArchive(snapshot)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let data {
                    self.preparedZip = data
                    self.statusOverride = "ZIP 已生成，可以改名并分享"
                    self.publish()
                    self.onExportReady?()
                } else {
                    self.statusOverride = nil
                    self.publish()
                    self.onNotice?("ZIP 生成失败，请重试")
                }
            }
        }
    }

    func finishExport(name: String) {
        guard let data = preparedZip else {
            onNotice?("ZIP 还没有生成，请先点\u{201C}导出 ZIP\u{201D}")
            return
        }
        onShareZip?(data, Self.safeZipBaseName(name) + ".zip")
        statusOverride = "已打开系统分享"
        publish()
    }

    static func safeZipBaseName(_ value: String) -> String {
        var base = value.trimmingCharacters(in: .whitespaces)
        if base.isEmpty { base = "优优LUI图标包" }
        base = base.components(separatedBy: CharacterSet(charactersIn: "\\/:*?\"<>|")).joined(separator: "_")
        if base.lowercased().hasSuffix(".zip") { base = String(base.dropLast(4)) }
        return base.isEmpty ? "优优LUI图标包" : base
    }

    private struct ExportSnapshot {
        let order: [Int]
        let chosen: [Int: EngineFile]
        let excluded: Set<Int>
        let extraFillApplied: Bool
        let fillFile: EngineFile?
        let config: EngineColorConfig
    }

    private enum ConvertMode: String {
        case normal, dark, selected, selectedDark
    }

    /// Conversion context for one export run: decoding and converted PNGs are
    /// cached per run, exactly like the previous implementation, so colour
    /// changes between exports always take effect.
    private final class ExportContext {
        let config: EngineColorConfig
        var decoded: [UUID: CGImage] = [:]
        var converted: [String: Data] = [:]

        init(config: EngineColorConfig) { self.config = config }

        func image(_ file: EngineFile) -> CGImage? {
            if let cached = decoded[file.id] { return cached }
            let image = EngineImageProcessing.decodeImage(file.data)
            if let image { decoded[file.id] = image }
            return image
        }

        func data(_ file: EngineFile, mode: ConvertMode, canvas: (Int, Int)?) -> Data? {
            let key = "\(file.id.uuidString)|\(mode.rawValue)|\(canvas.map { "\($0.0)x\($0.1)" } ?? "-")"
            if let cached = converted[key] { return cached }
            guard let image = image(file) else { return nil }
            let result: Data?
            switch mode {
            case .normal: result = toNormal(image, canvas: canvas)
            case .selected: result = toSelected(image, canvas: canvas)
            case .dark: result = toDark(image, selected: false, canvas: canvas)
            case .selectedDark: result = toDark(image, selected: true, canvas: canvas)
            }
            if let result { converted[key] = result }
            return result
        }

        private func toNormal(_ image: CGImage, canvas: (Int, Int)?) -> Data? {
            let surface = EngineImageProcessing.draw(image, canvasSize: canvas)
            if config.allColorEnabled { surface.recolor(hex: config.allColor) }
            return surface.pngData()
        }

        private func toSelected(_ image: CGImage, canvas: (Int, Int)?) -> Data? {
            let surface = EngineImageProcessing.draw(image, canvasSize: canvas)
            if config.selectedLightEnabled {
                if config.selectedLightCustom {
                    surface.recolor(hex: config.selectedColor)
                } else {
                    surface.darken()
                }
            }
            return surface.pngData()
        }

        private func toDark(_ image: CGImage, selected: Bool, canvas: (Int, Int)?) -> Data? {
            let surface = EngineImageProcessing.draw(image, canvasSize: canvas)
            if selected {
                if config.selectedDarkEnabled {
                    if config.selectedDarkCustom {
                        surface.recolor(hex: config.selectedDarkColor)
                        return surface.pngData()
                    }
                    // Auto mode: derive from the light appearance settings.
                    // (The previous implementation did not invert here.)
                    if config.selectedLightEnabled {
                        if config.selectedLightCustom {
                            surface.recolor(hex: config.selectedColor)
                        } else {
                            surface.darken()
                        }
                    }
                } else {
                    return surface.pngData()
                }
            } else {
                if config.darkModeInvertEnabled {
                    if config.darkModeColor.lowercased() != "#ffffff" {
                        surface.recolor(hex: config.darkModeColor)
                    } else {
                        if config.allColorEnabled { surface.recolor(hex: config.allColor) }
                        surface.invert()
                    }
                }
            }
            return surface.pngData()
        }
    }

    private static func darkName(for name: String) -> String? {
        if name.lowercased().hasSuffix("@3x.png") {
            return String(name.dropLast(7)) + "_Dark@3x.png"
        }
        if name.lowercased().hasSuffix(".png") {
            return String(name.dropLast(4)) + "_Dark.png"
        }
        return nil
    }

    private func buildArchive(_ snapshot: ExportSnapshot) -> Data? {
        let context = ExportContext(config: snapshot.config)
        var order: [String] = []
        var blobs: [String: Data] = [:]
        func put(_ name: String, _ data: Data?) {
            guard let data else { return }
            if blobs[name] == nil { order.append(name) }
            blobs[name] = data
        }

        for index in snapshot.order {
            guard let file = snapshot.chosen[index] else { continue }
            let item = items[index]
            let groups: [(names: [String], mode: ConvertMode, darkMode: ConvertMode?)] = [
                (item.files.isEmpty ? [item.file] : item.files, .normal, .dark),
                (item.selectedFiles, .selected, .selectedDark),
            ]
            for group in groups {
                for name in group.names {
                    let canvas = Self.canvasFiles[name]
                    put(name, context.data(file, mode: group.mode, canvas: canvas))
                    if !Self.noInvertFiles.contains(name), let darkName = Self.darkName(for: name) {
                        let generateDark: Bool
                        switch group.darkMode {
                        case .dark: generateDark = snapshot.config.darkModeInvertEnabled
                        case .selectedDark: generateDark = snapshot.config.selectedDarkEnabled
                        default: generateDark = false
                        }
                        if generateDark {
                            put(darkName, context.data(file, mode: group.darkMode!, canvas: canvas))
                        }
                    }
                }
            }
        }

        // Naming-rule extensions: reuse the chosen image for a rule's target
        // file, or the fill image after a dual-category fill.
        for rule in extraRules {
            if let target = rule.targetFile, let entry = fileToEntry[target], snapshot.excluded.contains(entry) {
                continue
            }
            var source: EngineFile?
            if let target = rule.targetFile {
                for index in snapshot.order {
                    guard let candidate = snapshot.chosen[index] else { continue }
                    let names = items[index].files + items[index].selectedFiles
                    let entryNames = items[index].files.isEmpty ? [items[index].file] + items[index].selectedFiles : names
                    if entryNames.contains(target) && !snapshot.excluded.contains(index) {
                        source = candidate
                        break
                    }
                }
            }
            if source == nil && snapshot.extraFillApplied { source = snapshot.fillFile }
            guard let resolved = source else { continue }
            let selected = rule.mode == "selected"
            put(rule.file, context.data(resolved, mode: selected ? .selected : .normal, canvas: nil))
            // Dark variant for the extra file itself (same guards as before).
            if let target = rule.targetFile, Self.noInvertFiles.contains(target) { continue }
            addDarkVariant(forExtra: rule.file, source: resolved, selected: selected,
                           config: snapshot.config, context: context, put: put)
        }

        let entries = order.compactMap { name in blobs[name].map { ZipWriter.Entry(name: name, data: $0) } }
        if entries.isEmpty { return nil }
        return ZipWriter.archive(entries: entries)
    }

    private func addDarkVariant(forExtra name: String, source: EngineFile, selected: Bool,
                                config: EngineColorConfig, context: ExportContext,
                                put: (String, Data?) -> Void) {
        let lower = name.lowercased()
        guard lower.hasSuffix("@3x.png") else { return }
        if lower.hasSuffix("_dark@3x.png") || lower.hasSuffix("darkmode@3x.png") || lower.hasSuffix("_light@3x.png") { return }
        guard config.darkModeInvertEnabled else { return }
        let darkName = String(name.dropLast(7)) + "_Dark@3x.png"
        put(darkName, context.data(source, mode: selected ? .selectedDark : .dark, canvas: nil))
    }
}
