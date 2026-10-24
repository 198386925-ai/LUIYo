import Combine
import UIKit

/// Pill action for the home tools area: the glass surface sits at the
/// bottom and the icon + title render ABOVE it (the previous version put
/// the surface inside a UIButton, whose content ended up under the glass).
final class PillActionView: UIControl {
    private let surface = StaticGlassView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        surface.glassRadius = 999
        surface.isUserInteractionEnabled = false
        addSubview(surface)
        surface.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        titleLabel.isUserInteractionEnabled = false
        let row = UIStackView(arrangedSubviews: [iconView, titleLabel])
        row.axis = .horizontal
        row.spacing = 7
        row.alignment = .center
        row.isUserInteractionEnabled = false
        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    func configure(icon: UIImage?, title: String, color: UIColor, font: UIFont, useBlur: Bool, glassTint: UIColor) {
        iconView.image = icon
        iconView.tintColor = color
        titleLabel.text = title
        titleLabel.textColor = color
        titleLabel.font = font
        surface.configure(useBlur: useBlur, tint: glassTint)
    }
}

/// Color settings row (UIKit): palette icon, two-line text and a chevron
/// over the glass pill surface — a control so the whole row is tappable.
final class ColorRowView: UIControl {
    private let surface = StaticGlassView()
    private let iconView = UIImageView(image: UIImage(systemName: "paintpalette", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)))
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))

    override init(frame: CGRect) {
        super.init(frame: frame)
        surface.glassRadius = 999
        surface.isUserInteractionEnabled = false
        addSubview(surface)
        surface.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .scaleAspectFit
        titleLabel.text = "自定义修改颜色"
        titleLabel.textColor = .label
        subtitleLabel.text = "浅色 / 深色 / 全部图标"
        subtitleLabel.textColor = .secondaryLabel
        chevron.tintColor = .secondaryLabel
        chevron.contentMode = .scaleAspectFit
        for v in [iconView, titleLabel, subtitleLabel, chevron] {
            addSubview(v)
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            subtitleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 16),
            chevron.heightAnchor.constraint(equalToConstant: 16),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(useBlur: Bool, tint: UIColor, titleFont: UIFont, subtitleFont: UIFont) {
        surface.configure(useBlur: useBlur, tint: tint)
        titleLabel.font = titleFont
        subtitleLabel.font = subtitleFont
    }
}

/// Homepage (UIKit): header, tools, category picker and the icon grid,
/// driven by the same NativeHomeModel / engine commands as before.
final class HomeViewController: UIViewController {
    var model: NativeHomeModel!
    private var category = 0
    private var catalog: NativeIconCatalog!
    private var collectionView: UICollectionView!
    private var cancellables = Set<AnyCancellable>()
    private var editingInlineSearch = false

    private enum Section: Int, CaseIterable {
        case header, search, tools, picker, status, heading, items
    }

    private var activeCategory: String { category == 0 ? "wechat" : "liquidui" }
    private var categoryEntries: [NativeIconEntry] {
        let filtered = catalog.entries.filter { $0.category == activeCategory }
        guard activeCategory == "wechat" else { return filtered }
        // Build 64 (user order): the four bottom-tab entries stay pinned
        // at the front in tab order; everything else sorts by title
        // character count, ascending, stable (same-length titles keep
        // catalog order). State is keyed by item id, so reordering the
        // display list cannot disturb uploads.
        let pinnedTitles = ["底栏微信", "底栏通讯录", "底栏发现", "底栏我的"]
        let pinned = pinnedTitles.flatMap { title in filtered.filter { $0.title == title } }
        let pinnedIDs = Set(pinned.map(\.id))
        let rest = filtered.enumerated()
            .filter { !pinnedIDs.contains($0.element.id) }
            .sorted {
                if $0.element.title.count != $1.element.title.count {
                    return $0.element.title.count < $1.element.title.count
                }
                return $0.offset < $1.offset
            }
            .map(\.element)
        return pinned + rest
    }
    private var visibleEntries: [NativeIconEntry] {
        let tokens = model.query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return categoryEntries.filter { item in
            tokens.allSatisfy { item.title.localizedCaseInsensitiveContains($0) }
        }
    }
    private var showsSearch: Bool { !model.theme.bottomSearchEnabled }
    private var showsStatus: Bool { !model.status.isEmpty && !model.status.hasPrefix("已上传 ") }

