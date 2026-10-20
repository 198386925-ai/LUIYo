import UIKit
import UniformTypeIdentifiers

/// Slides a presented page in from the right while fading it in (and back
/// out to the right on dismiss), instead of the default bottom-up sheet.
final class SlideFadeTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let presenting: Bool

    init(presenting: Bool) { self.presenting = presenting }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        presenting ? 0.28 : 0.24
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let container = transitionContext.containerView
        if presenting {
            guard let toView = transitionContext.view(forKey: .to) else {
                transitionContext.completeTransition(false)
                return
            }
            toView.alpha = 0
            toView.transform = CGAffineTransform(translationX: container.bounds.width * 0.22, y: 0)
            container.addSubview(toView)
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
                toView.alpha = 1
                toView.transform = .identity
            } completion: { _ in
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            }
        } else {
            guard let fromView = transitionContext.view(forKey: .from) else {
                transitionContext.completeTransition(false)
                return
            }
            UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseIn]) {
                fromView.alpha = 0
                fromView.transform = CGAffineTransform(translationX: container.bounds.width * 0.22, y: 0)
            } completion: { _ in
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            }
        }
    }
}

/// Shared header for the settings sub-pages: a wide back button on the left
/// and the title centred on the page.
func luiyoPageHeader(title: String, backAction: Selector, target: Any?) -> UIView {
    let header = UIView()
    let back = UIButton(type: .system)
    back.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .bold)), for: .normal)
    back.tintColor = UIAppColors.inkDynamic
    back.contentHorizontalAlignment = .left
    back.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)
    back.addTarget(target, action: backAction, for: .touchUpInside)
    back.accessibilityLabel = "返回"
    let label = UILabel()
    label.text = title
    label.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
    label.textColor = UIAppColors.inkDynamic
    label.textAlignment = .center
    header.addSubview(back)
    header.addSubview(label)
    back.translatesAutoresizingMaskIntoConstraints = false
    label.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        back.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 6),
        back.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        back.widthAnchor.constraint(equalToConstant: 56),
        back.heightAnchor.constraint(equalToConstant: 44),
        label.centerXAnchor.constraint(equalTo: header.centerXAnchor),
        label.centerYAnchor.constraint(equalTo: header.centerYAnchor),
    ])
    return header
}

/// The 更改字体 page (modelled on the reference design): one Latin and one
/// Chinese font are picked from the bundled catalog or imported files, and
/// the 应用位置 checkboxes choose which pages （首页/规则页/设置页） use them.
/// Opened from the settings theme fold's 自定义字体 entry.
final class FontSettingsViewController: UIViewController {
    private let fontController: ThemeFontController
    private let homeModel: NativeHomeModel
    private var library: FontLibrary { fontController.library }
    /// Fired whenever selections or page switches change.
    var onChanged: (() -> Void)?

    private var chineseTab = false
    private var query = ""

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var previewBig: UILabel!
    private var previewSub: UILabel!
    private var previewStyles: UILabel!
    private var previewDigits: UILabel!
    private var checkboxImages: [FontArea: UIImageView] = [:]
    private let listStack = UIStackView()
    private var searchField: UITextField!
    private var downloadedSizeLabel: UILabel!
    private var importedSizeLabel: UILabel!

