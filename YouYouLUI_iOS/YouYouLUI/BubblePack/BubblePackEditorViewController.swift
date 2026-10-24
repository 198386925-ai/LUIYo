import PhotosUI
import UIKit

/// 气泡包编辑界面（Swift 版，LUBubblePackEditorViewController 的一比一移植）
///
/// 仿微信聊天窗口的编辑页：点气泡放图，底部切命名方式和夜间版，导出 zip。
/// UIKit only。导出改用 App 现成的 ZipWriter（ObjC 版用 SSZipArchive，
/// 这里是唯一一处有意改动；输出文件名与静默行为与 ObjC 版一致）。

// MARK: - 颜色工具

private func bubbleColor(hex: String) -> UIColor {
    let s = hex.replacingOccurrences(of: "#", with: "")
    let rgb = UInt32(s, radix: 16) ?? 0
    return UIColor(
        red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
        green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
        blue: CGFloat(rgb & 0xFF) / 255.0,
        alpha: 1
    )
}

private let bubbleLightTable: [String: String] = [
    "bg": "#f4f5f7", "card": "#ffffff", "line": "#e4e7eb", "line2": "#d3d8de",
    "text": "#1b1d20", "text2": "#5d646d", "text3": "#8b9199",
    "accent": "#2f7cf6",
    "ok": "#1a9c5b", "warn": "#c08a12",
    "chat": "#ededed", "chatNight": "#111112",
    "bub": "#ffffff", "bubNight": "#2c2c2e", "bubEmpty": "#c2c7cd",
    "mine": "#95ec69", "mineNight": "#4a8c5a",
    "wxNav": "#ededed", "wxNavLine": "#d9d9d9", "wxNavTx": "#181818", "wxTime": "#b2b2b2",
    "wxBar": "#f7f7f7", "wxInputBg": "#ffffff", "wxIc": "#7d7d7d",
]

private let bubbleDarkTable: [String: String] = [
    "bg": "#141517", "card": "#1d1f23", "line": "#2e3238", "line2": "#3c424a",
    "text": "#e9ebee", "text2": "#a6adb6", "text3": "#6f767f",
    "accent": "#5b9bff",
    "ok": "#4ec98a", "warn": "#e0b64a",
    "chat": "#111112", "chatNight": "#111112",
    "bub": "#2c2c2e", "bubNight": "#2c2c2e", "bubEmpty": "#565c66",
    "mine": "#4a8c5a", "mineNight": "#4a8c5a",
    "wxNav": "#1c1c1e", "wxNavLine": "#2e2e30", "wxNavTx": "#e5e5e7", "wxTime": "#6b6b70",
    "wxBar": "#1c1c1e", "wxInputBg": "#2c2c2e", "wxIc": "#8a8a90",
]

// ObjC 版的 LU_CAT_LABEL 在源码里定义了但从未使用，这里不移植。
private let bubbleCatGroup: [String: String] = [
    "hb": "红包", "aa": "转账 / AA", "gift": "礼物",
    "app": "卡片", "common": "通用卡片底 / 遮罩", "voice": "语音",
]

// MARK: - 气泡视图（带微信尾巴）

final class BubbleView: UIView, UIGestureRecognizerDelegate {
    let imageView = UIImageView()
    let placeholder = UILabel()
    let deleteBtn = UIButton(type: .custom)
    var isMine = false
    var position: BubblePosition = .top  // 0 上 1 中 2 下 3 单（与 BubblePosition rawValue 一致）
    var isOther = false
    var category: String?
    var tailColor: UIColor?
    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?

    private var tail: CAShapeLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 7
        backgroundColor = .white

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        addSubview(imageView)

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        placeholder.textColor = UIColor(white: 0.45, alpha: 1)
        placeholder.textAlignment = .center
        placeholder.numberOfLines = 0
        addSubview(placeholder)

        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        deleteBtn.backgroundColor = bubbleColor(hex: "#ff5a5f")
        deleteBtn.layer.cornerRadius = 9
        deleteBtn.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        deleteBtn.setTitleColor(.white, for: .normal)
        deleteBtn.setTitle("×", for: .normal)
        deleteBtn.isHidden = true
        deleteBtn.addTarget(self, action: #selector(del), for: .touchUpInside)
        addSubview(deleteBtn)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tap))
        tap.delegate = self
        addGestureRecognizer(tap)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholder.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            placeholder.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            placeholder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            placeholder.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            deleteBtn.topAnchor.constraint(equalTo: topAnchor, constant: -6),
            deleteBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 6),
            deleteBtn.widthAnchor.constraint(equalToConstant: 18),
            deleteBtn.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view != deleteBtn
    }

    @objc private func tap() { onTap?() }
    @objc private func del() { onDelete?() }

    func showImage(_ img: UIImage, displaySize size: CGSize) {
        imageView.isHidden = false
        imageView.image = img
        imageView.bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        placeholder.isHidden = true
        deleteBtn.isHidden = false
        backgroundColor = .clear
        layer.borderWidth = 0
        redrawTail()
    }

    func showEmpty(withText text: String) {
        imageView.isHidden = true
        imageView.image = nil
        placeholder.isHidden = false
        placeholder.text = text
        deleteBtn.isHidden = true
        if !isOther {
            layer.borderWidth = 1.5
            layer.borderColor = bubbleColor(hex: "#c2c7cd").cgColor
        }
        redrawTail()
    }

    func applyBubbleColor(_ color: UIColor, border: UIColor?) {
        if imageView.isHidden {
            backgroundColor = color
            if let border {
                layer.borderWidth = 1.5
                layer.borderColor = border.cgColor
            } else {
                layer.borderWidth = 0
            }
        }
        tailColor = color
        redrawTail()
    }

    func redrawTail() {
        tail?.removeFromSuperlayer()
        tail = nil
        if isOther { return }
        if position == .middle { return }
        if !imageView.isHidden { return }
        // 注意：ObjC 版这里算出的 y 和 rect r 从未赋给图层（死代码），
        // 图层不设 frame，路径按图层原点画 —— 这里照原样保留这个渲染结果，
        // 只省略那两个不起作用的计算。
        let w: CGFloat = 8
        let h: CGFloat = 13
        let left = !isMine
        let path = UIBezierPath()
        if left {
            path.move(to: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: 0, y: h * 0.45))
        } else {
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: w, y: h * 0.45))
        }
        path.close()
        let layer = CAShapeLayer()
        layer.path = path.cgPath
        layer.fillColor = (tailColor ?? backgroundColor)?.cgColor
        self.layer.addSublayer(layer)
        tail = layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        redrawTail()
    }
}