    /// Sections that actually exist right now. A hidden section must not
    /// exist at all: a compositional-layout section with zero items still
    /// reserves its height, which left the blank holes the user circled.
    private var visibleSections: [Section] {
        var list: [Section] = [.header]
        if showsSearch { list.append(.search) }
        list.append(.tools)
        list.append(.picker)
        if showsStatus { list.append(.status) }
        list.append(.heading)
        list.append(.items)
        return list
    }

    func hfont(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        if let imported = model.importedFont { return imported.withSize(size) }
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        catalog = NativeIconCatalog.load()
        let layout = UICollectionViewCompositionalLayout { [weak self] index, _ in
            self?.layoutSection(index) ?? NSCollectionLayoutSection(
                group: NSCollectionLayoutGroup.vertical(
                    layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(60)),
                    subitems: [NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(60)))]))
        }
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = 12
        layout.configuration = config
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.register(HomeHeaderCell.self, forCellWithReuseIdentifier: "header")
        collectionView.register(HomeSearchCell.self, forCellWithReuseIdentifier: "search")
        collectionView.register(HomeToolsCell.self, forCellWithReuseIdentifier: "tools")
        collectionView.register(HomePickerCell.self, forCellWithReuseIdentifier: "picker")
        collectionView.register(HomeStatusCell.self, forCellWithReuseIdentifier: "status")
        collectionView.register(HomeHeadingCell.self, forCellWithReuseIdentifier: "heading")
        collectionView.register(HomeIconCell.self, forCellWithReuseIdentifier: "icon")
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        // Report the scroll view AFTER this load finishes: the shell's
        // handler re-enters attachNativeHome, which must not happen while
        // viewDidLoad is still on the stack (infinite recursion, Build 1 crash).
        let scrollView = collectionView!
        DispatchQueue.main.async { [weak self] in
            self?.model.onScrollView?(scrollView)
        }
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // objectWillChange fires before the change lands; reload on
                // the next tick so the grid reads the new values.
                DispatchQueue.main.async { self?.refresh() }
            }
            .store(in: &cancellables)
        refreshTheme()
    }

    private func layoutSection(_ index: Int) -> NSCollectionLayoutSection {
        let section = visibleSections.indices.contains(index) ? visibleSections[index] : .items
        if section == .items {
            // Build 63: icon cells are a FIXED height, not estimated —
            // estimated heights let 1-line titles render shorter than
            // 2-line titles, so the grid looked ragged (some cells big,
            // some small). Titles are already capped at 2 lines, so a
            // fixed 76pt fits every title; content stays vertically
            // centred inside the uniform card.
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(0.5), heightDimension: .absolute(76)))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(76)),
                subitems: [item, item])
            group.interItemSpacing = .fixed(10)
            let result = NSCollectionLayoutSection(group: group)
            result.interGroupSpacing = 8
            result.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 24, trailing: 20)
            return result
        }
        if section == .tools {
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1), heightDimension: .absolute(200)))
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(200)),
                subitems: [item])
            let result = NSCollectionLayoutSection(group: group)
            result.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
            return result
        }
        let heights: [Section: CGFloat] = [.header: 76, .search: 44, .picker: 34, .status: 18, .heading: 24]
        let height = heights[section] ?? 60
        // The search capsule must keep its full 44pt: as an estimated
        // (self-sizing) section it collapsed to the icon's height on device
        // and rendered as a thin slit.
        let heightDimension: NSCollectionLayoutDimension = section == .search ? .absolute(height) : .estimated(height)
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1), heightDimension: heightDimension))
        let group = NSCollectionLayoutGroup.vertical(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: heightDimension),
            subitems: [item])
        let result = NSCollectionLayoutSection(group: group)
        result.contentInsets = NSDirectionalEdgeInsets(top: index == 0 ? 12 : 0, leading: 20, bottom: 0, trailing: 20)
        return result
    }

    private func refresh() {
        refreshTheme()
        collectionView.reloadData()
    }

    private func refreshTheme() {
        if model.backgroundImage == nil {
            view.backgroundColor = UIColor(nativeHex: model.theme.background)
        } else {
            view.backgroundColor = .clear
        }
    }

    // MARK: Actions

    func openColorSettings() {
        let editor = ColorSettingsViewController(model: model)
        let nav = UINavigationController(rootViewController: editor)
        present(nav, animated: true)
    }
}

