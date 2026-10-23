import CoreText
import CryptoKit
import UIKit

/// The three pages whose fonts can be set independently.
enum FontArea: String, CaseIterable {
    case home, rules, settings
    var title: String {
        switch self {
        case .home: return "首页"
        case .rules: return "规则页"
        case .settings: return "设置页"
        }
    }
}

/// One selectable face of a user-imported font file (TTC files yield several).
struct ImportedFont {
    let id: String
    let fileKey: String
    let name: String
    let postScriptName: String
    let coversLatin: Bool
    let coversChinese: Bool
    let fileURL: URL
    let sizeBytes: Int
}

/// Font catalog (user-imported fonts only — the app ships no bundled
/// picker fonts since Build 38), per-area Latin/Chinese selections and
/// cascaded font vending. Latin and Chinese faces are chosen independently;
/// the cascade keeps Latin glyphs on the Latin face and CJK glyphs on the
/// Chinese face, like the reference implementation this is ported from.
final class FontLibrary {
    var onSelectionsChanged: (() -> Void)?

    // MARK: - Registration / face resolution

    private var registeredFiles: Set<String> = []

    private func registerFile(_ url: URL) {
        let key = url.path
        if registeredFiles.contains(key) { return }
        registeredFiles.insert(key)
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    private func descriptors(for url: URL) -> [CTFontDescriptor] {
        (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]) ?? []
    }

    // MARK: - Imported fonts

    private(set) var imported: [ImportedFont] = []

