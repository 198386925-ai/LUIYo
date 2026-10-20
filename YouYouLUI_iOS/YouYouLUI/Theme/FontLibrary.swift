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

/// A bundled font family. `files` maps a style key ("regular", "medium",
/// "semibold", "bold", "italic", ...) to a bundle file base name.
struct FontFamilyDef {
    let id: String
    let displayName: String
    let group: String
    let chinese: Bool
    let variable: Bool
    let files: [String: String]
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

/// Font catalog (bundled + imported), per-area Latin/Chinese selections and
/// cascaded font vending. Latin and Chinese faces are chosen independently;
/// the cascade keeps Latin glyphs on the Latin face and CJK glyphs on the
/// Chinese face, like the reference implementation this is ported from.
final class FontLibrary {
    var onSelectionsChanged: (() -> Void)?

    // MARK: - Catalog

    static let latinFamilies: [FontFamilyDef] = [
        FontFamilyDef(id: "inter", displayName: "Inter", group: "Inter", chinese: false, variable: false, files: [
            "regular": "Inter-Regular", "medium": "Inter-Medium", "semibold": "Inter-SemiBold", "bold": "Inter-Bold",
            "italic": "Inter-Italic", "mediumItalic": "Inter-MediumItalic", "semiboldItalic": "Inter-SemiBoldItalic", "boldItalic": "Inter-BoldItalic",
        ]),
        FontFamilyDef(id: "plexSans", displayName: "IBM Plex Sans", group: "IBM Plex", chinese: false, variable: false, files: [
            "regular": "IBMPlexSans-Regular", "medium": "IBMPlexSans-Medium", "semibold": "IBMPlexSans-SemiBold", "bold": "IBMPlexSans-Bold",
            "italic": "IBMPlexSans-Italic", "mediumItalic": "IBMPlexSans-MediumItalic", "semiboldItalic": "IBMPlexSans-SemiBoldItalic", "boldItalic": "IBMPlexSans-BoldItalic",
        ]),
        FontFamilyDef(id: "plexSerif", displayName: "IBM Plex Serif", group: "IBM Plex", chinese: false, variable: false, files: [
            "regular": "IBMPlexSerif-Regular", "medium": "IBMPlexSerif-Medium", "semibold": "IBMPlexSerif-SemiBold", "bold": "IBMPlexSerif-Bold",
            "italic": "IBMPlexSerif-Italic", "mediumItalic": "IBMPlexSerif-MediumItalic", "semiboldItalic": "IBMPlexSerif-SemiBoldItalic", "boldItalic": "IBMPlexSerif-BoldItalic",
        ]),
        FontFamilyDef(id: "plexMono", displayName: "IBM Plex Mono", group: "IBM Plex", chinese: false, variable: false, files: [
            "regular": "IBMPlexMono-Regular", "medium": "IBMPlexMono-Medium", "semibold": "IBMPlexMono-SemiBold", "bold": "IBMPlexMono-Bold",
            "italic": "IBMPlexMono-Italic", "mediumItalic": "IBMPlexMono-MediumItalic", "semiboldItalic": "IBMPlexMono-SemiBoldItalic", "boldItalic": "IBMPlexMono-BoldItalic",
        ]),
        FontFamilyDef(id: "googleSans", displayName: "Google Sans", group: "Google Sans", chinese: false, variable: true, files: [
            "regular": "GoogleSans-Variable",
        ]),
        FontFamilyDef(id: "googleSansFlex", displayName: "Google Sans Flex", group: "Google Sans", chinese: false, variable: true, files: [
            "regular": "GoogleSansFlex-Variable",
        ]),
        FontFamilyDef(id: "googleSansCode", displayName: "Google Sans Code", group: "Google Sans", chinese: false, variable: true, files: [
            "regular": "GoogleSansCode-Variable", "italic": "GoogleSansCode-VariableItalic",
        ]),
    ]

    static let chineseFamilies: [FontFamilyDef] = [
        FontFamilyDef(id: "plexSansSC", displayName: "IBM Plex Sans SC", group: "IBM Plex", chinese: true, variable: false, files: [
            "regular": "IBMPlexSansSC-Regular", "medium": "IBMPlexSansSC-Regular", "semibold": "IBMPlexSansSC-SemiBold", "bold": "IBMPlexSansSC-SemiBold",
        ]),
    ]

    func families(chinese: Bool) -> [FontFamilyDef] { chinese ? Self.chineseFamilies : Self.latinFamilies }

    func family(id: String) -> FontFamilyDef? {
        (Self.latinFamilies + Self.chineseFamilies).first { $0.id == id }
    }

    // MARK: - Registration / face resolution

    private var registeredFiles: Set<String> = []

    private func bundleURL(forBase base: String) -> URL? {
        Bundle.main.url(forResource: base, withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: base, withExtension: "ttf")
    }

    private func registerFile(_ url: URL) {
        let key = url.path
        if registeredFiles.contains(key) { return }
        registeredFiles.insert(key)
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    private func descriptors(for url: URL) -> [CTFontDescriptor] {
        (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]) ?? []
    }

    private func styleKey(weight: UIFont.Weight, italic: Bool) -> String {
        var base = "regular"
        if weight >= .bold { base = "bold" }
        else if weight >= .semibold { base = "semibold" }
        else if weight >= .medium { base = "medium" }
        if italic { return base == "regular" ? "italic" : base + "Italic" }
        return base
    }

