import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// The app shell: three native UIKit pages in a tab bar, the floating
/// bottom search, and the native work layer (IconEngine) behind the
/// homepage. There is no web content anywhere in the app.
///
/// This type owns composition and state only; behaviour is split across
/// extensions, one file each:
///  - `ShellTabs`            — tab construction and page selection
///  - `ShellWebPlacement`    — where the native pages are seated
///  - `ShellAppearance`      — appearance, palette, fonts, material mode
///  - `ShellCommands`        — requests sent to the work layer
///  - `ShellWebDelegates`    — tab bar delegate
///  - `ShellSnapshot`        — CI snapshot scenarios
///
/// Members are `internal` because those extensions live in separate files.
final class MainShellViewController: UITabBarController {
    // MARK: - Authorization

    var onActivationRequested: (() -> Void)?
    var onLicenseSubmitted: ((String) -> Void)?
    var onPageChanged: ((String) -> Void)?
    var isAuthorized = false
    var authorizationMessage = "未激活 · 仅可浏览"
    var authorizationBusy = false

    // MARK: - Collaborators

    let preferences = ThemePreferences.shared
    let homeModel = NativeHomeModel()
    let fontController = ThemeFontController()
    var engine: IconEngine!
    var imagePicker: ImagePickerCoordinator!
    var zipExport: ZipExportCoordinator!

    // MARK: - Tabs

    var pageTabs: [UITabBarItem] = []
    var pageControllers: [UIViewController] = []
    let searchTabController = UIViewController()
    var retainedTabs: [String: AnyObject] = [:]
    var bottomSearchEnabled = false
    var separateSearch = false
    var activePage: ShellPage = .home

    // MARK: - Page placement

    var boundScrollViews: [ObjectIdentifier: UIScrollView] = [:]
    var nativeHomeHost: HomeViewController?
    var nativeHomeConstraints: [NSLayoutConstraint] = []
    weak var nativeHomeScrollView: UIScrollView?
    var nativeHomeReady = false
    var switchingPage = false
    var suppressWebViewReveal = false
    var pageSwitchGeneration = 0
    var lastFadedNativePage: ShellPage?
    var reportedTabTop: CGFloat = -1
    private var scrollOffsetObservation: NSKeyValueObservation?
    #if DEBUG
    private var nativeHomeScrollObservation: NSKeyValueObservation?
    #endif

    // MARK: - Search

    weak var activeSearchController: SearchOverlayViewController?
    var activeSearchPage = "home"
    var openingSearch = false

    // MARK: - Chrome

    let backgroundImageView = UIImageView()
    var settingsHero: UIView?
    var scrollMinimizeEnabled = false
    var restoredNativeFont = false
    let originalTabLabelFonts = NSMapTable<UILabel, UIFont>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    var defaultTabAppearance: UITabBarAppearance?
    var defaultScrollEdgeAppearance: UITabBarAppearance?

    /// The imported theme font, if one is active.
    var currentThemeFont: UIFont? { fontController.font }

    // MARK: - Lifecycle

    override func loadView() {
        super.loadView()
        let rootView = view!
        // Shared native background on every page.
        rootView.backgroundColor = ThemePalette.adaptiveBackground
        installBackground(in: rootView)
        installEngine()
        configureTabs()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        AppFeedback.install()
        preferences.registerDefaults()
        setScrollMinimize(preferences.minimizeBottomBar)
        separateSearch = preferences.isSeparateSearch
        setBottomSearchEnabled(preferences.bottomSearchEnabled)
        applyAppearance(preferences.appearanceMode)
        nativeHomeReady = true
        refreshHomeTheme()
        engine.start()
        runSnapshotScenarioIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The version popup (VersionPopup) presents only once the home
        // shell has completed its first appearance and the app is
        // active: presenting during the launch phase leaves the popup's
        // baked images / gradient layers uncommitted (a ghost render
        // that only heals after a background→foreground cycle).
        VersionPopup.noteHomeShellDidAppear()
    }

    deinit {
        scrollOffsetObservation?.invalidate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Remove extra layer shadows without replacing native system glass.
        removeExtraLayerShadows(tabBar.layer)
        updateTabLabelFonts(in: tabBar)
        keepContentBelowNativeBar()
        updateLayoutMetrics()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isViewLoaded,
              previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyStoredPalette()
        setNeedsStatusBarAppearanceUpdate()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        traitCollection.userInterfaceStyle == .dark ? .lightContent : .darkContent
    }