    var importedDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LUIYoFonts/Imported", isDirectory: true)
    }

    func loadImported() {
        migrateLegacySelectionsIfNeeded()
        sanitizeSelections()
        imported = []
        let dir = importedDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            imported.append(contentsOf: entries(forFile: url))
        }
    }

    private func entries(forFile url: URL) -> [ImportedFont] {
        registerFile(url)
        let fileKey = url.deletingPathExtension().lastPathComponent
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return descriptors(for: url).enumerated().map { index, descriptor in
            let psName = (CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String) ?? fileKey
            let fullName = (CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String) ?? psName
            let ct = CTFontCreateWithFontDescriptor(descriptor, 10, nil)
            let charset = CTFontCopyCharacterSet(ct) as CharacterSet
            let latin = charset.contains(UnicodeScalar(0x41)!) && charset.contains(UnicodeScalar(0x61)!)
            let chinese = charset.contains(UnicodeScalar(0x4E2D)!)
            return ImportedFont(id: fileKey + ":" + String(index), fileKey: fileKey, name: fullName,
                                postScriptName: psName, coversLatin: latin, coversChinese: chinese,
                                fileURL: url, sizeBytes: size)
        }
    }

    /// Imports font bytes into the library. Returns the faces created.
    @discardableResult
    func importFont(data: Data, filename: String) -> [ImportedFont]? {
        guard data.count > 0, data.count <= 64 * 1024 * 1024 else { return nil }
        guard !descriptorsFromData(data).isEmpty else { return nil }
        let digest = SHA256.hash(data: data)
        let fileKey = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        let ext = (filename as NSString).pathExtension.isEmpty ? "ttf" : (filename as NSString).pathExtension
        let dir = importedDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(String(fileKey) + "." + ext)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
        }
        let faces = entries(forFile: url)
        if !faces.isEmpty {
            imported.removeAll { $0.fileKey == String(fileKey) }
            imported.append(contentsOf: faces)
        }
        return faces.isEmpty ? nil : faces
    }

    private func descriptorsFromData(_ data: Data) -> [CTFontDescriptor] {
        (CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor]) ?? []
    }

    func deleteImported(fileKey: String) {
        let urls = Set(imported.filter { $0.fileKey == fileKey }.map { $0.fileURL })
        imported.removeAll { $0.fileKey == fileKey }
        for url in urls { try? FileManager.default.removeItem(at: url) }
        // Drop selections that pointed at the removed faces.
        for chinese in [false, true] {
            let value = selection(chinese: chinese)
            if value.hasPrefix("imp:") {
                let id = String(value.dropFirst(4))
                if !imported.contains(where: { $0.id == id }) {
                    setSelection(chinese: chinese, value: "system", notify: false)
                }
            }
        }
        onSelectionsChanged?()
    }

    func clearAllImported() {
        let keys = Set(imported.map { $0.fileKey })
        for key in keys { deleteImported(fileKey: key) }
    }

    var importedTotalBytes: Int {
        var seen: Set<String> = []
        var total = 0
        for face in imported where !seen.contains(face.fileKey) {
            seen.insert(face.fileKey)
            total += face.sizeBytes
        }
        return total
    }

    // MARK: - Selections (one Latin + one Chinese choice, gated per page)

    private func selectionKey(chinese: Bool) -> String {
        chinese ? "fontlib.sel.chinese" : "fontlib.sel.latin"
    }

    private func offKey(_ area: FontArea) -> String { "fontlib.off." + area.rawValue }

    /// One-time migration from the first release's per-area selections: the
    /// global choice takes the first custom pick found, and a page keeps the
    /// font only if it had a custom pick of its own.
    func migrateLegacySelectionsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "fontlib.sel.latin") == nil else { return }
        var latin = "system"
        var chinese = "system"
        var anyCustom = false
        var customAreas: [FontArea: Bool] = [:]
        for area in FontArea.allCases {
            let oldLatin = defaults.string(forKey: "fontlib.sel." + area.rawValue + ".latin") ?? "system"
            let oldChinese = defaults.string(forKey: "fontlib.sel." + area.rawValue + ".chinese") ?? "system"
            if latin == "system" { latin = oldLatin }
            if chinese == "system" { chinese = oldChinese }
            let custom = oldLatin != "system" || oldChinese != "system"
            customAreas[area] = custom
            if custom { anyCustom = true }
        }
        defaults.set(latin, forKey: "fontlib.sel.latin")
        defaults.set(chinese, forKey: "fontlib.sel.chinese")
        if anyCustom {
            for area in FontArea.allCases where customAreas[area] != true {
                defaults.set(true, forKey: offKey(area))
            }
        }
    }

    /// Selections saved by older builds can still point at a bundled
    /// family ("fam:<id>"). The bundled catalog was removed in Build 38,
    /// so any such selection is rewritten to the system font instead of
    /// dangling over a face that no longer exists.
    private func sanitizeSelections() {
        for chinese in [false, true] where selection(chinese: chinese).hasPrefix("fam:") {
            setSelection(chinese: chinese, value: "system", notify: false)
        }
    }

    func selection(chinese: Bool) -> String {
        UserDefaults.standard.string(forKey: selectionKey(chinese: chinese)) ?? "system"
    }

    func setSelection(chinese: Bool, value: String, notify: Bool = true) {
        UserDefaults.standard.set(value, forKey: selectionKey(chinese: chinese))
        if notify { onSelectionsChanged?() }
    }

    /// Whether the chosen font applies to a page (the page's checkbox).
    func isEnabled(_ area: FontArea) -> Bool {
        !UserDefaults.standard.bool(forKey: offKey(area))
    }

    func setEnabled(_ area: FontArea, _ enabled: Bool) {
        if enabled {
            UserDefaults.standard.removeObject(forKey: offKey(area))
        } else {
            UserDefaults.standard.set(true, forKey: offKey(area))
        }
        onSelectionsChanged?()
    }

    func resetAllSelections() {
        setSelection(chinese: false, value: "system", notify: false)
        setSelection(chinese: true, value: "system", notify: false)
        onSelectionsChanged?()
    }

    var hasAnyCustomSelection: Bool {
        (selection(chinese: false) != "system" || selection(chinese: true) != "system")
            && FontArea.allCases.contains { isEnabled($0) }
    }

    /// Human-readable summary of the current choices, e.g. "Inter · IBM Plex Sans SC".
    func summary() -> String {
        let latin = displayName(forSelection: selection(chinese: false))
        let chinese = displayName(forSelection: selection(chinese: true))
        if latin == nil && chinese == nil { return "使用默认字体" }
        return [latin, chinese].compactMap { $0 }.joined(separator: " · ")
    }

    func displayName(forSelection value: String) -> String? {
        if value == "system" { return nil }
        if value.hasPrefix("imp:") {
            let id = String(value.dropFirst(4))
            return imported.first { $0.id == id }?.name
        }
        return nil
    }

    // MARK: - Font vending

    private func face(forSelection value: String, chinese: Bool, size: CGFloat, weight: UIFont.Weight, italic: Bool) -> CTFont? {
        if value.hasPrefix("imp:") {
            let id = String(value.dropFirst(4))
            guard let face = imported.first(where: { $0.id == id }) else { return nil }
            registerFile(face.fileURL)
            let all = descriptors(for: face.fileURL)
            let index = Int(id.split(separator: ":").last.map(String.init) ?? "0") ?? 0
            guard all.indices.contains(index) else { return nil }
            return CTFontCreateWithFontDescriptor(all[index], size, nil)
        }
        return nil
    }

    /// The effective font for an area: nil when the page's switch is off or
    /// both scripts use the system font.
    func uiFont(area: FontArea, size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont? {
        guard isEnabled(area) else { return nil }
        return currentFont(size: size, weight: weight, italic: italic)
    }

    /// The chosen font itself, ignoring the per-page switches (previews).
    func currentFont(size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont? {
        let latin = face(forSelection: selection(chinese: false), chinese: false, size: size, weight: weight, italic: italic)
        let chinese = face(forSelection: selection(chinese: true), chinese: true, size: size, weight: weight, italic: italic)
        if latin == nil && chinese == nil { return nil }
        if let latin, chinese == nil { return latin as UIFont }
        if let chinese, latin == nil {
            let base = UIFont.systemFont(ofSize: size, weight: weight) as CTFont
            return Self.cascade(latin: base, chinese: chinese) as UIFont
        }
        if let latin, let chinese { return Self.cascade(latin: latin, chinese: chinese) as UIFont }
        return nil
    }

    /// Preview font for one imported-font row.
    func previewFont(imported face: ImportedFont, size: CGFloat) -> UIFont? {
        UIFont(name: face.postScriptName, size: size)
    }

    // MARK: - Latin/CJK cascade (ported from RGFontCascade)

    static let chineseCharacters: CharacterSet = {
        var result = CharacterSet()
        for range in [0x2E80...0x303F, 0x3100...0x312F, 0x31A0...0x31EF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
                      0xF900...0xFAFF, 0xFF01...0xFF60, 0xFFE0...0xFFE6, 0x20000...0x323AF] {
            result.insert(charactersIn: UnicodeScalar(range.lowerBound)!...UnicodeScalar(range.upperBound)!)
        }
        return result
    }()

    static func cascade(latin: CTFont, chinese: CTFont) -> CTFont {
        let latinCharacters = (CTFontCopyCharacterSet(latin) as CharacterSet).subtracting(chineseCharacters)
        let chineseSet = (CTFontCopyCharacterSet(chinese) as CharacterSet).intersection(chineseCharacters)
        let chineseDescriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(chinese),
            [kCTFontCharacterSetAttribute: chineseSet as CFCharacterSet] as CFDictionary)
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(latin),
            [kCTFontCharacterSetAttribute: latinCharacters as CFCharacterSet,
             kCTFontCascadeListAttribute: [chineseDescriptor]] as CFDictionary)
        return CTFontCreateCopyWithAttributes(latin, 0.0, nil, descriptor)
    }
}