extension HomeViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func numberOfSections(in collectionView: UICollectionView) -> Int { visibleSections.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch visibleSections[section] {
        case .header, .tools, .picker, .heading, .search, .status: return 1
        case .items: return visibleEntries.count
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let section = visibleSections[indexPath.section]
        switch section {
        case .header:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "header", for: indexPath) as! HomeHeaderCell
            cell.configure(model: model, hfont: { [weak self] in self?.hfont($0, $1) ?? UIFont.systemFont(ofSize: $0) })
            return cell
        case .search:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "search", for: indexPath) as! HomeSearchCell
            cell.configure(model: model, hfont: { [weak self] in self?.hfont($0, $1) ?? UIFont.systemFont(ofSize: $0) })
            cell.onQueryChange = { [weak self] text in
                guard let self else { return }
                self.model.query = text
                self.model.send("search", ["query": text])
            }
            cell.onEditingChange = { [weak self] editing in self?.editingInlineSearch = editing }
            return cell
        case .tools:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "tools", for: indexPath) as! HomeToolsCell
            cell.configure(model: model, hfont: { [weak self] in self?.hfont($0, $1) ?? UIFont.systemFont(ofSize: $0) })
            cell.onAction = { [weak self] action in
                guard let self else { return }
                switch action {
                case "colors": self.openColorSettings()
                case "fill": self.model.send("fill", ["query": self.model.query])
                default: self.model.send(action, [:])
                }
            }
            return cell
        case .picker:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "picker", for: indexPath) as! HomePickerCell
            cell.configure(model: model, selection: category)
            cell.onSelection = { [weak self] value in
                guard let self, self.category != value else { return }
                self.category = value
                self.model.send("category", ["category": value == 0 ? "wechat" : "liquidui"])
                self.collectionView.reloadData()
            }
            return cell
        case .status:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "status", for: indexPath) as! HomeStatusCell
            cell.configure(model: model, hfont: { [weak self] in self?.hfont($0, $1) ?? UIFont.systemFont(ofSize: $0) })
            return cell
        case .heading:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "heading", for: indexPath) as! HomeHeadingCell
            cell.configure(title: category == 0 ? "原版微信图标" : "LiquidUI 图标",
                           count: categoryEntries.count,
                           hfont: { [weak self] in self?.hfont($0, $1) ?? UIFont.systemFont(ofSize: $0) })
            return cell
        case .items:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "icon", for: indexPath) as! HomeIconCell
            let item = visibleEntries[indexPath.item]
            cell.configure(item: item, image: model.images[item.id], model: model,
                           hfont: { [weak self] in self?.hfont($0, $1) ?? UIFont.systemFont(ofSize: $0) })
            cell.onTrash = { [weak self] in self?.model.send("remove", ["id": item.id]) }
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard visibleSections[indexPath.section] == .items else { return }
        let item = visibleEntries[indexPath.item]
        model.send("upload", ["id": item.id])
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first, visibleSections[indexPath.section] == .items else { return nil }
        let item = visibleEntries[indexPath.item]
        guard model.images[item.id] != nil else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "移除图标", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    self?.model.send("remove", ["id": item.id])
                },
            ])
        }
    }
}

// MARK: - Cells

