import CoreText
import UIKit

/// Owns the app fonts: a facade over FontLibrary (bundled + imported fonts,
/// per-area Latin/Chinese selections). `font` stays the settings-area base
/// font for the shell's tab bar / hero wiring; pages ask for their own area
/// through `font(for:)`. Applying fonts to views stays the shell's job.
final class ThemeFontController {
    let library = FontLibrary()

    /// The settings area's base font (10pt), nil when it uses the system font.
    private(set) var font: UIFont?

    /// Called on the main queue whenever any area's font changes.
    var onFontChanged: ((UIFont?) -> Void)?

    private var legacyStorageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ThemeFont.data")
    }

    init() {
        library.onSelectionsChanged = { [weak self] in
            guard let self else { return }
            self.font = self.font(for: .settings)
            self.onFontChanged?(self.font)
        }
    }

    /// Base font (10pt) for one page area; consumers scale with `withSize`.
    func font(for area: FontArea) -> UIFont? {
        library.uiFont(area: area, size: 10, weight: .regular, italic: false)
    }

    /// Restores imported fonts and selections saved by a previous launch,
    /// migrating the pre-library single imported font if one exists.
    @discardableResult
    func restore() -> Bool {
        library.loadImported()
        if let data = try? Data(contentsOf: legacyStorageURL), !data.isEmpty {
            if let faces = library.importFont(data: data, filename: "旧版导入字体.ttf"), let first = faces.first {
                for area in FontArea.allCases {
                    if first.coversLatin {
                        library.setSelection(area: area, chinese: false, value: "imp:" + first.id, notify: false)
                    }
                    if first.coversChinese {
                        library.setSelection(area: area, chinese: true, value: "imp:" + first.id, notify: false)
                    }
                }
            }
            try? FileManager.default.removeItem(at: legacyStorageURL)
        }
        font = font(for: .settings)
        return library.hasAnyCustomSelection
    }

    /// Legacy single-font import: imports the payload and selects it for the
    /// settings area (kept for the settings page's older call sites).
    @discardableResult
    func apply(_ data: Data) -> Bool {
        guard let faces = library.importFont(data: data, filename: "导入字体.ttf"), let first = faces.first else { return false }
        if first.coversLatin {
            library.setSelection(area: .settings, chinese: false, value: "imp:" + first.id, notify: false)
        }
        if first.coversChinese {
            library.setSelection(area: .settings, chinese: true, value: "imp:" + first.id, notify: false)
        }
        library.onSelectionsChanged?()
        return true
    }

    /// Drops every area's custom selection, back to the system font.
    func reset() {
        library.resetAllSelections()
    }
}