// MARK: - 编辑界面

final class BubblePackEditorViewController: UIViewController,
    UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate {
    /// 导出完成回调，zipURL 是临时目录下的 气泡包.zip
    var onExport: ((URL) -> Void)?
    /// 壳子设置的导出授权门：点导出时先问它，回调 true 才真正打包；
    /// 没设置时（编辑器单用）直接导出。页内随便玩，只有导出 zip 过门。
    var exportAuthorizationCheck: ((@escaping (Bool) -> Void) -> Void)?

    private struct PlacedImage {
        let image: UIImage
        let w: Int
        let h: Int
    }

    private var scrollView: UIScrollView!
    private var contentStack: UIStackView!
    private var headerTitle: UILabel!
    private var headerSub: UILabel!
    private var themeBtn: UIButton!
    private var toolbar: UIView!
    private var modeSeg: UISegmentedControl!
    private var nightSeg: UISegmentedControl!
    private var viewSeg: UISegmentedControl!
    private var scaleSeg: UISegmentedControl!
    private var batchBtn: UIButton!
    private var copyBtn: UIButton!
    private var clearBtn: UIButton!
    private var exportBtn: UIButton!
    private var phoneCard: UIView!
    private var navView: UIView!
    private var chatStack: UIStackView!
    private var inputBar: UIView!
    private var phoneTip: UILabel!
    private var summaryLabel: UILabel!
    private var progressBar: UIView!
    private var progressFillW: NSLayoutConstraint!
    private var noteLabel: UILabel!
    private var otherToggle: UIButton!
    private var otherCard: UIView!
    private var otherChatStack: UIStackView!

    private var state: [String: PlacedImage] = [:]
    private var unrecognized: [(name: String, image: UIImage)] = []  // 批量导入时文件名认不出的图：不进任何槽位、也不进 zip
    private var textBubbles: [String: BubbleView] = [:]
    private var textFileNames: [String: UILabel] = [:]
    private var otherBubbles: [String: BubbleView] = [:]
    private var otherFileNames: [String: UILabel] = [:]

    private var mode = 0
    private var scaleOpt = 0  // 0 自动 1 不写 2 @2x 3 @3x
    private var wantsNight = false
    private var viewNight = false
    private var dark = false
    private var pickingSlotId: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "气泡包制作器"
        mode = 0
        scaleOpt = 0
        wantsNight = false
        viewNight = false
        dark = false
        state = [:]
        unrecognized = []
        textBubbles = [:]
        textFileNames = [:]
        otherBubbles = [:]
        otherFileNames = [:]

        buildScrollView()
        buildHeader()
        buildToolbar()
        buildPhone()
        buildSummaryAndNote()
        buildOtherPhone()
        buildChat()
        buildOtherChat()
        applyTheme()
        refresh()
    }

    private func c(_ key: String) -> UIColor {
        // 与 ObjC 版一致：深色表里没有的 key 回落到浅色表，两表都没有则为黑色
        //（ObjC 版 LUColor(nil) 即黑色；如夜间文字气泡边框用的 "bubLine" 就不在两表里）
        let table = dark ? bubbleDarkTable : bubbleLightTable
        let hex = table[key] ?? bubbleLightTable[key] ?? "#000000"
        return bubbleColor(hex: hex)
    }

    // MARK: - 骨架

    private func buildScrollView() {
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack = UIStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.layoutMargins = UIEdgeInsets(top: 18, left: 14, bottom: 90, right: 14)
        contentStack.isLayoutMarginsRelativeArrangement = true
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
        ])
    }

    private func buildHeader() {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        headerTitle = UILabel()
        headerTitle.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        headerSub = UILabel()
        headerSub.font = UIFont.systemFont(ofSize: 12.5)
        headerSub.numberOfLines = 0
        let titles = UIStackView(arrangedSubviews: [headerTitle, headerSub])
        titles.axis = .vertical
        titles.spacing = 1
        themeBtn = pillButton("深/浅配色", primary: false)
        themeBtn.addTarget(self, action: #selector(toggleTheme), for: .touchUpInside)
        row.addSubview(titles)
        row.addSubview(themeBtn)
        titles.translatesAutoresizingMaskIntoConstraints = false
        themeBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titles.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titles.topAnchor.constraint(equalTo: row.topAnchor),
            titles.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            themeBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            themeBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        contentStack.addArrangedSubview(row)
    }

    private func pillButton(_ title: String, primary: Bool) -> UIButton {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.layer.cornerRadius = 999
        b.titleLabel?.font = UIFont.systemFont(ofSize: 13)
        b.setTitle(title, for: .normal)
        if primary {
            b.backgroundColor = c("accent")
            b.setTitleColor(.white, for: .normal)
        } else {
            b.layer.borderWidth = 1
            b.setTitleColor(c("text2"), for: .normal)
        }
        b.setContentHuggingPriority(.required, for: .horizontal)
        return b
    }

    private func buildToolbar() {
        toolbar = UIView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.layer.cornerRadius = 22
        toolbar.layer.borderWidth = 1

        let mainRow = UIStackView()
        mainRow.translatesAutoresizingMaskIntoConstraints = false
        mainRow.axis = .horizontal
        mainRow.alignment = .center
        mainRow.spacing = 14

        modeSeg = segWithItems(["中文名", "英文名"], selected: 0)
        modeSeg.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        mainRow.addArrangedSubview(groupWithLabel("命名", views: [modeSeg]))

        nightSeg = segWithItems(["不做", "要做"], selected: 0)
        nightSeg.addTarget(self, action: #selector(nightChanged), for: .valueChanged)
        viewSeg = segWithItems(["日间", "夜间"], selected: 0)
        viewSeg.isHidden = true
        viewSeg.addTarget(self, action: #selector(viewChanged), for: .valueChanged)
        mainRow.addArrangedSubview(groupWithLabel("夜间版", views: [nightSeg, viewSeg]))

        scaleSeg = segWithItems(["自动", "@3x", "@2x", "不写"], selected: 0)
        scaleSeg.addTarget(self, action: #selector(scaleChanged), for: .valueChanged)
        mainRow.addArrangedSubview(groupWithLabel("倍数", views: [scaleSeg]))

        batchBtn = pillButton("批量导图", primary: false)
        batchBtn.addTarget(self, action: #selector(batch), for: .touchUpInside)
        copyBtn = pillButton("复制日间到夜间", primary: false)
        copyBtn.isHidden = true
        copyBtn.addTarget(self, action: #selector(copyDayToNight), for: .touchUpInside)
        clearBtn = pillButton("清空", primary: false)
        clearBtn.addTarget(self, action: #selector(clearAll), for: .touchUpInside)
        exportBtn = pillButton("导出 zip", primary: true)
        exportBtn.addTarget(self, action: #selector(doExport), for: .touchUpInside)

        let actions = UIStackView(arrangedSubviews: [batchBtn, copyBtn, clearBtn, exportBtn])
        actions.axis = .horizontal
        actions.spacing = 10
        actions.alignment = .center
        mainRow.addArrangedSubview(actions)

        toolbar.addSubview(mainRow)
        mainRow.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mainRow.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 10),
            mainRow.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -10),
            mainRow.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 16),
            mainRow.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -16),
        ])
        contentStack.addArrangedSubview(toolbar)
    }

    private func segWithItems(_ items: [String], selected idx: Int) -> UISegmentedControl {
        let s = UISegmentedControl(items: items)
        s.translatesAutoresizingMaskIntoConstraints = false
        s.selectedSegmentIndex = idx
        s.layer.cornerRadius = 999
        s.layer.masksToBounds = true
        s.tintColor = c("accent")
        return s
    }

    private func groupWithLabel(_ label: String, views: [UIView]) -> UIView {
        let g = UIStackView()
        g.axis = .horizontal
        g.spacing = 8
        g.alignment = .center
        g.layer.cornerRadius = 999
        g.layoutMargins = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 6)
        g.isLayoutMarginsRelativeArrangement = true
        let lb = UILabel()
        lb.text = label
        lb.font = UIFont.systemFont(ofSize: 12.5)
        lb.textColor = c("text3")
        lb.setContentHuggingPriority(.required, for: .horizontal)
        g.addArrangedSubview(lb)
        for v in views { g.addArrangedSubview(v) }
        return g
    }

    // MARK: - 手机框

    private func buildPhone() {
        phoneCard = UIView()
        phoneCard.translatesAutoresizingMaskIntoConstraints = false
        phoneCard.layer.cornerRadius = 18
        phoneCard.layer.borderWidth = 1
        phoneCard.clipsToBounds = true

        navView = UIView()
        navView.translatesAutoresizingMaskIntoConstraints = false
        navView.layer.borderWidth = 1
        let back = UILabel()
        back.text = "‹"
        back.font = UIFont.systemFont(ofSize: 22)
        let name = UILabel()
        name.text = "微信"
        name.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        name.textAlignment = .center
        let more = UILabel()
        more.text = "⋯"
        more.font = UIFont.systemFont(ofSize: 19)
        phoneTip = UILabel()
        phoneTip.font = UIFont.systemFont(ofSize: 11)
        let navRow = UIStackView(arrangedSubviews: [back, more, phoneTip])
        navRow.axis = .horizontal
        navRow.spacing = 8
        navRow.alignment = .center
        navView.addSubview(name)
        navView.addSubview(navRow)
        name.translatesAutoresizingMaskIntoConstraints = false
        navRow.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            navView.heightAnchor.constraint(equalToConstant: 44),
            name.centerXAnchor.constraint(equalTo: navView.centerXAnchor),
            name.centerYAnchor.constraint(equalTo: navView.centerYAnchor),
            navRow.leadingAnchor.constraint(equalTo: navView.leadingAnchor, constant: 12),
            navRow.trailingAnchor.constraint(equalTo: navView.trailingAnchor, constant: -12),
            navRow.topAnchor.constraint(equalTo: navView.topAnchor),
            navRow.bottomAnchor.constraint(equalTo: navView.bottomAnchor),
        ])

        chatStack = UIStackView()
        chatStack.translatesAutoresizingMaskIntoConstraints = false
        chatStack.axis = .vertical
        chatStack.spacing = 9
        chatStack.alignment = .fill

        inputBar = UIView()
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        inputBar.layer.borderWidth = 1
        let inRow = UIStackView()
        inRow.axis = .horizontal
        inRow.spacing = 9
        inRow.alignment = .center
        inRow.translatesAutoresizingMaskIntoConstraints = false
        let voice = wxInputChip("语音")
        let box = UIView()
        box.layer.cornerRadius = 5
        box.layer.borderWidth = 1
        box.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        let emoji = wxInputChip("表情")
        let moreIc = wxInputChip("更多")
        inRow.addArrangedSubview(voice)
        inRow.addArrangedSubview(box)
        inRow.addArrangedSubview(emoji)
        inRow.addArrangedSubview(moreIc)
        inputBar.addSubview(inRow)
        NSLayoutConstraint.activate([
            inputBar.heightAnchor.constraint(equalToConstant: 50),
            inRow.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 12),
            inRow.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -12),
            inRow.topAnchor.constraint(equalTo: inputBar.topAnchor),
            inRow.bottomAnchor.constraint(equalTo: inputBar.bottomAnchor),
        ])

        phoneCard.addSubview(navView)
        phoneCard.addSubview(chatStack)
        phoneCard.addSubview(inputBar)
        NSLayoutConstraint.activate([
            navView.topAnchor.constraint(equalTo: phoneCard.topAnchor),
            navView.leadingAnchor.constraint(equalTo: phoneCard.leadingAnchor),
            navView.trailingAnchor.constraint(equalTo: phoneCard.trailingAnchor),
            chatStack.topAnchor.constraint(equalTo: navView.bottomAnchor, constant: 12),
            chatStack.leadingAnchor.constraint(equalTo: phoneCard.leadingAnchor, constant: 12),
            chatStack.trailingAnchor.constraint(equalTo: phoneCard.trailingAnchor, constant: -12),
            inputBar.topAnchor.constraint(equalTo: chatStack.bottomAnchor, constant: 4),
            inputBar.leadingAnchor.constraint(equalTo: phoneCard.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: phoneCard.trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: phoneCard.bottomAnchor),
        ])
        contentStack.addArrangedSubview(phoneCard)
    }

    private func wxInputChip(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = UIFont.systemFont(ofSize: 10.5)
        l.textAlignment = .center
        l.layer.cornerRadius = 12
        l.layer.borderWidth = 1
        l.layer.masksToBounds = true
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.heightAnchor.constraint(equalToConstant: 24).isActive = true
        l.widthAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        return l
    }

    // MARK: - 统计 / 说明 / 其它气泡手机框

    private func buildSummaryAndNote() {
        summaryLabel = UILabel()
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = UIFont.systemFont(ofSize: 13)
        summaryLabel.numberOfLines = 0
        contentStack.addArrangedSubview(summaryLabel)

        progressBar = UIView()
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.layer.cornerRadius = 99
        progressBar.backgroundColor = c("line")
        let fill = UIView()
        fill.backgroundColor = c("ok")
        fill.layer.cornerRadius = 99
        fill.translatesAutoresizingMaskIntoConstraints = false
        progressBar.addSubview(fill)
        progressFillW = fill.widthAnchor.constraint(equalTo: progressBar.widthAnchor, multiplier: 0)
        NSLayoutConstraint.activate([
            progressBar.heightAnchor.constraint(equalToConstant: 4),
            fill.topAnchor.constraint(equalTo: progressBar.topAnchor),
            fill.bottomAnchor.constraint(equalTo: progressBar.bottomAnchor),
            fill.leadingAnchor.constraint(equalTo: progressBar.leadingAnchor),
            progressFillW,
        ])
        contentStack.addArrangedSubview(progressBar)

        noteLabel = UILabel()
        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        noteLabel.font = UIFont.systemFont(ofSize: 12.5)
        noteLabel.numberOfLines = 0
        noteLabel.layer.cornerRadius = 8
        noteLabel.layer.borderWidth = 1
        contentStack.addArrangedSubview(noteLabel)
    }

    private func buildOtherPhone() {
        otherToggle = UIButton(type: .system)
        otherToggle.translatesAutoresizingMaskIntoConstraints = false
        otherToggle.setTitle("红包 / 语音 / 卡片等其它气泡（32 个，可选项）", for: .normal)
        otherToggle.setTitleColor(c("accent"), for: .normal)
        otherToggle.titleLabel?.font = UIFont.systemFont(ofSize: 13.5, weight: .semibold)
        otherToggle.contentHorizontalAlignment = .left
        otherToggle.layer.cornerRadius = 999
        otherToggle.layer.borderWidth = 1
        otherToggle.layer.masksToBounds = true
        otherToggle.addTarget(self, action: #selector(toggleOther), for: .touchUpInside)
        contentStack.addArrangedSubview(otherToggle)

        otherCard = UIView()
        otherCard.translatesAutoresizingMaskIntoConstraints = false
        otherCard.layer.cornerRadius = 18
        otherCard.layer.borderWidth = 1
        otherCard.clipsToBounds = true
        otherCard.isHidden = true

        let nav = UIView()
        nav.translatesAutoresizingMaskIntoConstraints = false
        nav.layer.borderWidth = 1
        let n2 = UILabel()
        n2.text = "微信"
        n2.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        n2.textAlignment = .center
        let tip2 = UILabel()
        tip2.text = "点气泡放图"
        tip2.font = UIFont.systemFont(ofSize: 11)
        let navR = UIStackView(arrangedSubviews: [tip2])
        navR.axis = .horizontal
        nav.translatesAutoresizingMaskIntoConstraints = false
        nav.addSubview(n2)
        nav.addSubview(navR)
        n2.translatesAutoresizingMaskIntoConstraints = false
        navR.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            nav.heightAnchor.constraint(equalToConstant: 44),
            n2.centerXAnchor.constraint(equalTo: nav.centerXAnchor),
            n2.centerYAnchor.constraint(equalTo: nav.centerYAnchor),
            navR.trailingAnchor.constraint(equalTo: nav.trailingAnchor, constant: -12),
            navR.centerYAnchor.constraint(equalTo: nav.centerYAnchor),
        ])

        otherChatStack = UIStackView()
        otherChatStack.translatesAutoresizingMaskIntoConstraints = false
        otherChatStack.axis = .vertical
        otherChatStack.spacing = 9
        otherChatStack.alignment = .fill

        let inBar = UIView()
        inBar.translatesAutoresizingMaskIntoConstraints = false
        inBar.layer.borderWidth = 1
        let ir = UIStackView()
        ir.axis = .horizontal
        ir.spacing = 9
        ir.alignment = .center
        ir.translatesAutoresizingMaskIntoConstraints = false
        ir.addArrangedSubview(wxInputChip("语音"))
        let bx = UIView()
        bx.layer.cornerRadius = 5
        bx.layer.borderWidth = 1
        bx.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        ir.addArrangedSubview(bx)
        ir.addArrangedSubview(wxInputChip("表情"))
        ir.addArrangedSubview(wxInputChip("更多"))
        inBar.addSubview(ir)
        NSLayoutConstraint.activate([
            inBar.heightAnchor.constraint(equalToConstant: 50),
            ir.leadingAnchor.constraint(equalTo: inBar.leadingAnchor, constant: 12),
            ir.trailingAnchor.constraint(equalTo: inBar.trailingAnchor, constant: -12),
            ir.topAnchor.constraint(equalTo: inBar.topAnchor),
            ir.bottomAnchor.constraint(equalTo: inBar.bottomAnchor),
        ])

        otherCard.addSubview(nav)
        otherCard.addSubview(otherChatStack)
        otherCard.addSubview(inBar)
        NSLayoutConstraint.activate([
            nav.topAnchor.constraint(equalTo: otherCard.topAnchor),
            nav.leadingAnchor.constraint(equalTo: otherCard.leadingAnchor),
            nav.trailingAnchor.constraint(equalTo: otherCard.trailingAnchor),
            otherChatStack.topAnchor.constraint(equalTo: nav.bottomAnchor, constant: 12),
            otherChatStack.leadingAnchor.constraint(equalTo: otherCard.leadingAnchor, constant: 12),
            otherChatStack.trailingAnchor.constraint(equalTo: otherCard.trailingAnchor, constant: -12),
            inBar.topAnchor.constraint(equalTo: otherChatStack.bottomAnchor, constant: 4),
            inBar.leadingAnchor.constraint(equalTo: otherCard.leadingAnchor),
            inBar.trailingAnchor.constraint(equalTo: otherCard.trailingAnchor),
            inBar.bottomAnchor.constraint(equalTo: otherCard.bottomAnchor),
        ])
        contentStack.addArrangedSubview(otherCard)
    }

    // MARK: - 构建气泡

    private func textSlot(side: BubbleSide, pos: BubblePosition) -> BubbleSlot? {
        BubbleNaming.shared.textSlots().first { $0.side == side && $0.position == pos }
    }

    private func messageRow(for slot: BubbleSlot, isOther: Bool) -> UIView {
        let bub = BubbleView()
        bub.isMine = slot.side == .sender
        bub.position = slot.position
        bub.isOther = isOther
        bub.category = isOther ? slot.type : nil
        let sid = slot.identifier
        bub.onTap = { [weak self] in self?.pickForSlotId(sid) }
        bub.onDelete = { [weak self] in self?.removeSlotId(sid) }
        if isOther { otherBubbles[sid] = bub } else { textBubbles[sid] = bub }

        let fn = UILabel()
        fn.font = UIFont.systemFont(ofSize: 11)
        fn.numberOfLines = 0
        fn.textColor = c("text2")
        fn.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        if isOther { otherFileNames[sid] = fn } else { textFileNames[sid] = fn }

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        if bub.isMine {
            fn.textAlignment = .right
            row.addArrangedSubview(fn)
            row.addArrangedSubview(bub)
        } else {
            row.addArrangedSubview(bub)
            row.addArrangedSubview(fn)
        }

        bub.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        bub.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        if isOther {
            let min: [String: (CGFloat, CGFloat)] = [
                "hb": (206, 88), "aa": (196, 86), "gift": (196, 86),
                "app": (224, 84), "common": (224, 84), "voice": (148, 40),
            ]
            if let m = min[slot.type] {
                bub.widthAnchor.constraint(greaterThanOrEqualToConstant: m.0).isActive = true
                bub.heightAnchor.constraint(greaterThanOrEqualToConstant: m.1).isActive = true
            }
        }
        return row
    }

    private func buildChat() {
        let time = UILabel()
        time.text = "下午 8:07"
        time.font = UIFont.systemFont(ofSize: 11)
        time.textAlignment = .center
        chatStack.addArrangedSubview(time)

        let seq = ["r0", "r1", "r2", "s0", "s1", "s2", "gap", "r3", "gap", "s3"]
        for it in seq {
            if it == "gap" {
                let g = UIView()
                g.translatesAutoresizingMaskIntoConstraints = false
                g.heightAnchor.constraint(equalToConstant: 18).isActive = true
                chatStack.addArrangedSubview(g)
                continue
            }
            let sender = it.hasPrefix("s")
            let pos = Int(String(it.dropFirst())) ?? 0
            guard let s = textSlot(side: sender ? .sender : .receiver,
                                   pos: BubblePosition(rawValue: pos) ?? .single) else { continue }
            chatStack.addArrangedSubview(messageRow(for: s, isOther: false))
        }
    }

    private func buildOtherChat() {
        for cat in ["hb", "aa", "gift", "app", "common", "voice"] {
            let items = BubbleNaming.shared.otherSlots()
                .filter { $0.type == cat }
                .sorted { $0.identifier < $1.identifier }
            if items.isEmpty { continue }
            let gt = UILabel()
            gt.text = bubbleCatGroup[cat]
            gt.font = UIFont.systemFont(ofSize: 11)
            gt.textAlignment = .center
            otherChatStack.addArrangedSubview(gt)
            for s in items {
                otherChatStack.addArrangedSubview(messageRow(for: s, isOther: true))
            }
        }
    }

    // MARK: - 刷新

    private func refresh() {
        let night = viewNight
        applyPhoneNight(night)

        let upd: (BubbleSlot, BubbleView, UILabel) -> Void = { [weak self] slot, bub, fn in
            guard let self else { return }
            let theme = night ? "night" : "day"
            let it = self.state["\(slot.identifier)|\(theme)"]
            self.colorBubble(bub, slot: slot, night: night)
            if let it {
                let sc = self.scaleValue(w: it.w, h: it.h)
                let dw = it.w != 0 ? it.w / sc : 60
                let dh = it.h != 0 ? it.h / sc : 40
                bub.showImage(it.image, displaySize: CGSize(width: dw, height: dh))
                fn.text = String(format: "%@\n%ld×%ld · 显示 %ld×%ld",
                                 self.outName(slot, theme: theme), it.w, it.h, dw, dh)
            } else {
                let txt = bub.isOther ? slot.desc : slot.cnName
                bub.showEmpty(withText: txt)
                fn.text = self.outName(slot, theme: theme)
            }
            fn.textColor = self.c("text2")
        }

        for s in BubbleNaming.shared.textSlots() {
            if let bub = textBubbles[s.identifier], let fn = textFileNames[s.identifier] {
                upd(s, bub, fn)
            }
        }
        for s in BubbleNaming.shared.otherSlots() {
            if let bub = otherBubbles[s.identifier], let fn = otherFileNames[s.identifier] {
                upd(s, bub, fn)
            }
        }

        updateSummary()
    }

    private func colorBubble(_ bub: BubbleView, slot: BubbleSlot, night: Bool) {
        if bub.isOther {
            let map: [String: [String]] = [
                "hb": ["#fa9d3b", "#ffffff", "#7a4412", "#ffffff"],
                "aa": ["#f7c14c", "#5a3c00", "#6d5215", "#e8d9a0"],
                "gift": ["#f07c7c", "#ffffff", "#7a3030", "#ffffff"],
                "app": ["#ffffff", "#1b1d20", "#2c2c2e", "#e9ebee"],
                "common": ["#f2f4f7", "#1b1d20", "#33363c", "#e9ebee"],
                "voice": ["#ffffff", "#1b1d20", "#2c2c2e", "#e9ebee"],
            ]
            let mask = slot.identifier.contains("mask")
            let i = night ? 2 : 0
            let ti = night ? 3 : 1
            let arr = map[slot.type]
            let bg = mask ? bubbleColor(hex: night ? "#33363c" : "#e9ecf0")
                          : bubbleColor(hex: arr?[i] ?? "#000000")
            let tx = mask ? bubbleColor(hex: night ? "#e9ebee" : "#1b1d20")
                          : bubbleColor(hex: arr?[ti] ?? "#000000")
            let border: UIColor? = mask ? bubbleColor(hex: night ? "#565c66" : "#b6bdc6") : nil
            if bub.imageView.isHidden {
                bub.backgroundColor = bg
                if let border {
                    bub.layer.borderWidth = 1.5
                    bub.layer.borderColor = border.cgColor
                } else {
                    bub.layer.borderWidth = 0
                }
            }
            bub.tailColor = bg
            bub.placeholder.textColor = tx
            bub.redrawTail()
            return
        }
        let bg = slot.side == .sender
            ? (night ? c("mineNight") : c("mine"))
            : (night ? c("bubNight") : c("bub"))
        // 注意：ObjC 版这里夜间边框用的是 "bubLine"，它不在两套颜色表里，
        // c() 因此回落黑色 —— 这里照原样保留（不“修”成别的色）
        let border = night ? c("bubLine") : bubbleColor(hex: "#c2c7cd")
        bub.applyBubbleColor(bg, border: border)
        bub.placeholder.textColor = UIColor(white: night ? 0.6 : 0.45, alpha: 1)
    }

    private func applyPhoneNight(_ night: Bool) {
        let navBg = night ? bubbleColor(hex: "#1c1c1e") : c("wxNav")
        let navLine = night ? bubbleColor(hex: "#2e2e30") : c("wxNavLine")
        let navTx = night ? bubbleColor(hex: "#e5e5e7") : c("wxNavTx")
        navView.backgroundColor = navBg
        navView.layer.borderColor = navLine.cgColor
        // ObjC 版只重着 navView 的直接 UILabel 子视图，返回/更多标号在 navRow 里，
        // 夜间切换后会看不见；这里递归重着整条导航栏（标题、返回、更多、提示同色）。
        func recolorNavLabels(_ view: UIView) {
            if let label = view as? UILabel { label.textColor = navTx }
            for sub in view.subviews { recolorNavLabels(sub) }
        }
        recolorNavLabels(navView)
        phoneTip.textColor = navTx
        chatStack.backgroundColor = night ? c("chatNight") : c("chat")
        inputBar.backgroundColor = navBg
        inputBar.layer.borderColor = navLine.cgColor
        phoneCard.backgroundColor = c("card")
        phoneCard.layer.borderColor = c("line").cgColor
        for v in inputBar.subviews {
            guard let stack = v as? UIStackView else { continue }
            for x in stack.arrangedSubviews {
                if let label = x as? UILabel {
                    label.textColor = c("wxIc")
                    label.layer.borderColor = c("wxIc").cgColor
                } else if x.layer.borderWidth > 0 {
                    x.layer.borderColor = c("wxNavLine").cgColor
                    x.backgroundColor = c("wxInputBg")
                }
            }
        }
    }

    // MARK: - 主题与文件名 / 倍数

    private func applyTheme() {
        view.backgroundColor = c("bg")
        scrollView.backgroundColor = c("bg")
        headerTitle.text = "气泡包制作器"
        headerSub.text = "LiquidUI 商城 · 点气泡放图，自动按规则命名，导出即可上传"
        headerTitle.textColor = c("text")
        headerSub.textColor = c("text3")
        themeBtn.layer.borderColor = c("line").cgColor
        themeBtn.setTitleColor(c("text2"), for: .normal)

        toolbar.backgroundColor = c("card")
        toolbar.layer.borderColor = c("line").cgColor
        for v in toolbar.subviews {
            guard let row = v as? UIStackView else { continue }
            for cc in row.arrangedSubviews {
                if let stack = cc as? UIStackView {
                    stack.backgroundColor = c("bg")
                }
                if let label = cc as? UILabel {
                    label.textColor = c("text3")
                }
            }
        }
        modeSeg.tintColor = c("accent")
        nightSeg.tintColor = c("accent")
        viewSeg.tintColor = c("accent")
        scaleSeg.tintColor = c("accent")
        for b in [batchBtn, copyBtn, clearBtn] {
            b?.layer.borderColor = c("line").cgColor
            b?.setTitleColor(c("text2"), for: .normal)
        }
        exportBtn.backgroundColor = c("accent")

        summaryLabel.textColor = c("text2")
        progressBar.backgroundColor = c("line")
        noteLabel.textColor = c("text2")
        noteLabel.layer.borderColor = c("line").cgColor
        noteLabel.backgroundColor = c("card")

        otherToggle.layer.borderColor = c("line").cgColor
        otherToggle.setTitleColor(c("accent"), for: .normal)
        otherCard.backgroundColor = c("card")
        otherCard.layer.borderColor = c("line").cgColor
    }

    // scaleOpt：0 自动 1 不写 2 @2x 3 @3x。分段顺序是 自动/@3x/@2x/不写，
    // ObjC 版 scaleChanged 直接取 selectedSegmentIndex，等于把 @3x 和 不写标反了；
    // 这里按按钮文字修正映射（点什么就是什么）。
    private func scaleValue(w: Int, h: Int) -> Int {
        if scaleOpt == 3 { return 3 }
        if scaleOpt == 2 { return 2 }
        if scaleOpt == 1 { return 1 }
        return max(w, h) > 120 ? 3 : 1
    }

    private func suffixForScale(_ sc: Int) -> String {
        if sc == 3 { return "@3x" }
        if sc == 2 { return "@2x" }
        return ""
    }

    /// 与 ObjC 版 outName:theme: 一致（含原生名里的 ".png" 去除；真实规则数据里没有 .png，故无实际影响）。
    /// placed 传了就用它的实际尺寸算倍数后缀（夜间导出沿用日间图时用得上），不传则查当前槽位。
    private func outName(_ slot: BubbleSlot, theme: String, placed: PlacedImage? = nil) -> String {
        let night = theme == "night"
        let dir = (mode == 0 && night && !slot.cnName.isEmpty) ? "夜间/" : ""
        let sfx: String
        if let it = placed ?? state["\(slot.identifier)|\(theme)"] {
            sfx = suffixForScale(scaleValue(w: it.w, h: it.h))
        } else {
            sfx = scaleOpt == 1 ? "" : (scaleOpt == 2 ? "@2x" : "@3x")
        }
        let base: String
        if mode == 0 && !slot.cnName.isEmpty {
            base = slot.cnName
        } else {
            base = slot.nativeName.replacingOccurrences(of: ".png", with: "") + (night ? "_Dark" : "")
        }
        return "\(dir)\(base)\(sfx).png"
    }

    // MARK: - 统计

    private func updateSummary() {
        let need = BubbleNaming.shared.textSlots().count
        var day = 0
        var night = 0
        var other = 0
        for s in BubbleNaming.shared.textSlots() {
            if state["\(s.identifier)|day"] != nil { day += 1 }
            if state["\(s.identifier)|night"] != nil { night += 1 }
        }
        for s in BubbleNaming.shared.otherSlots() {
            if state["\(s.identifier)|day"] != nil || state["\(s.identifier)|night"] != nil {
                other += 1
            }
        }

        var tip = day == need ? "齐了，可以导出" : "文字气泡 8 个位置放满才能导出"
        if wantsNight && night < need {
            tip = "可以导出；夜间没放图的会沿用日间那张"
        }

        var txt = "日间 \(day)/\(need)"
        if wantsNight {
            txt += "   夜间 \(night)/\(need)"
        }
        txt += "   其它气泡 \(other)"
        if !unrecognized.isEmpty {
            let names = unrecognized.prefix(3).map { $0.name }.joined(separator: "、")
            let more = unrecognized.count > 3 ? " 等 \(unrecognized.count) 张" : ""
            txt += "\n⚠️ \(unrecognized.count) 张未识别（不导出）：\(names)\(more)"
        }
        summaryLabel.text = "\(txt)\n\(tip)"

        let pct: CGFloat = need != 0 ? CGFloat(day) / CGFloat(need) : 0
        progressFillW.isActive = false
        progressFillW = progressBar.subviews.first?.widthAnchor.constraint(equalTo: progressBar.widthAnchor, multiplier: pct)
        progressFillW?.isActive = true

        phoneTip.text = "正在编辑\(viewNight ? "夜间版" : "日间版") · 当前命名：\(mode == 0 ? "中文名" : "微信英文名")"
        copyBtn.isHidden = !wantsNight
        exportBtn.isEnabled = day == need
        viewSeg.isHidden = !wantsNight
        noteLabel.text = mode == 0
            ? "中文名：文字气泡用「左上」这种名字，夜间版自动放进 zip 里的「夜间」文件夹。红包等其它气泡只能用英文原名，导出时会自动用英文名。"
            : "微信英文名：用微信原生文件名，夜间版在名字末尾加 _Dark。需要按下态的话，手动把文件名加上 _HL 再放进包里。"
    }

    // MARK: - 主题 / 交互

    @objc private func toggleTheme() {
        dark.toggle()
        applyTheme()
        refresh()
    }

    @objc private func modeChanged() {
        mode = modeSeg.selectedSegmentIndex
        refresh()
    }

    @objc private func nightChanged() {
        wantsNight = nightSeg.selectedSegmentIndex == 1
        if !wantsNight { viewNight = false }
        refresh()
    }

    @objc private func viewChanged() {
        viewNight = viewSeg.selectedSegmentIndex == 1
        refresh()
    }

    @objc private func scaleChanged() {
        // 分段顺序 自动/@3x/@2x/不写 → scaleOpt 0/3/2/1
        scaleOpt = [0, 3, 2, 1][scaleSeg.selectedSegmentIndex]
        refresh()
    }

    @objc private func toggleOther() {
        otherCard.isHidden.toggle()
        if !otherCard.isHidden { refresh() }
    }

    @objc private func clearAll() {
        state.removeAll()
        unrecognized.removeAll()
        refresh()
    }

    @objc private func copyDayToNight() {
        // ObjC 版这里还算了个没用上的计数 n，这里省略（死代码，无行为影响）
        for s in BubbleNaming.shared.textSlots() + BubbleNaming.shared.otherSlots() {
            let d = "\(s.identifier)|day"
            let key = "\(s.identifier)|night"
            if let day = state[d], state[key] == nil {
                state[key] = day
            }
        }
        refresh()
    }

    // MARK: - 放图

    private func pickForSlotId(_ sid: String) {
        pickingSlotId = sid
        presentPickerMulti(false)
    }

    private func removeSlotId(_ sid: String) {
        let t = viewNight ? "night" : "day"
        state.removeValue(forKey: "\(sid)|\(t)")
        refresh()
    }

    private func presentPickerMulti(_ multi: Bool) {
        if #available(iOS 14, *) {
            var config = PHPickerConfiguration()
            config.selectionLimit = multi ? 0 : 1
            config.filter = .images
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            present(picker, animated: true)
            return
        }
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        present(picker, animated: true)
    }

    @objc private func batch() {
        presentPickerMulti(true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        if results.isEmpty { return }
        if pickingSlotId != nil {
            if let first = results.first {
                first.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
                    guard let self, let img = obj as? UIImage else { return }
                    DispatchQueue.main.async {
                        self.put(img, slotId: self.pickingSlotId)
                        self.pickingSlotId = nil
                    }
                }
            }
            return
        }
        for r in results {
            r.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
                guard let self, let img = obj as? UIImage else { return }
                // ObjC 版直接 append "png"，foo.png 会变成 foo.png.png 而认错槽位；
                // 这里名字自带图片后缀时不再追加。
                let raw = r.itemProvider.suggestedName ?? "image"
                let ext = (raw as NSString).pathExtension.lowercased()
                let name = ["png", "jpg", "jpeg", "webp", "heic"].contains(ext) ? raw : raw + ".png"
                DispatchQueue.main.async {
                    self.placeImage(img, fileName: name)
                }
            }
        }
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true) {
            guard let img = info[.originalImage] as? UIImage else { return }
            // ObjC 版：这里只调 put（pickingSlotId 为 nil 时 put 直接返回，批量图会被丢掉）—— 照原样
            self.put(img, slotId: self.pickingSlotId)
            self.pickingSlotId = nil
        }
    }

    private func put(_ img: UIImage, slotId: String?, theme: String? = nil) {
        guard let sid = slotId else { return }
        // 默认按当前查看主题存（手动点选路径）；批量导入传匹配到的主题，
        // 否则一张夜间图会在日间视图下被存进日间槽位。
        let theme = theme ?? (viewNight ? "night" : "day")
        let px = Int(img.size.width * img.scale)
        let py = Int(img.size.height * img.scale)
        state["\(sid)|\(theme)"] = PlacedImage(image: img, w: px, h: py)
        refresh()
    }

    private func placeImage(_ img: UIImage, fileName: String) {
        let m = BubbleNaming.shared.matchFileName(fileName, directories: [])
        let theme = (m.isNight && wantsNight) ? "night" : "day"
        if let sid = m.slot?.identifier {
            // 认得出：直接放进对应槽位（已占满就覆盖，命名始终正确）。
            // 旧逻辑在槽位已占满/认不出时会把图塞进下一个空文字气泡，
            // 导致导出文件名错乱——这里改为精确归位。
            put(img, slotId: sid, theme: theme)
            return
        }
        // 认不出名字：不偷偷塞进文字气泡，收进未识别清单，统计区提示用户手动处理。
        // 这些图不会进入任何槽位，因此也不会被导出到 zip。
        unrecognized.append((name: fileName, image: img))
        refresh()
    }

    // MARK: - 导入 / 导出

    func importImages(_ images: [String: UIImage]) {
        for (fileName, image) in images {
            placeImage(image, fileName: fileName)
        }
    }

    @objc private func doExport() {
        // 导出过门：壳子设了授权检查就先问它（未授权时壳子弹授权提示，
        // 这里直接不导）；没设置时直接导出。
        if let check = exportAuthorizationCheck {
            check { [weak self] allowed in
                guard allowed else { return }
                DispatchQueue.main.async { self?.performExport() }
            }
            return
        }
        performExport()
    }

    private func performExport() {
        // 唯一一处有意改动：ObjC 版把 PNG 写到临时目录再调 SSZipArchive；
        // 这里直接用 App 现成的 ZipWriter 打包，输出文件名与静默行为一致。
        // 另按提示文案补了夜间 fallback：夜间没放图的槽位导出时沿用日间那张
        //（ObjC 版代码没做这一步，文案与代码不一致，这里按文案修齐）。
        var entries: [ZipWriter.Entry] = []
        for slot in BubbleNaming.shared.textSlots() + BubbleNaming.shared.otherSlots() {
            for theme in ["day", "night"] {
                if theme == "night" && !wantsNight { continue }
                let it = state["\(slot.identifier)|\(theme)"]
                    ?? (theme == "night" ? state["\(slot.identifier)|day"] : nil)
                guard let it else { continue }
                guard let data = it.image.pngData() else { continue }
                entries.append(ZipWriter.Entry(name: outName(slot, theme: theme, placed: it), data: data))
            }
        }
        if entries.isEmpty { return }
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("气泡包.zip")
        try? FileManager.default.removeItem(at: zipURL)
        let data = ZipWriter.archive(entries: entries)
        do {
            try data.write(to: zipURL)
            onExport?(zipURL)
        } catch {
            // ObjC 版 zip 失败时静默（无回调），这里同样静默
        }
    }
}