final class HomeHeaderCell: UICollectionViewCell {
    private let title = UILabel()
    private let subtitle = UILabel()
    private let authIcon = UIImageView()
    private let authLabel = UILabel()
    private let countLabel = UILabel()
    private let feedback = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        title.text = "LUIYo"
        subtitle.text = "微信图标管理"
        subtitle.textColor = UIAppColors.secondary
        authLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = UIAppColors.secondary
        countLabel.font = UIFont.systemFont(ofSize: 12)
        // No UIButton.Configuration here: a configuration button renders
        // its title at the configuration's own size, which is why the blue
        // link kept coming out bigger than the grey status labels. As a
        // classic button it honours titleLabel.font (hfont 12) exactly.
        feedback.titleEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: -6)
        feedback.setTitle("反馈问题 · 联系客服", for: .normal)
        feedback.setTitleColor(.systemBlue, for: .normal)
        feedback.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        feedback.addTarget(self, action: #selector(openFeedback), for: .touchUpInside)
        let statusRow = UIStackView(arrangedSubviews: [authIcon, authLabel, countLabel, feedback, UIView()])
        statusRow.axis = .horizontal
        statusRow.spacing = 6
        statusRow.alignment = .center
        // The symbol's glyph box is not square (the seal is wider
        // than tall, the lock taller than wide); with the default
        // scale-to-fill the 15 pt square slot stretched the glyph —
        // aspect-fit keeps its natural proportions in the same slot.
        authIcon.contentMode = .scaleAspectFit
        authIcon.translatesAutoresizingMaskIntoConstraints = false
        authIcon.widthAnchor.constraint(equalToConstant: 15).isActive = true
        authIcon.heightAnchor.constraint(equalToConstant: 15).isActive = true
        let stack = UIStackView(arrangedSubviews: [title, subtitle, statusRow])
        stack.axis = .vertical
        stack.spacing = 5
        stack.setCustomSpacing(8, after: subtitle)
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func openFeedback() {
        UIApplication.shared.open(AppConfiguration.supportURL)
    }

    func configure(model: NativeHomeModel, hfont: (CGFloat, UIFont.Weight) -> UIFont) {
        title.font = hfont(25, .bold)
        subtitle.font = hfont(12, .regular)
        authIcon.image = UIImage(systemName: model.authorized ? "checkmark.seal.fill" : "lock.fill",
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        authIcon.tintColor = model.authorized ? .systemGreen : UIAppColors.secondary
        // Wording exactly as designed （已授权/未授权）; what changed
        // is only the source — `authorized` is now the account
        // authorization verdict pushed by the shell.
        authLabel.text = model.authorized ? "已授权" : "未授权"
        authLabel.textColor = model.authorized ? .systemGreen : UIAppColors.secondary
        authLabel.font = hfont(12, .medium)
        countLabel.text = "已上传项目：\(model.uploadedCount) 项"
        countLabel.font = hfont(12, .regular)
        if let icon = ToolbarAssetImages.template(named: "ToolbarSupport") {
            let scaled = UIGraphicsImageRenderer(size: CGSize(width: 15, height: 15)).image { _ in
                icon.draw(in: CGRect(x: 0, y: 0, width: 15, height: 15))
            }.withRenderingMode(.alwaysTemplate)
            feedback.setImage(scaled, for: .normal)
            feedback.tintColor = .systemBlue
        }
        feedback.titleLabel?.font = hfont(12, .medium)
    }
}

final class HomeSearchCell: UICollectionViewCell, UITextFieldDelegate {
    private let surface = StaticGlassView()
    private let field = UITextField()
    private let clearButton = UIButton(type: .system)
    var onQueryChange: ((String) -> Void)?
    var onEditingChange: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        surface.glassRadius = 999
        surface.isUserInteractionEnabled = false
        contentView.addSubview(surface)
        surface.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            surface.topAnchor.constraint(equalTo: contentView.topAnchor),
            surface.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = UIAppColors.secondary
        icon.contentMode = .scaleAspectFit
        field.placeholder = "搜索图标"
        field.returnKeyType = .search
        field.delegate = self
        field.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearButton.tintColor = UIAppColors.secondary
        clearButton.isHidden = true
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [icon, field, clearButton])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        contentView.addSubview(row)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func textChanged() { onQueryChange?(field.text ?? "") }
    @objc private func clearTapped() {
        field.text = ""
        onQueryChange?("")
    }
    func textFieldDidBeginEditing(_ textField: UITextField) { onEditingChange?(true) }
    func textFieldDidEndEditing(_ textField: UITextField) { onEditingChange?(false) }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func configure(model: NativeHomeModel, hfont: (CGFloat, UIFont.Weight) -> UIFont) {
        surface.configure(useBlur: model.useBlur, tint: UIColor(nativeHex: model.theme.card))
        field.font = hfont(12, .regular)
        if field.text != model.query, !field.isFirstResponder {
            field.text = model.query
        }
        clearButton.isHidden = model.query.isEmpty
    }
}