/// Swaps every label/button/text-field font in a view tree for the given page
/// font (same point sizes), remembering each view's original system font so
/// the change is fully reversible. PillSegmentedControl manages its own
/// buttons and is skipped.
enum PageFontApplier {
    private static let originals = NSMapTable<UIView, UIFont>(keyOptions: .weakMemory, valueOptions: .strongMemory)

    static func apply(_ font: UIFont?, to root: UIView) {
        walk(root, font: font)
    }

    private static func walk(_ view: UIView, font: UIFont?) {
        if view is PillSegmentedControl { return }
        // Font specimens (the 更改字体 page's previews and catalog
        // rows) render each candidate face itself — never rewrite
        // a subtree the owner marked exempt.
        if view.accessibilityIdentifier == "luiyo.fontExempt" { return }
        var target: UIFont?
        var setFont: ((UIFont) -> Void)?
        if let label = view as? UILabel {
            target = label.font
            setFont = { label.font = $0 }
        } else if let button = view as? UIButton, let label = button.titleLabel {
            target = label.font
            setFont = { button.titleLabel?.font = $0 }
        } else if let field = view as? UITextField {
            target = field.font
            setFont = { field.font = $0 }
        }
        if let current = target, let setter = setFont {
            let original = originals.object(forKey: view) ?? current
            if originals.object(forKey: view) == nil { originals.setObject(original, forKey: view) }
            setter(font?.withSize(original.pointSize) ?? original)
        }
        for child in view.subviews { walk(child, font: font) }
    }
}