    private func fileBase(for family: FontFamilyDef, weight: UIFont.Weight, italic: Bool) -> String? {
        let key = styleKey(weight: weight, italic: italic)
        if let exact = family.files[key] { return exact }
        let plain = styleKey(weight: weight, italic: false)
        if let plainFile = family.files[plain] { return plainFile }
        if let semibold = family.files["semibold"], weight >= .semibold { return semibold }
        return family.files["regular"]
    }

    /// Builds a CTFont for a bundled family face, honouring the wght axis of
    /// variable fonts when present.
    private func familyFont(_ family: FontFamilyDef, size: CGFloat, weight: UIFont.Weight, italic: Bool) -> CTFont? {
        guard let base = fileBase(for: family, weight: weight, italic: italic),
              let url = bundleURL(forBase: base) else { return nil }
        registerFile(url)
        guard let descriptor = descriptors(for: url).first else { return nil }
        var ct = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        if family.variable {
            let axes = (CTFontCopyVariationAxes(ct) as? [[String: Any]]) ?? []
            let wghtTag = 0x77676874
            if axes.contains(where: { ($0[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.intValue == wghtTag }) {
                let target: Double = weight >= .bold ? 700 : weight >= .semibold ? 600 : weight >= .medium ? 500 : 400
                let variation = [NSNumber(value: wghtTag): NSNumber(value: target)] as CFDictionary
                let varied = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(ct), [kCTFontVariationAttribute: variation] as CFDictionary)
                ct = CTFontCreateCopyWithAttributes(ct, size, nil, varied)
            }
        }
        return ct
    }

    // MARK: - Imported fonts

    private(set) var imported: [ImportedFont] = []

    var importedDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LUIYoFonts/Imported", isDirectory: true)
    }

    func loadImported() {
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
            let fullName = (CTFontDescriptorCopyAttribute(descriptor, kCTFontFullNameAttribute) as? String) ?? psName
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
        for area in FontArea.allCases {
            for chinese in [false, true] {
                let value = selection(area: area, chinese: chinese)
                if value.hasPrefix("imp:") {
                    let id = String(value.dropFirst(4))
                    if !imported.contains(where: { $0.id == id }) {
                        setSelection(area: area, chinese: chinese, value: "system", notify: false)
                    }
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

    var bundledTotalBytes: Int {
        var total = 0
        for family in Self.latinFamilies + Self.chineseFamilies {
            for base in Set(family.files.values) {
                if let url = bundleURL(forBase: base),
                   let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0 {
                    total += size
                }
            }
        }
        return total
    }

    // MARK: - Selections (per area, Latin and Chinese independent)

    private func defaultsKey(area: FontArea, chinese: Bool) -> String {
        "fontlib.sel." + area.rawValue + (chinese ? ".chinese" : ".latin")
    }

    func selection(area: FontArea, chinese: Bool) -> String {
        UserDefaults.standard.string(forKey: defaultsKey(area: area, chinese: chinese)) ?? "system"
    }

    func setSelection(area: FontArea, chinese: Bool, value: String, notify: Bool = true) {
        UserDefaults.standard.set(value, forKey: defaultsKey(area: area, chinese: chinese))
        if notify { onSelectionsChanged?() }
    }

    func resetAllSelections() {
        for area in FontArea.allCases {
            setSelection(area: area, chinese: false, value: "system", notify: false)
            setSelection(area: area, chinese: true, value: "system", notify: false)
        }
        onSelectionsChanged?()
    }

    var hasAnyCustomSelection: Bool {
        FontArea.allCases.contains { area in
            selection(area: area, chinese: false) != "system" || selection(area: area, chinese: true) != "system"
        }
    }

    /// Human-readable summary of one area's selections, e.g. "Inter · IBM Plex Sans SC".
    func summary(area: FontArea) -> String {
        let latin = displayName(forSelection: selection(area: area, chinese: false))
        let chinese = displayName(forSelection: selection(area: area, chinese: true))
        if latin == nil && chinese == nil { return "使用默认字体" }
        return [latin, chinese].compactMap { $0 }.joined(separator: " · ")
    }

    func displayName(forSelection value: String) -> String? {
        if value == "system" { return nil }
        if value.hasPrefix("fam:") { return family(id: String(value.dropFirst(4)))?.displayName }
        if value.hasPrefix("imp:") {
            let id = String(value.dropFirst(4))
            return imported.first { $0.id == id }?.name
        }
        return nil
    }

    // MARK: - Font vending

    private func face(forSelection value: String, chinese: Bool, size: CGFloat, weight: UIFont.Weight, italic: Bool) -> CTFont? {
        if value.hasPrefix("fam:") {
            guard let def = family(id: String(value.dropFirst(4))) else { return nil }
            return familyFont(def, size: size, weight: weight, italic: italic)
        }
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

    /// The effective font for an area, or nil when both scripts use the system font.
    func uiFont(area: FontArea, size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont? {
        let latin = face(forSelection: selection(area: area, chinese: false), chinese: false, size: size, weight: weight, italic: italic)
        let chinese = face(forSelection: selection(area: area, chinese: true), chinese: true, size: size, weight: weight, italic: italic)
        if latin == nil && chinese == nil { return nil }
        if let latin, chinese == nil { return latin as UIFont }
        if let chinese, latin == nil {
            let base = UIFont.systemFont(ofSize: size, weight: weight) as CTFont
            return Self.cascade(latin: base, chinese: chinese) as UIFont
        }
        if let latin, let chinese { return Self.cascade(latin: latin, chinese: chinese) as UIFont }
        return nil
    }

    /// Preview font for one catalog row.
    func previewFont(family def: FontFamilyDef, size: CGFloat) -> UIFont? {
        familyFont(def, size: size, weight: .regular, italic: false).map { $0 as UIFont }
    }

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