final class HomeToolsCell: UICollectionViewCell {
    private let batchButton = PillActionView()
    private let fillImageButton = PillActionView()
    private let fillButton = PillActionView()
    private let colorRow = ColorRowView()
    private let clearButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)
    var onAction: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let row1 = UIStackView(arrangedSubviews: [batchButton, fillImageButton])
        row1.axis = .horizontal
        row1.spacing = 8
        row1.distribution = .fillEqually
        let row4 = UIStackView(arrangedSubviews: [clearButton, exportButton])
        row4.axis = .horizontal
        row4.spacing = 8
        row4.distribution = .fillEqually
        let stack = UIStackView(arrangedSubviews: [row1, fillButton, colorRow, row4])
        stack.axis = .vertical
        stack.spacing = 8
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        for button in [batchButton, fillImageButton, fillButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }
        colorRow.translatesAutoresizingMaskIntoConstraints = false
        colorRow.heightAnchor.constraint(equalToConstant: 44).isActive = true
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        exportButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        batchButton.addTarget(self, action: #selector(batchTapped), for: .touchUpInside)
        fillImageButton.addTarget(self, action: #selector(fillImageTapped), for: .touchUpInside)
        fillButton.addTarget(self, action: #selector(fillTapped), for: .touchUpInside)
        colorRow.addTarget(self, action: #selector(colorsTapped), for: .touchUpInside)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        exportButton.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func batchTapped() { onAction?("batch") }
    @objc private func fillImageTapped() { onAction?("fillImage") }
    @objc private func fillTapped() { onAction?("fill") }
    @objc private func colorsTapped() { onAction?("colors") }
    @objc private func clearTapped() { onAction?("clear") }
    @objc private func exportTapped() { onAction?("export") }

    func configure(model: NativeHomeModel, hfont: (CGFloat, UIFont.Weight) -> UIFont) {
        let tint = UIColor(nativeHex: model.theme.button)
        let textColor: UIColor = model.theme.customButton ? .label : .systemBlue
        for (button, title, asset, symbol) in [
            (batchButton, "关键词批量导入", "ToolbarImport", nil),
            (fillImageButton, "补全图片", "ToolbarFill", nil),
            (fillButton, "双分类补全", nil, "square.3.layers.3d"),
        ] as [(PillActionView, String, String?, String?)] {
            let icon: UIImage?
            if let asset, let image = ToolbarAssetImages.template(named: asset) {
                icon = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 18)).image { _ in
                    image.draw(in: CGRect(x: 0, y: 0, width: 18, height: 18))
                }.withRenderingMode(.alwaysTemplate)
            } else if let symbol {
                icon = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium))
            } else {
                icon = nil
            }
            button.configure(icon: icon, title: title, color: textColor,
                             font: hfont(13, .semibold),
                             useBlur: model.useBlur, glassTint: tint)
        }
        // Color row: palette icon + two-line text + chevron (matches the old home).
        colorRow.configure(useBlur: model.useBlur, tint: tint,
                           titleFont: hfont(13, .semibold), subtitleFont: hfont(10, .regular))

        for (button, title, asset, hex) in [
            (clearButton, "清空", "ToolbarClear", "#007AFE"),
            (exportButton, "导出 ZIP", "ToolbarExport", "#46D86A"),
        ] as [(UIButton, String, String, String)] {
            let color = UIColor(nativeHex: hex)
            var config: UIButton.Configuration
            if #available(iOS 26.0, *), !model.useBlur {
                config = .prominentGlass()
            } else {
                config = .plain()
                config.background.visualEffect = UIBlurEffect(style: .systemMaterial)
                config.background.backgroundColor = color.withAlphaComponent(0.72)
            }
            config.title = title
            config.cornerStyle = .capsule
            config.baseBackgroundColor = color
            config.baseForegroundColor = .white
            if let image = ToolbarAssetImages.template(named: asset) {
                config.image = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 18)).image { _ in
                    image.withTintColor(.white, renderingMode: .alwaysOriginal)
                        .draw(in: CGRect(x: 0, y: 0, width: 18, height: 18))
                }.withRenderingMode(.alwaysOriginal)
            }
            config.imagePadding = 8
            let font = hfont(13, .semibold)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes
                result.font = font
                result.foregroundColor = .white
                return result
            }
            button.configuration = config
            button.tintColor = color
        }
    }
}