    init(fontController: ThemeFontController, homeModel: NativeHomeModel) {
        self.fontController = fontController
        self.homeModel = homeModel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        transitioningDelegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var cardTint: UIColor { UIColor(nativeHex: homeModel.theme.card) }

    private func configuredCard(radius: CGFloat) -> GlassCardView {
        let card = GlassCardView(radius: radius)
        card.configure(useBlur: homeModel.useBlur, tint: cardTint)
        return card
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(nativeHex: homeModel.theme.background)

        let header = luiyoPageHeader(title: "更改字体", backAction: #selector(backTapped), target: self)
        view.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 52),
        ])

        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        stack.axis = .vertical
        stack.spacing = 12
        scrollView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -28),
        ])

        // 1) Preview card.
        stack.addArrangedSubview(previewCard())
        // 2) 应用位置： label + checkbox card + note.
        let areaLabel = sectionLabel("应用位置")
        stack.addArrangedSubview(areaLabel)
        stack.setCustomSpacing(6, after: areaLabel)
        stack.addArrangedSubview(areaCard())
        let areaNote = UILabel()
        areaNote.text = "勾选的页面会立即换上所选字体；没勾选的页面使用系统默认字体。"
        areaNote.font = UIFont.systemFont(ofSize: 11)
        areaNote.textColor = UIAppColors.secondary
        areaNote.numberOfLines = 0
        stack.addArrangedSubview(areaNote)
        stack.setCustomSpacing(4, after: areaNote)
        // 3) Latin / Chinese switch.
        let scriptSeg = PillSegmentedControl(
            options: [("latin", "英文字体"), ("chinese", "中文字体")],
            onChange: { [weak self] value in
                self?.chineseTab = (value == "chinese")
                self?.rebuildList()
            })
        stack.addArrangedSubview(scriptSeg)
        // 4) Search card.
        stack.addArrangedSubview(searchCard())
        // 5) Font list (one card per row).
        listStack.axis = .vertical
        listStack.spacing = 10
        stack.addArrangedSubview(listStack)
        // 6) Notes.
        let notes = UILabel()
        notes.text = "支持 TTF、OTF 与 TTC 格式（单个文件不超过 64MB）。英文字体只管英文和数字，中文字体只管汉字，两边可以自由搭配。"
        notes.font = UIFont.systemFont(ofSize: 11)
        notes.textColor = UIAppColors.secondary
        notes.numberOfLines = 0
        stack.addArrangedSubview(notes)
        // 7) Storage card + restore.
        stack.addArrangedSubview(storageCard())
        let restore = UIButton(type: .system)
        restore.setTitle("恢复系统默认字体", for: .normal)
        restore.setTitleColor(UIColor(red: 0.85, green: 0.25, blue: 0.22, alpha: 1), for: .normal)
        restore.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        restore.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)
        stack.addArrangedSubview(restore)

        rebuildList()
        refreshPreview()
        refreshStorage()
    }

    @objc private func backTapped() { dismiss(animated: true) }

    private func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = UIAppColors.inkDynamic
        return label
    }

    // MARK: - Preview

    private func previewCard() -> UIView {
        let card = configuredCard(radius: 26)
        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 8
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
        previewBig.numberOfLines = 1
        previewSub = UILabel()
        previewSub.text = "界面文字 · 中文字体自动回退"
        previewSub.numberOfLines = 1
        previewStyles = UILabel()
        previewDigits = UILabel()
        previewDigits.text = "0123456789 → # «="
        for label in [header, previewBig, previewSub, previewStyles, previewDigits] {
            inner.addArrangedSubview(label!)
        }
        return card
    }

    private func refreshPreview() {
        previewBig.font = library.currentFont(size: 20) ?? UIFont.systemFont(ofSize: 20)
        previewSub.font = library.currentFont(size: 13) ?? UIFont.systemFont(ofSize: 13)
        previewSub.textColor = UIAppColors.secondary
        previewDigits.font = library.currentFont(size: 13) ?? UIFont.systemFont(ofSize: 13)
        previewDigits.textColor = UIAppColors.secondary
        let boldFont = library.currentFont(size: 14, weight: .bold) ?? UIFont.systemFont(ofSize: 14, weight: .bold)
        let italicFont = library.currentFont(size: 14, italic: true) ?? UIFont.italicSystemFont(ofSize: 14)
        let text = NSMutableAttributedString(string: "Bold 粗体  ", attributes: [.font: boldFont])
        text.append(NSAttributedString(string: "Italic 斜体", attributes: [.font: italicFont]))
        previewStyles.attributedText = text
    }

    // MARK: - 应用位置 checkboxes

    private func areaCard() -> UIView {
        let card = configuredCard(radius: 20)
        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 0
        card.content.addSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.content.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: card.content.trailingAnchor),
            inner.topAnchor.constraint(equalTo: card.content.topAnchor),
            inner.bottomAnchor.constraint(equalTo: card.content.bottomAnchor),
        ])
        let areas = FontArea.allCases
        for (index, area) in areas.enumerated() {
            let row = UIControl()
            row.tag = index
            row.addTarget(self, action: #selector(areaRowTapped(_:)), for: .touchUpInside)
            let box = UIImageView()
            box.contentMode = .scaleAspectFit
            checkboxImages[area] = box
            let label = UILabel()
            label.text = area.title
            label.font = UIFont.systemFont(ofSize: 15)
            label.textColor = UIAppColors.inkDynamic
            row.addSubview(box)
            row.addSubview(label)
            box.translatesAutoresizingMaskIntoConstraints = false
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 52),
                box.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
                box.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                box.widthAnchor.constraint(equalToConstant: 23),
                box.heightAnchor.constraint(equalToConstant: 23),
                label.leadingAnchor.constraint(equalTo: box.trailingAnchor, constant: 12),
                label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            ])
            inner.addArrangedSubview(row)
            if index < areas.count - 1 {
                let line = UIView()
                line.backgroundColor = UIAppColors.divider
                inner.addArrangedSubview(line)
                line.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
                    line.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: 51),
                    line.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -16),
                ])
            }
        }
        refreshCheckboxes()
        return card
    }

    private func refreshCheckboxes() {
        for (area, box) in checkboxImages {
            let on = library.isEnabled(area)
            box.image = UIImage(systemName: on ? "checkmark.square.fill" : "square",
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .regular))
            box.tintColor = on ? UIAppColors.inkDynamic : UIAppColors.secondary
        }
    }

    @objc private func areaRowTapped(_ sender: UIControl) {
        let area = FontArea.allCases[sender.tag]
        library.setEnabled(area, !library.isEnabled(area))
        refreshCheckboxes()
        notifyChanged()
    }

    // MARK: - Search

    private func searchCard() -> UIView {
        let card = configuredCard(radius: 20)
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)))
        icon.tintColor = UIAppColors.secondary
        icon.contentMode = .scaleAspectFit
        let field = UITextField()
        field.placeholder = "搜索字体"
        field.font = UIFont.systemFont(ofSize: 14)
        field.textColor = UIAppColors.inkDynamic
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .search
        field.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        searchField = field
        card.content.addSubview(icon)
        card.content.addSubview(field)
        icon.translatesAutoresizingMaskIntoConstraints = false
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 48),
            icon.leadingAnchor.constraint(equalTo: card.content.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: card.content.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: card.content.trailingAnchor, constant: -14),
            field.centerYAnchor.constraint(equalTo: card.content.centerYAnchor),
        ])
        return card
    }

    @objc private func searchChanged() {
        query = (searchField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        rebuildList()
    }

    // MARK: - Font list (one card per row)

    private func matches(_ name: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }

    private func rebuildList() {
        for arranged in listStack.arrangedSubviews {
            listStack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
        let current = library.selection(chinese: chineseTab)
        if matches("系统默认") {
            listStack.addArrangedSubview(fontRowCard(
                name: "系统默认",
                preview: chineseTab ? "中文字体示例：你好，世界。" : "The quick brown fox 0123",
                previewFont: nil,
                selected: current == "system",
                value: "system",
                fileKey: nil))
        }
        var lastGroup: String?
        for def in library.families(chinese: chineseTab) where matches(def.displayName) {
            if def.group != lastGroup {
                lastGroup = def.group
                listStack.addArrangedSubview(groupHeader(def.group))
            }
            let preview = library.previewFont(family: def, size: 12)
            listStack.addArrangedSubview(fontRowCard(
                name: def.displayName,
                preview: preview == nil ? "下载后显示此字体预览" : (chineseTab ? "中文字体示例：你好，世界。" : "The quick brown fox 0123"),
                previewFont: preview,
                selected: current == "fam:" + def.id,
                value: "fam:" + def.id,
                fileKey: nil))
        }
        let faces = library.imported.filter { chineseTab ? $0.coversChinese : $0.coversLatin }
        let visibleFaces = faces.filter { matches($0.name) }
        if !visibleFaces.isEmpty {
            listStack.addArrangedSubview(groupHeader("已导入"))
            for face in visibleFaces {
                listStack.addArrangedSubview(fontRowCard(
                    name: face.name,
                    preview: chineseTab ? "中文字体示例：你好，世界。" : "The quick brown fox 0123",
                    previewFont: library.previewFont(imported: face, size: 12),
                    selected: current == "imp:" + face.id,
                    value: "imp:" + face.id,
                    fileKey: face.fileKey))
            }
        }
        listStack.addArrangedSubview(importCard())
    }

    private func groupHeader(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = UIAppColors.inkDynamic
        return label
    }

    private func fontRowCard(name: String, preview: String?, previewFont: UIFont?, selected: Bool, value: String, fileKey: String?) -> UIView {
        let card = configuredCard(radius: 20)
        let tap = UIControl()
        tap.accessibilityIdentifier = value
        tap.addTarget(self, action: #selector(fontRowTapped(_:)), for: .touchUpInside)
        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = UIFont.systemFont(ofSize: 14)
        nameLabel.textColor = UIAppColors.inkDynamic
        nameLabel.numberOfLines = 1
        let previewLabel = UILabel()
        previewLabel.text = preview
        previewLabel.font = previewFont ?? UIFont.systemFont(ofSize: 12)
        previewLabel.textColor = UIAppColors.secondary
        previewLabel.numberOfLines = 1
        let radio = UIImageView(image: UIImage(
            systemName: selected ? "checkmark.circle.fill" : "circle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)))
        radio.tintColor = selected ? UIAppColors.accentPurple : UIAppColors.secondary
        radio.contentMode = .scaleAspectFit
        card.content.addSubview(tap)
        tap.addSubview(nameLabel)
        tap.addSubview(previewLabel)
        tap.addSubview(radio)
        tap.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        radio.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tap.leadingAnchor.constraint(equalTo: card.content.leadingAnchor),
            tap.trailingAnchor.constraint(equalTo: card.content.trailingAnchor),
            tap.topAnchor.constraint(equalTo: card.content.topAnchor),
            tap.bottomAnchor.constraint(equalTo: card.content.bottomAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: tap.leadingAnchor, constant: 16),
            nameLabel.topAnchor.constraint(equalTo: tap.topAnchor, constant: 11),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: radio.leadingAnchor, constant: -10),
            previewLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            previewLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            previewLabel.bottomAnchor.constraint(equalTo: tap.bottomAnchor, constant: -11),
            previewLabel.trailingAnchor.constraint(lessThanOrEqualTo: radio.leadingAnchor, constant: -10),
            radio.trailingAnchor.constraint(equalTo: tap.trailingAnchor, constant: -16),
            radio.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
            radio.widthAnchor.constraint(equalToConstant: 22),
            radio.heightAnchor.constraint(equalToConstant: 22),
        ])
        if let fileKey {
            card.accessibilityIdentifier = fileKey
            let press = UILongPressGestureRecognizer(target: self, action: #selector(importedLongPressed(_:)))
            press.minimumPressDuration = 0.6
            card.addGestureRecognizer(press)
        }
        return card
    }

    private func importCard() -> UIView {
        let card = configuredCard(radius: 20)
        let tap = UIControl()
        tap.addTarget(self, action: #selector(importTapped), for: .touchUpInside)
        let title = UILabel()
        title.text = "从文件导入字体"
        title.font = UIFont.systemFont(ofSize: 14)
        title.textColor = UIAppColors.inkDynamic
        let sub = UILabel()
        sub.text = "TTF · OTF · TTC"
        sub.font = UIFont.systemFont(ofSize: 11)
        sub.textColor = UIAppColors.secondary
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)))
        chevron.tintColor = UIAppColors.inkDynamic
        chevron.contentMode = .scaleAspectFit
        card.content.addSubview(tap)
        tap.addSubview(title)
        tap.addSubview(sub)
        tap.addSubview(chevron)
        tap.translatesAutoresizingMaskIntoConstraints = false
        title.translatesAutoresizingMaskIntoConstraints = false
        sub.translatesAutoresizingMaskIntoConstraints = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tap.leadingAnchor.constraint(equalTo: card.content.leadingAnchor),
            tap.trailingAnchor.constraint(equalTo: card.content.trailingAnchor),
            tap.topAnchor.constraint(equalTo: card.content.topAnchor),
            tap.bottomAnchor.constraint(equalTo: card.content.bottomAnchor),
            title.leadingAnchor.constraint(equalTo: tap.leadingAnchor, constant: 16),
            title.topAnchor.constraint(equalTo: tap.topAnchor, constant: 11),
            sub.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            sub.bottomAnchor.constraint(equalTo: tap.bottomAnchor, constant: -11),
            chevron.trailingAnchor.constraint(equalTo: tap.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 20),
            chevron.heightAnchor.constraint(equalToConstant: 20),
        ])
        return card
    }

    @objc private func fontRowTapped(_ sender: UIControl) {
        guard let value = sender.accessibilityIdentifier else { return }
        library.setSelection(chinese: chineseTab, value: value)
        notifyChanged()
        refreshPreview()
        rebuildList()
    }

    @objc private func importedLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let card = gesture.view,
              let fileKey = card.accessibilityIdentifier else { return }
        let name = library.imported.first { $0.fileKey == fileKey }?.name ?? "字体"
        let sheet = UIAlertController(title: name, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "删除这个字体", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.library.deleteImported(fileKey: fileKey)
            self.notifyChanged()
            self.refreshPreview()
            self.refreshStorage()
            self.rebuildList()
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = card
            popover.sourceRect = card.bounds
        }
        present(sheet, animated: true)
    }

    // MARK: - Storage

    private func storageCard() -> UIView {
        let card = configuredCard(radius: 20)
        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 8
        card.content.addSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.content.leadingAnchor, constant: 16),
            inner.trailingAnchor.constraint(equalTo: card.content.trailingAnchor, constant: -16),
            inner.topAnchor.constraint(equalTo: card.content.topAnchor, constant: 14),
            inner.bottomAnchor.constraint(equalTo: card.content.bottomAnchor, constant: -14),
        ])
        let title = UILabel()
        title.text = "字体存储"
        title.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = UIAppColors.inkDynamic
        inner.addArrangedSubview(title)
        downloadedSizeLabel = UILabel()
        downloadedSizeLabel.font = UIFont.systemFont(ofSize: 12)
        downloadedSizeLabel.textColor = UIAppColors.secondary
        inner.addArrangedSubview(downloadedSizeLabel)
        importedSizeLabel = UILabel()
        importedSizeLabel.font = UIFont.systemFont(ofSize: 12)
        importedSizeLabel.textColor = UIAppColors.secondary
        inner.addArrangedSubview(importedSizeLabel)
        let clear = UIButton(type: .system)
        clear.setTitle("清理已导入字体", for: .normal)
        clear.setTitleColor(UIColor(red: 0.85, green: 0.25, blue: 0.22, alpha: 1), for: .normal)
        clear.titleLabel?.font = UIFont.systemFont(ofSize: 13)
        clear.contentHorizontalAlignment = .left
        clear.addTarget(self, action: #selector(clearImportedTapped), for: .touchUpInside)
        inner.addArrangedSubview(clear)
        return card
    }

    private func refreshStorage() {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        downloadedSizeLabel?.text = "内置字体 · " + formatter.string(fromByteCount: Int64(library.bundledTotalBytes))
        importedSizeLabel?.text = "已导入字体 · " + formatter.string(fromByteCount: Int64(library.importedTotalBytes))
    }

    @objc private func clearImportedTapped() {
        guard !library.imported.isEmpty else { return }
        let alert = UIAlertController(title: "清理已导入字体", message: "会删除全部从文件导入的字体，正在使用它们的选项会回到系统默认。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.library.clearAllImported()
            self.notifyChanged()
            self.refreshPreview()
            self.refreshStorage()
            self.rebuildList()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func restoreTapped() {
        fontController.reset()
        notifyChanged()
        refreshPreview()
        rebuildList()
    }

    // MARK: - Import

    @objc private func importTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.font], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    private func notifyChanged() { onChanged?() }
}

extension FontSettingsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        var changed = false
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let faces = library.importFont(data: data, filename: url.lastPathComponent) else { continue }
            for face in faces {
                if face.coversLatin { library.setSelection(chinese: false, value: "imp:" + face.id, notify: false) }
                if face.coversChinese { library.setSelection(chinese: true, value: "imp:" + face.id, notify: false) }
            }
            changed = true
        }
        if changed {
            library.onSelectionsChanged?()
            notifyChanged()
            refreshPreview()
            refreshStorage()
            rebuildList()
        }
    }
}

extension FontSettingsViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideFadeTransitionAnimator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideFadeTransitionAnimator(presenting: false)
    }
}
