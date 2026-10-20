import UIKit
import UniformTypeIdentifiers

/// The 更改字体 page: per-area （首页/规则页/设置页） Latin and Chinese fonts are
/// chosen independently from the bundled catalog or imported files, with a
/// live preview. Opened from the settings theme fold's 自定义字体 entry.
final class FontSettingsViewController: UIViewController {
    private let fontController: ThemeFontController
    private var library: FontLibrary { fontController.library }
    /// Fired whenever selections change (the settings entry subtitle refreshes).
    var onChanged: (() -> Void)?

    private var area: FontArea = .settings
    private var chineseTab = false
    private var query = ""

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var previewBig: UILabel!
    private var previewSub: UILabel!
    private var previewStyles: UILabel!
    private var previewDigits: UILabel!
    private let listStack = UIStackView()
    private var searchField: UITextField!
    private var downloadedSizeLabel: UILabel!
    private var importedSizeLabel: UILabel!

    init(fontController: ThemeFontController) {
        self.fontController = fontController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x12 / 255, green: 0x12 / 255, blue: 0x14 / 255, alpha: 1)
                : UIColor(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255, alpha: 1)
        }
        buildUI()
        rebuildList()
        refreshPreview()
        refreshStorage()
    }

    // MARK: - Layout

    private func buildUI() {
        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)), for: .normal)
        back.tintColor = UIAppColors.inkDynamic
        back.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        let title = UILabel()
        title.text = "更改字体"
        title.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        title.textColor = UIAppColors.inkDynamic
        let header = UIStackView(arrangedSubviews: [back, title])
        header.axis = .horizontal
        header.spacing = 6
        header.alignment = .center
        view.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false

        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        stack.axis = .vertical
        stack.spacing = 12
        scrollView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])

        // 应用位置: the three pages can use different fonts.
        let areaLabel = sectionLabel("应用位置")
        stack.addArrangedSubview(areaLabel)
        let areaControl = PillSegmentedControl()
        areaControl.options = FontArea.allCases.map { ($0.rawValue, $0.title) }
        areaControl.setSelectedValue(area.rawValue)
        areaControl.onChange = { [weak self] value in
            guard let self, let next = FontArea(rawValue: value) else { return }
            self.area = next
            self.rebuildList()
            self.refreshPreview()
        }
        stack.addArrangedSubview(areaControl)
        stack.setCustomSpacing(16, after: areaControl)

        stack.addArrangedSubview(previewCard())

        let scriptControl = PillSegmentedControl()
        scriptControl.options = [("latin", "英文字体"), ("chinese", "中文字体")]
        scriptControl.setSelectedValue("latin")
        scriptControl.onChange = { [weak self] value in
            self?.chineseTab = (value == "chinese")
            self?.rebuildList()
        }
        stack.addArrangedSubview(scriptControl)

        stack.addArrangedSubview(searchCard())
        stack.addArrangedSubview(listCard())

        let notes = UILabel()
        notes.numberOfLines = 0
        notes.font = UIFont.systemFont(ofSize: 12.5)
        notes.textColor = UIAppColors.secondary
        notes.text = "支持不超过 64 MB 的 TTF、OTF 和 TTC，TTC 内所有支持的字体会加入字体库，可分别选择中英文字体。\n英文字母、数字和英文标点使用英文字体；汉字及中文标点使用中文字体，两项选择只应用到上方选中的页面。"
        stack.addArrangedSubview(notes)

        stack.addArrangedSubview(storageCard())

        let restore = UIButton(type: .system)
        restore.setTitle("恢复系统默认字体", for: .normal)
        restore.titleLabel?.font = UIFont.systemFont(ofSize: 15)
        restore.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)
        stack.addArrangedSubview(restore)
    }

    private func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = UIAppColors.inkDynamic
        return label
    }

    private func previewCard() -> UIView {
        let card = GlassCardView(radius: 26)
        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 6
        card.content.addSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.content.leadingAnchor, constant: 16),
            inner.trailingAnchor.constraint(equalTo: card.content.trailingAnchor, constant: -16),
            inner.topAnchor.constraint(equalTo: card.content.topAnchor, constant: 14),
            inner.bottomAnchor.constraint(equalTo: card.content.bottomAnchor, constant: -14),
        ])
        let header = UILabel()
        header.text = "字体预览"
        header.font = UIFont.systemFont(ofSize: 12)
        header.textColor = UIAppColors.secondary
        previewBig = UILabel()
        previewBig.text = "Hello, LUIYo!"
        previewSub = UILabel()
        previewSub.text = "界面文字 · 中文字体自动回退"
        previewSub.textColor = UIAppColors.secondary
        previewStyles = UILabel()
        previewDigits = UILabel()
        previewDigits.text = "0123456789 → # «="
        for label in [header, previewBig, previewSub, previewStyles, previewDigits] { inner.addArrangedSubview(label!) }
        return card
    }

    private func searchCard() -> UIView {
        let card = GlassCardView(radius: 20)
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = UIAppColors.secondary
        icon.contentMode = .scaleAspectFit
        searchField = UITextField()
        searchField.placeholder = "搜索字体"
        searchField.font = UIFont.systemFont(ofSize: 14)
        searchField.textColor = UIAppColors.inkDynamic
        searchField.clearButtonMode = .whileEditing
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        let row = UIStackView(arrangedSubviews: [icon, searchField])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        card.content.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.content.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: card.content.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: card.content.topAnchor),
            row.bottomAnchor.constraint(equalTo: card.content.bottomAnchor),
            row.heightAnchor.constraint(equalToConstant: 40),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
        ])
        return card
    }

    private func listCard() -> UIView {
        let card = GlassCardView(radius: 26)
        listStack.axis = .vertical
        listStack.spacing = 2
        card.content.addSubview(listStack)
        listStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            listStack.leadingAnchor.constraint(equalTo: card.content.leadingAnchor, constant: 8),
            listStack.trailingAnchor.constraint(equalTo: card.content.trailingAnchor, constant: -8),
            listStack.topAnchor.constraint(equalTo: card.content.topAnchor, constant: 8),
            listStack.bottomAnchor.constraint(equalTo: card.content.bottomAnchor, constant: -8),
        ])
        return card
    }

    private func storageCard() -> UIView {
        let card = GlassCardView(radius: 26)
        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 10
        card.content.addSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.content.leadingAnchor, constant: 16),
            inner.trailingAnchor.constraint(equalTo: card.content.trailingAnchor, constant: -16),
            inner.topAnchor.constraint(equalTo: card.content.topAnchor, constant: 14),
            inner.bottomAnchor.constraint(equalTo: card.content.bottomAnchor, constant: -14),
        ])
        let title = sectionLabel("字体存储")
        inner.addArrangedSubview(title)
        downloadedSizeLabel = UILabel()
        importedSizeLabel = UILabel()
        inner.addArrangedSubview(storageRow(title: "内置字体", value: downloadedSizeLabel))
        inner.addArrangedSubview(storageRow(title: "已导入", value: importedSizeLabel))
        let clear = UIButton(type: .system)
        clear.setTitle("清理已导入字体", for: .normal)
        clear.setTitleColor(.systemRed, for: .normal)
        clear.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        clear.contentHorizontalAlignment = .leading
        clear.addTarget(self, action: #selector(clearImportedTapped), for: .touchUpInside)
        inner.addArrangedSubview(clear)
        return card
    }

    private func storageRow(title: String, value: UILabel) -> UIView {
        let name = UILabel()
        name.text = title
        name.font = UIFont.systemFont(ofSize: 14)
        name.textColor = UIAppColors.inkDynamic
        value.font = UIFont.systemFont(ofSize: 14)
        value.textColor = UIAppColors.secondary
        let row = UIStackView(arrangedSubviews: [name, UIView(), value])
        row.axis = .horizontal
        return row
    }

    // MARK: - List

    private func rebuildList() {
        for view in listStack.arrangedSubviews {
            listStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let current = library.selection(area: area, chinese: chineseTab)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()

        if q.isEmpty || "系统默认".contains(q) {
            listStack.addArrangedSubview(fontRow(name: "系统默认",
                                                 preview: previewText(),
                                                 previewFont: UIFont.systemFont(ofSize: 12),
                                                 selected: current == "system",
                                                 value: "system"))
        }

        var lastGroup: String?
        for family in library.families(chinese: chineseTab) {
            if !q.isEmpty && !family.displayName.lowercased().contains(q) { continue }
            if family.group != lastGroup {
                lastGroup = family.group
                listStack.addArrangedSubview(groupHeader(family.group))
            }
            listStack.addArrangedSubview(fontRow(name: family.displayName,
                                                 preview: previewText(),
                                                 previewFont: library.previewFont(family: family, size: 12),
                                                 selected: current == "fam:" + family.id,
                                                 value: "fam:" + family.id))
        }

        let faces = library.imported.filter { chineseTab ? $0.coversChinese : $0.coversLatin }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) }
        if !faces.isEmpty {
            listStack.addArrangedSubview(groupHeader("已导入"))
            for face in faces {
                let row = fontRow(name: face.name,
                                  preview: previewText(),
                                  previewFont: library.previewFont(imported: face, size: 12),
                                  selected: current == "imp:" + face.id,
                                  value: "imp:" + face.id)
                let press = UILongPressGestureRecognizer(target: self, action: #selector(importedLongPressed(_:)))
                press.minimumPressDuration = 0.6
                row.addGestureRecognizer(press)
                listStack.addArrangedSubview(row)
            }
        }

        listStack.addArrangedSubview(importRow())
    }

    private func previewText() -> String {
        chineseTab ? "中文字体示例：你好，世界。" : "The quick brown fox 0123"
    }

    private func groupHeader(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = UIAppColors.inkDynamic
        let container = UIView()
        container.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
        ])
        return container
    }

    private func fontRow(name: String, preview: String, previewFont: UIFont?, selected: Bool, value: String) -> UIView {
        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = UIFont.systemFont(ofSize: 14)
        nameLabel.textColor = UIAppColors.inkDynamic
        let previewLabel = UILabel()
        previewLabel.text = previewFont == nil ? "下载后显示此字体预览" : preview
        previewLabel.font = previewFont ?? UIFont.systemFont(ofSize: 12)
        previewLabel.textColor = UIAppColors.secondary
        previewLabel.lineBreakMode = .byTruncatingTail
        let texts = UIStackView(arrangedSubviews: [nameLabel, previewLabel])
        texts.axis = .vertical
        texts.spacing = 2
        let radio = UIImageView(image: UIImage(systemName: selected ? "checkmark.circle.fill" : "circle"))
        radio.tintColor = selected ? UIAppColors.accentPurple : UIColor(white: 0.78, alpha: 1)
        radio.contentMode = .scaleAspectFit
        let row = UIStackView(arrangedSubviews: [texts, radio])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        radio.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            radio.widthAnchor.constraint(equalToConstant: 22),
            radio.heightAnchor.constraint(equalToConstant: 22),
        ])
        let control = UIControl()
        control.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: control.trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: control.topAnchor, constant: 7),
            row.bottomAnchor.constraint(equalTo: control.bottomAnchor, constant: -7),
        ])
        control.accessibilityIdentifier = value
        control.addTarget(self, action: #selector(fontRowTapped(_:)), for: .touchUpInside)
        return control
    }

    private func importRow() -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "square.and.arrow.down"))
        icon.tintColor = UIAppColors.inkDynamic
        icon.contentMode = .scaleAspectFit
        let name = UILabel()
        name.text = "从文件导入字体"
        name.font = UIFont.systemFont(ofSize: 14)
        name.textColor = UIAppColors.inkDynamic
        let formats = UILabel()
        formats.text = "TTF · OTF · TTC"
        formats.font = UIFont.systemFont(ofSize: 12)
        formats.textColor = UIAppColors.secondary
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)))
        chevron.tintColor = UIColor(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xCC / 255, alpha: 1)
        let row = UIStackView(arrangedSubviews: [icon, name, UIView(), formats, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        icon.translatesAutoresizingMaskIntoConstraints = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.heightAnchor.constraint(equalToConstant: 14),
        ])
        let control = UIControl()
        control.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: control.trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: control.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: control.bottomAnchor, constant: -10),
        ])
        control.addTarget(self, action: #selector(importTapped), for: .touchUpInside)
        return control
    }

    // MARK: - Actions

    @objc private func closeTapped() { dismiss(animated: true) }

    @objc private func searchChanged() {
        query = searchField.text ?? ""
        rebuildList()
    }

    @objc private func fontRowTapped(_ sender: UIControl) {
        guard let value = sender.accessibilityIdentifier else { return }
        library.setSelection(area: area, chinese: chineseTab, value: value)
        rebuildList()
        refreshPreview()
        onChanged?()
    }

    @objc private func importedLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let view = gesture.view,
              let value = view.accessibilityIdentifier, value.hasPrefix("imp:") else { return }
        let fileKey = String(value.dropFirst(4)).split(separator: ":").first.map(String.init) ?? ""
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "删除这个字体", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.library.deleteImported(fileKey: fileKey)
            self.rebuildList()
            self.refreshPreview()
            self.refreshStorage()
            self.onChanged?()
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = view.bounds
        }
        present(sheet, animated: true)
    }

    @objc private func importTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.font], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    @objc private func clearImportedTapped() {
        guard !library.imported.isEmpty else { return }
        let alert = UIAlertController(title: "清理已导入字体", message: "会删除全部从文件导入的字体，正在使用它们的页面会回到系统默认字体。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "清理", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.library.clearAllImported()
            self.rebuildList()
            self.refreshPreview()
            self.refreshStorage()
            self.onChanged?()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func restoreTapped() {
        fontController.reset()
        rebuildList()
        refreshPreview()
        onChanged?()
    }

    // MARK: - Preview / storage

    private func refreshPreview() {
        previewBig.font = library.uiFont(area: area, size: 20) ?? UIFont.systemFont(ofSize: 20)
        previewSub.font = library.uiFont(area: area, size: 12.5) ?? UIFont.systemFont(ofSize: 12.5)
        previewDigits.font = library.uiFont(area: area, size: 13) ?? UIFont.systemFont(ofSize: 13)
        let bold = library.uiFont(area: area, size: 14, weight: .bold) ?? UIFont.systemFont(ofSize: 14, weight: .bold)
        let italic = library.uiFont(area: area, size: 14, italic: true) ?? UIFont.italicSystemFont(ofSize: 14)
        let text = NSMutableAttributedString(string: "Bold 粗体 ", attributes: [.font: bold])
        text.append(NSAttributedString(string: "Italic 斜体", attributes: [.font: italic]))
        previewStyles.attributedText = text
    }

    private func refreshStorage() {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        downloadedSizeLabel.text = formatter.string(fromByteCount: Int64(library.bundledTotalBytes))
        importedSizeLabel.text = formatter.string(fromByteCount: Int64(library.importedTotalBytes))
    }
}

extension FontSettingsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        var changed = false
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let faces = library.importFont(data: data, filename: url.lastPathComponent) else { continue }
            for face in faces {
                if face.coversLatin {
                    library.setSelection(area: area, chinese: false, value: "imp:" + face.id, notify: false)
                    changed = true
                }
                if face.coversChinese {
                    library.setSelection(area: area, chinese: true, value: "imp:" + face.id, notify: false)
                    changed = true
                }
            }
        }
        if changed {
            library.onSelectionsChanged?()
            rebuildList()
            refreshPreview()
            refreshStorage()
            onChanged?()
        }
    }
}