final class HomePickerCell: UICollectionViewCell {
    private let picker = PillSegmentedControl()
    var onSelection: ((Int) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(picker)
        picker.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            picker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            picker.topAnchor.constraint(equalTo: contentView.topAnchor),
            picker.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        picker.options = [("wechat", "原版微信"), ("liquidui", "LiquidUI")]
        picker.onChange = { [weak self] value in self?.onSelection?(value == "wechat" ? 0 : 1) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(model: NativeHomeModel, selection: Int) {
        picker.setSelectedValue(selection == 0 ? "wechat" : "liquidui")
    }
}

final class HomeStatusCell: UICollectionViewCell {
    private let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textColor = UIAppColors.secondary
        contentView.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.topAnchor.constraint(equalTo: contentView.topAnchor),
            label.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(model: NativeHomeModel, hfont: (CGFloat, UIFont.Weight) -> UIFont) {
        label.text = model.status
        label.font = hfont(12, .regular)
    }
}

final class HomeHeadingCell: UICollectionViewCell {
    private let title = UILabel()
    private let count = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        count.textColor = UIAppColors.secondary
        let row = UIStackView(arrangedSubviews: [title, UIView(), count])
        row.axis = .horizontal
        row.alignment = .center
        contentView.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            row.topAnchor.constraint(equalTo: contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(title text: String, count value: Int, hfont: (CGFloat, UIFont.Weight) -> UIFont) {
        title.text = text
        title.font = hfont(17, .regular)
        count.text = "\(value) 项"
        count.font = hfont(12, .regular)
    }
}

final class HomeIconCell: UICollectionViewCell {
    private let card = GlassCardView(radius: 24)
    private let thumbContainer = UIView()
    private let thumbImage = UIImageView()
    private let plusIcon = UIImageView()
    private let title = UILabel()
    private let state = UILabel()
    private let trash = UIButton(type: .system)
    var onTrash: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        thumbContainer.layer.cornerRadius = 12
        thumbContainer.clipsToBounds = true
        thumbImage.contentMode = .scaleAspectFit
        plusIcon.image = UIImage(systemName: "plus")
        plusIcon.tintColor = .white
        plusIcon.contentMode = .center
        thumbContainer.addSubview(thumbImage)
        thumbContainer.addSubview(plusIcon)
        thumbImage.translatesAutoresizingMaskIntoConstraints = false
        plusIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            thumbImage.leadingAnchor.constraint(equalTo: thumbContainer.leadingAnchor),
            thumbImage.trailingAnchor.constraint(equalTo: thumbContainer.trailingAnchor),
            thumbImage.topAnchor.constraint(equalTo: thumbContainer.topAnchor),
            thumbImage.bottomAnchor.constraint(equalTo: thumbContainer.bottomAnchor),
            plusIcon.centerXAnchor.constraint(equalTo: thumbContainer.centerXAnchor),
            plusIcon.centerYAnchor.constraint(equalTo: thumbContainer.centerYAnchor),
            plusIcon.widthAnchor.constraint(equalToConstant: 16),
            plusIcon.heightAnchor.constraint(equalToConstant: 16),
        ])
        title.numberOfLines = 2
        state.numberOfLines = 1
        let texts = UIStackView(arrangedSubviews: [title, state])
        texts.axis = .vertical
        texts.spacing = 3
        trash.setImage(UIImage(systemName: "trash"), for: .normal)
        trash.tintColor = .systemRed
        trash.addTarget(self, action: #selector(trashTapped), for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [thumbContainer, texts, trash])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        card.content.addSubview(row)
        thumbContainer.translatesAutoresizingMaskIntoConstraints = false
        trash.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            thumbContainer.widthAnchor.constraint(equalToConstant: 32),
            thumbContainer.heightAnchor.constraint(equalToConstant: 32),
            trash.widthAnchor.constraint(equalToConstant: 36),
            row.leadingAnchor.constraint(equalTo: card.content.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: card.content.trailingAnchor, constant: -2),
            row.topAnchor.constraint(equalTo: card.content.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: card.content.bottomAnchor, constant: -10),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func trashTapped() { onTrash?() }

    func configure(item: NativeIconEntry, image: UIImage?, model: NativeHomeModel, hfont: (CGFloat, UIFont.Weight) -> UIFont) {
        card.configure(useBlur: model.useBlur, tint: UIColor(nativeHex: model.theme.card))
        title.text = item.title
        title.font = hfont(12, .regular)
        title.textColor = .label
        state.text = image == nil ? "点击上传" : "已上传 · 点击替换"
        state.font = hfont(10, .regular)
        state.textColor = UIAppColors.secondary
        trash.isHidden = image == nil
        if let image {
            thumbImage.image = image
            thumbImage.isHidden = false
            plusIcon.isHidden = true
            thumbContainer.backgroundColor = .clear
        } else {
            thumbImage.isHidden = true
            plusIcon.isHidden = false
            thumbContainer.backgroundColor = model.theme.customButton
                ? UIColor(nativeHex: model.theme.button) : .systemBlue
            plusIcon.tintColor = model.theme.customButton
                ? UIColor(nativeHex: model.theme.actionText) : .white
        }
    }
}