    // MARK: - Composition

    private func installBackground(in rootView: UIView) {
        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        backgroundImageView.isUserInteractionEnabled = false
        backgroundImageView.accessibilityElementsHidden = true
        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        rootView.insertSubview(backgroundImageView, at: 0)
        NSLayoutConstraint.activate([
            backgroundImageView.topAnchor.constraint(equalTo: rootView.topAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            backgroundImageView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor)
        ])
        // Custom background image feature removed — clear any previously stored image.
        backgroundImageView.image = nil
        try? FileManager.default.removeItem(at: AppPaths.legacyBackgroundImage)
        homeModel.backgroundImage = nil
    }

    private func installEngine() {
        engine = IconEngine()
        engine.onState = { [weak self] payload in self?.homeModel.apply(payload) }
        engine.onNotice = { [weak self] text in self?.showNotice(text) }
        engine.onExportReady = { [weak self] in
            self?.zipExport.askFileName(default: ZipExportCoordinator.defaultFileName)
        }
        engine.onShareZip = { [weak self] data, fileName in
            self?.zipExport.share(data: data, fileName: fileName)
        }

        imagePicker = ImagePickerCoordinator(presenter: self)
        imagePicker.onFiles = { [weak self] files, kind, index in self?.receiveFiles(files, kind: kind, index: index) }
        imagePicker.onAvatar = { [weak self] data in self?.saveHeroAvatar(data) }
        imagePicker.onFailure = { [weak self] text in self?.showNotice(text) }
        zipExport = ZipExportCoordinator(presenter: self)
        zipExport.onNameChosen = { [weak self] name in self?.engine.finishExport(name: name) }

        homeModel.onCommand = { [weak self] action, values in
            guard let self else { return }
            if action == "category" || action == "search" { self.runNativeEngine(action, values) }
            else { self.handleHomeCommand(action, values) }
        }
        homeModel.onScrollView = { [weak self] scroll in
            guard let self else { return }
            self.nativeHomeScrollView = scroll
            scroll.accessibilityIdentifier = "nativeHomeScroll"
            scroll.keyboardDismissMode = .interactive
            self.keepContentBelowNativeBar()
            #if DEBUG
            self.nativeHomeScrollObservation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                self?.writeNativeHomeDiagnostics()
            }
            self.writeNativeHomeDiagnostics()
            #endif
        }
        fontController.onFontChanged = { [weak self] _ in
            self?.distributeFonts()
        }
    }

    private func configureTabs() {
        // Standard UIKit UITabBar: when built with the iOS 26 SDK and run on
        // iOS 26+, the system supplies Liquid Glass. Do not set a custom
        // background, blur, material or shadow here. Font changes preserve the
        // system appearance.
        delegate = self
        pageTabs = ShellPage.allCases.map { page in
            let item = UITabBarItem(title: page.title,
                                    image: UIImage(systemName: page.iconName),
                                    selectedImage: UIImage(systemName: page.selectedIconName))
            item.tag = page.rawValue
            return item
        }
        pageControllers = pageTabs.map { item in
            let controller = UIViewController()
            controller.tabBarItem = item
            controller.view.backgroundColor = .clear
            return controller
        }
        searchTabController.tabBarItem = UITabBarItem(title: "搜索",
                                                      image: UIImage(systemName: "magnifyingglass"),
                                                      tag: 3)
        searchTabController.view.backgroundColor = .clear
        defaultTabAppearance = tabBar.standardAppearance
        defaultScrollEdgeAppearance = tabBar.scrollEdgeAppearance?.copy() as? UITabBarAppearance
        restoredNativeFont = fontController.restore()
        homeModel.importedFont = fontController.font(for: .home)
    }

    func setAuthorization(_ allowed: Bool, message: String? = nil, busy: Bool = false) {
        homeModel.authorized = allowed
        isAuthorized = allowed
        authorizationMessage = message ?? (allowed ? "已授权" : "未激活 · 仅可浏览")
        authorizationBusy = busy
        syncNativeSettingsAuth()
        if nativeHomeReady { engine.colorsUpdated() }
    }
}
