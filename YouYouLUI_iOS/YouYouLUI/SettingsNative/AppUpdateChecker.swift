import Combine
import Foundation
import UIKit
import UserNotifications

/// UserDefaults-backed switches for the 检查更新 page, modelled on the
/// reference update page: progress presentation, automatic checks,
/// automatic download and auto-exit after the install handoff. All
/// default ON, matching the reference.
enum UpdateSettings {
    private static let defaults = UserDefaults.standard

    private static func boolValue(_ key: String) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    /// Show the floating download-progress pill in the shell.
    static var showProgress: Bool {
        get { boolValue("luiyo.update.showProgress") }
        set { defaults.set(newValue, forKey: "luiyo.update.showProgress") }
    }

    /// Check the update feed at launch, at most once per hour.
    static var autoCheck: Bool {
        get { boolValue("luiyo.update.autoCheck") }
        set { defaults.set(newValue, forKey: "luiyo.update.autoCheck") }
    }

    /// Start the download in the background as soon as a check finds
    /// a newer build.
    static var autoDownload: Bool {
        get { boolValue("luiyo.update.autoDownload") }
        set { defaults.set(newValue, forKey: "luiyo.update.autoDownload") }
    }

    /// Terminate the app once a completed download has been handed
    /// off (the share sheet finished with a chosen destination).
    static var autoExitAfterInstall: Bool {
        get { boolValue("luiyo.update.autoExit") }
        set { defaults.set(newValue, forKey: "luiyo.update.autoExit") }
    }

    /// LCSign install node selection (single option for now).
    static var installNode: String {
        get { defaults.string(forKey: "luiyo.update.installNode") ?? "自动" }
        set { defaults.set(newValue, forKey: "luiyo.update.installNode") }
    }
}

/// Update engine for the 检查更新 page: reads the luioe feed
/// (`updates/latest.json`, release-shaped JSON written by
/// app-update.php), compares its build against the app's own, and
/// downloads the offered IPA in-app with delegate-driven progress.
///
/// One shared instance drives everything: the launch auto-check, the
/// badge on the settings row, the shell's progress pill and the page.
///
/// The download runs on a BACKGROUND URLSession, so it continues
/// while the user is elsewhere (home screen / other apps); the
/// system wakes the app when it lands, and the chain — sign, then
/// prepare the on-device install — runs from here, not from the
/// page, so it works whether or not the page is on screen. The
/// install hand-off never kills the app before the installer has
/// fetched the IPA: the auto-exit switch may end the app only
/// after the install server reports the IPA fully served, or
/// after the explicit 分享 fallback completes.
final class AppUpdateChecker: NSObject, ObservableObject {
    static let shared = AppUpdateChecker()

    /// The same static feed the launch version popup reads (it looks
    /// at `version_states`; this checker reads the release fields —
    /// the two never interfere).
    static let feedURL = URL(string: "https://luioe.bbroot.com/updates/latest.json")!

    private static let failureText = "连接失败，请检查网络和安装服务后重试。"
    private static let lastAutoCheckKey = "luiyo.update.lastAutoCheckAt"
    /// Stable identifier for the background download session: the
    /// system reattaches in-flight transfers to a session created
    /// with the same identifier after a relaunch.
    private static let backgroundSessionIdentifier = "com.youyou.lui.update-download"
    private static let pendingDownloadKey = "luiyo.update.pendingDownload"
    private static let installReadyNotificationID = "luiyo.update.install-ready"

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable
        case downloading
        case downloaded
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    /// The status line under the 检查更新 row.
    @Published private(set) var statusText: String = ""
    @Published private(set) var latestVersion: String = ""
    @Published private(set) var latestBuild: Int = 0
    @Published private(set) var releaseNotes: String = ""
    /// A check has found a build newer than our own (badge + offer).
    @Published private(set) var updateFound: Bool = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var downloadedFileURL: URL?

    // MARK: - Chain state (rendered by the 检查更新 page)

    /// In-app signing of the downloaded update is running.
    @Published private(set) var signingInProgress: Bool = false
    /// The signed IPA produced by the chain for the current
    /// download (nil until signing succeeds).
    @Published private(set) var signedFileURL: URL?
    /// Why the chain's sign step failed (auto chain only; a
    /// tap-started chain alerts instead). Rendered on the card's
    /// bytes line above the 分享 fallback.
    @Published private(set) var chainFailureText: String?
    /// A sign attempt for the current download has completed
    /// (success or failure). The page uses it to rest on the
    /// 分享 fallback instead of waiting for a chain that
    /// already ran.
    @Published private(set) var chainSettledForCurrentDownload: Bool = false
    /// Status line for the install hand-off while it is in
    /// flight （安装已发起… / 已准备好安装）, rendered on the
    /// card's bytes line.
    @Published private(set) var installStatusText: String = ""
    /// The install hand-off failed: the card rests on 分享 for
    /// the signed file, with no auto-retry.
    @Published private(set) var installFailed: Bool = false
    /// An install server is up (or the prompt was opened) for the
    /// current signed file.
    @Published private(set) var installInFlight: Bool = false
    /// One-shot alert for the page to present (manual-chain sign
    /// failures, install failures). `alertSequence` increments on
    /// every post so the page can react even to a repeated text.
    @Published private(set) var userAlert: (title: String, message: String)?
    @Published private(set) var alertSequence: Int = 0

    /// Whether the chain (sign → install) is engaged for the
    /// current download: the 自动下载并签名 switch, or a tap on
    /// 立即下载. A tap's engagement is persisted with the
    /// download's metadata so it survives a relaunch.
    var chainEngaged: Bool { UpdateSettings.autoDownload || manualChain }
    private var manualChain = false

    private var downloadURLString: String = ""
    /// The feed's IPA download URL for the latest release (empty
    /// until a check has landed) — used by the LCSign hand-off.
    var latestDownloadURLString: String { downloadURLString }
    private var downloadSHA256: String = ""
    /// The feed asset's SHA-256 for the latest release (bare hex,
    /// the `sha256:` prefix stripped; empty when the feed carries
    /// no usable digest) — handed to LCSign so it can verify the
    /// file it downloads.
    var latestSHA256: String { downloadSHA256 }
    private var expectedTotalBytes: Int64 = 0
    private var userCancelledDownload = false
    /// Set only by the launch/foreground auto-check: when THAT
    /// check discovers a newer build, the update popup is offered
    /// (once per discovered build) on top of the badge. Manual
    /// checks from the 检查更新 page never arm it.
    private var autoDiscoveryArmed = false

    // Chain bookkeeping (this checker owns the chain; the page
    // only renders the published state above).
    private var chainAttemptedFor: URL?
    private var signedForDownloadURL: URL?
    private var installAttemptedFor: URL?
    /// The on-device install server while an install hand-off is
    /// in flight (nil otherwise). Retained here so it keeps
    /// serving until it reports itself stopped.
    private var installServer: LocalInstallServer?
    /// Signing + install are prepared and the server is waiting:
    /// the install prompt still has to be surfaced (the download
    /// finished while the app was in the background). The
    /// manifest URL is opened on the next activation.
    private var pendingInstallPrompt = false
    private var pendingManifestURLString: String?

    /// The completion handler from
    /// `application(_:handleEventsForBackgroundURLSession:)`,
    /// invoked once the background session has delivered all of
    /// its pending events (urlSessionDidFinishEvents).
    var backgroundSessionCompletionHandler: (() -> Void)?

    private lazy var downloadSession: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        // Deliver events even when the system has to relaunch the
        // app for them, and start transfers promptly rather than
        // waiting for "ideal" conditions.
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    private var downloadTask: URLSessionDownloadTask?

    private var currentBuild: Int {
        Int(AppConfiguration.buildNumber) ?? 0
    }

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    // MARK: - Background-session delivery

    /// Called from the app delegate at launch: recreates the
    /// background session (so transfers started by a previous
    /// process reconnect and their completion events are
    /// delivered) and readopts a still-running transfer.
    func prepareForBackgroundDelivery() {
        let session = downloadSession
        session.getAllTasks { [weak self] tasks in
            guard let self,
                  let task = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first
            else { return }
            DispatchQueue.main.async {
                guard self.downloadTask == nil, self.phase != .downloaded else { return }
                self.restorePendingDownloadMetadata()
                guard self.updateFound else { return }
                self.downloadTask = task
                self.phase = .downloading
                self.downloadedBytes = task.countOfBytesReceived
                if task.countOfBytesExpectedToReceive > 0 {
                    self.totalBytes = task.countOfBytesExpectedToReceive
                }
                if self.totalBytes > 0 {
                    self.downloadProgress = min(1, Double(task.countOfBytesReceived) / Double(self.totalBytes))
                }
                self.statusText = "发现新版 \(self.latestVersion) (Build \(self.latestBuild))"
            }
        }
    }

    private func persistPendingDownloadMetadata() {
        UserDefaults.standard.set([
            "version": latestVersion,
            "build": latestBuild,
            "url": downloadURLString,
            "expectedBytes": expectedTotalBytes,
            "manual": manualChain,
        ], forKey: Self.pendingDownloadKey)
    }

    private func restorePendingDownloadMetadata() {
        guard latestBuild == 0,
              let stored = UserDefaults.standard.dictionary(forKey: Self.pendingDownloadKey),
              let version = stored["version"] as? String,
              let build = stored["build"] as? Int, build > currentBuild,
              let url = stored["url"] as? String, !url.isEmpty
        else { return }
        latestVersion = version
        latestBuild = build
        downloadURLString = url
        expectedTotalBytes = (stored["expectedBytes"] as? Int64) ?? 0
        manualChain = (stored["manual"] as? Bool) ?? false
        updateFound = true
    }

    private func clearPendingDownloadMetadata() {
        UserDefaults.standard.removeObject(forKey: Self.pendingDownloadKey)
    }

    // MARK: - Checking

    /// Launch path: gated by the 自动检查更新 switch and a 1-hour
    /// throttle, exactly like the page's footnote says.
    static func runLaunchAutoCheckIfNeeded() {
        guard UpdateSettings.autoCheck else { return }
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: lastAutoCheckKey)
        guard now - last >= 3600 else { return }
        UserDefaults.standard.set(now, forKey: lastAutoCheckKey)
        shared.autoDiscoveryArmed = true
        shared.checkForUpdate()
    }

    func checkForUpdate() {
        guard phase != .checking, phase != .downloading else { return }
        phase = .checking
        statusText = "正在检查…"
        var request = URLRequest(url: Self.feedURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async { self?.handleCheckResult(data: data, error: error) }
        }.resume()
    }

    private func handleCheckResult(data: Data?, error: Error?) {
        // The discovery-popup arming belongs to the check that is
        // completing right now, whichever way it lands.
        let wasAutoDiscovery = autoDiscoveryArmed
        autoDiscoveryArmed = false
        guard error == nil, let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["draft"] as? Bool) != true,
              (json["prerelease"] as? Bool) != true,
              let tag = json["tag_name"] as? String,
              let parsed = Self.parseTag(tag),
              let asset = (json["assets"] as? [[String: Any]])?.first,
              let urlString = asset["browser_download_url"] as? String,
              !urlString.isEmpty
        else {
            phase = .failed
            statusText = Self.failureText
            return
        }
        let discoveredNewBuild = parsed.build != latestBuild
        latestVersion = parsed.version
        latestBuild = parsed.build
        releaseNotes = (json["body"] as? String) ?? ""
        downloadURLString = urlString
        if let digest = asset["digest"] as? String, digest.hasPrefix("sha256:") {
            let hex = String(digest.dropFirst("sha256:".count))
            downloadSHA256 = (hex.count == 64 && hex.allSatisfy { $0.isHexDigit }) ? hex.lowercased() : ""
        } else {
            downloadSHA256 = ""
        }
        expectedTotalBytes = (asset["size"] as? Int).map { Int64($0) } ?? 0

        if parsed.build > currentBuild {
            updateFound = true
            phase = .updateAvailable
            statusText = "发现新版 \(parsed.version) (Build \(parsed.build))"
            if discoveredNewBuild {
                // A different build than the one any earlier tap
                // engaged a chain for: the tap's engagement (and
                // only it) starts over.
                manualChain = false
            }
            if wasAutoDiscovery {
                // A background discovery also raises the update
                // popup (once per build) — the same soft popup the
                // version-state path presents.
                VersionPopup.presentDiscoveredUpdateIfNeeded(
                    version: parsed.version, build: parsed.build,
                    notes: releaseNotes, downloadURL: URL(string: urlString))
            }
            if UpdateSettings.autoDownload {
                startDownload()
            }
        } else {
            updateFound = false
            phase = .upToDate
            statusText = "已是最新版本"
        }
    }

    /// `v<version>-b<build>` → (version, build).
    private static func parseTag(_ tag: String) -> (version: String, build: Int)? {
        guard tag.hasPrefix("v"), let dash = tag.range(of: "-b", options: .backwards) else { return nil }
        let version = String(tag[tag.index(after: tag.startIndex)..<dash.lowerBound])
        let buildString = String(tag[dash.upperBound...])
        guard !version.isEmpty, let build = Int(buildString) else { return nil }
        return (version, build)
    }

    // MARK: - Downloading

    func startDownload() {
        if phase == .downloaded, downloadedFileURL != nil {
            // The file is already here (e.g. it landed in the
            // background): a fresh start request just re-engages
            // the chain on it.
            driveChain()
            return
        }
        guard updateFound, downloadTask == nil,
              let url = URL(string: downloadURLString) else { return }
        resetChainState()
        userCancelledDownload = false
        downloadedFileURL = nil
        downloadedBytes = 0
        totalBytes = expectedTotalBytes
        downloadProgress = 0
        phase = .downloading
        statusText = "发现新版 \(latestVersion) (Build \(latestBuild))"
        persistPendingDownloadMetadata()
        requestInstallNotificationAuthorization()
        downloadTask = downloadSession.downloadTask(with: url)
        downloadTask?.resume()
        UpdateLiveActivity.downloadStarted(versionLabel: "\(latestVersion) (Build \(latestBuild))")
    }

    /// 立即下载 tapped: engages the chain (sign → install) for
    /// this download whether it starts now or has already landed.
    func startManualChain() {
        manualChain = true
        persistPendingDownloadMetadata()
        if phase == .downloaded, downloadedFileURL != nil {
            driveChain()
        } else {
            startDownload()
        }
    }

    func cancelDownload() {
        userCancelledDownload = true
        downloadTask?.cancel()
        downloadTask = nil
        clearPendingDownloadMetadata()
        UpdateLiveActivity.downloadCancelled()
        downloadProgress = 0
        downloadedBytes = 0
        phase = .updateAvailable
        statusText = "发现新版 \(latestVersion) (Build \(latestBuild))"
    }

    /// Records a successful hand-off of the offered IPA to LCSign:
    /// the status line now tells the user to finish inside LCSign.
    /// (The hand-off itself stays a deliberate user tap — the
    /// auto-download switch never opens LCSign on its own, and the
    /// auto-exit switch only applies to the share-sheet handoff.)
    func markLCSignHandoffCompleted() {
        statusText = "已递交 LCSign，请在 LCSign 中完成签名与安装。"
    }

    /// Presents the share sheet for an already downloaded IPA.
    /// The ONLY caller is the update page's 分享 button — the
    /// explicit fallback for the states where the sign/install
    /// chain cannot run (no cert material, signing or install
    /// failure). Because this is a deliberate user tap and
    /// nothing else reaches it, the auto-exit handler inside
    /// presentShareSheet can only ever follow that fallback,
    /// never the chain.
    func shareDownloaded() {
        guard let fileURL = downloadedFileURL else { return }
        presentShareSheet(fileURL: fileURL)
    }

    /// Only reached via shareDownloaded() (the page's explicit
    /// 分享 fallback). The auto-exit on completion therefore
    /// cannot fire while the local install server is serving:
    /// the install chain never presents this sheet.
    private func presentShareSheet(fileURL: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.maxY - 40,
                                        width: 1, height: 1)
        }
        activity.completionWithItemsHandler = { _, completed, _, _ in
            // The install handoff only counts when the user actually
            // picked a destination; dismissing the sheet keeps the
            // app alive (the reference page's footnote semantics).
            guard completed, UpdateSettings.autoExitAfterInstall else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
        }
        presenter.present(activity, animated: true)
    }

    static func formatBytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    // MARK: - The chain: sign → prepare install → surface prompt

    /// Clears every trace of a previous chain run (signed file,
    /// install state, pending prompt). A previous install server
    /// is stopped quietly — its handlers are detached first so
    /// its stop cannot be mistaken for an install outcome (the
    /// auto-exit in particular must not follow it).
    private func resetChainState() {
        if let server = installServer {
            server.onReady = nil
            server.onStopped = nil
            server.onIPAServed = nil
            server.stop()
            installServer = nil
        }
        signingInProgress = false
        signedFileURL = nil
        signedForDownloadURL = nil
        chainFailureText = nil
        chainSettledForCurrentDownload = false
        installStatusText = ""
        installFailed = false
        installInFlight = false
        chainAttemptedFor = nil
        installAttemptedFor = nil
        pendingInstallPrompt = false
        pendingManifestURLString = nil
        removeInstallReadyNotifications()
    }

    /// Drives the chain one step for the current downloaded file:
    /// sign it (once), then prepare the install. Idempotent —
    /// safe to call whenever state settles (download finished,
    /// cert imported, page re-rendered). Does nothing unless the
    /// chain is engaged and there is a finished download.
    func driveChain() {
        guard phase == .downloaded, let downloaded = downloadedFileURL else { return }
        if signedFileURL != nil {
            driveInstall()
            return
        }
        guard chainEngaged, UpdateSigner.canSign, !signingInProgress,
              chainAttemptedFor != downloaded else { return }
        chainAttemptedFor = downloaded
        signingInProgress = true
        UpdateSigner.signDownloadedUpdate(
            ipa: downloaded, version: latestVersion, build: latestBuild
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.signingInProgress = false
                self.chainSettledForCurrentDownload = true
                switch result {
                case .success(let signedURL):
                    self.signedFileURL = signedURL
                    self.signedForDownloadURL = downloaded
                    self.chainFailureText = nil
                    self.driveInstall()
                case .failure(let failure):
                    if self.manualChain {
                        // A tap-started chain surfaces its failure
                        // with an alert (if a page is there to
                        // present it) and rests on 分享.
                        self.postAlert(title: "签名失败", message: failure.message)
                    } else {
                        self.chainFailureText = "自动签名失败：\(failure.message)"
                    }
                }
            }
        }
    }

    /// Starts the on-device install server for the signed IPA.
    /// When it is listening: if the app is active, the system's
    /// itms-services prompt is opened immediately (the app
    /// backgrounds, the server — holding its background-task
    /// assertion — stays resident and serves the IPA); if the
    /// app is in the background, everything is left prepared, a
    /// local notification is posted, and the prompt is opened
    /// the moment the app next activates.
    private func driveInstall() {
        guard let signed = signedFileURL, LocalInstallServer.isAvailable,
              installAttemptedFor != signed, !installFailed else { return }
        installAttemptedFor = signed
        if let old = installServer {
            old.onReady = nil
            old.onStopped = nil
            old.onIPAServed = nil
            old.stop()
            installServer = nil
        }
        let metadata = LocalInstallServer.metadata(forIPA: signed, fallbackVersion: latestVersion)
        let server = LocalInstallServer()
        installServer = server
        installInFlight = true
        // Shared between this server's two handlers: whether the
        // installer has actually fetched the whole IPA from it.
        var ipaServed = false
        server.onIPAServed = { [weak self, weak server] in
            guard let self, let server, self.installServer === server else { return }
            ipaServed = true
        }
        server.onReady = { [weak self, weak server] port in
            guard let self, let server, self.installServer === server else { return }
            let manifestURL = "https://\(LocalInstallServer.host):\(port)/manifest.plist"
            self.pendingManifestURLString = manifestURL
            if UIApplication.shared.applicationState == .active {
                self.installStatusText = "安装已发起，请按系统提示完成。"
                self.openInstallManifest(manifestURL)
            } else {
                self.pendingInstallPrompt = true
                self.installStatusText = "新版本已准备好安装"
                self.scheduleInstallReadyNotification()
            }
        }
        server.onStopped = { [weak self, weak server] reason in
            guard let self, let server, self.installServer === server else { return }
            self.installServer = nil
            switch reason {
            case .failed(let failure):
                // No auto-retry: the card falls back to sharing
                // the signed file.
                self.installFailed = true
                self.installInFlight = false
                self.pendingInstallPrompt = false
                self.postAlert(title: "安装失败", message: failure.message)
            case .timeout:
                self.installInFlight = false
                if self.pendingInstallPrompt {
                    // The server expired while waiting for the
                    // user to come back. Stay pending: activation
                    // re-arms a fresh server and opens the prompt
                    // then. (The process was never killed — the
                    // server is simply restarted on demand.)
                    self.installAttemptedFor = nil
                }
            case .finished:
                self.pendingInstallPrompt = false
                if ipaServed, UpdateSettings.autoExitAfterInstall {
                    // The installer has fetched the whole IPA and
                    // the server has shut down after its grace
                    // window. Only now — never before the fetch —
                    // may the auto-exit switch end the app.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
                }
            }
        }
        server.start(ipaURL: signed, metadata: metadata)
    }

    private func openInstallManifest(_ manifestURLString: String) {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = manifestURLString.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "itms-services://?action=download-manifest&url=\(encoded)") else {
            postAlert(title: "安装失败", message: "安装链接无效。")
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            if !success {
                self?.postAlert(title: "安装失败", message: "无法打开系统安装入口，请改用分享安装。")
            }
        }
    }

    // MARK: - Pending install surfacing

    @objc private func applicationDidBecomeActive() {
        activatePendingInstallIfNeeded()
    }

    /// A prepared install is waiting (its download + signing
    /// finished while the app was in the background): surface
    /// the system prompt now that the app is active. If the
    /// install server expired meanwhile, a fresh one is armed
    /// first and its onReady opens the prompt.
    func activatePendingInstallIfNeeded() {
        guard pendingInstallPrompt, signedFileURL != nil else { return }
        removeInstallReadyNotifications()
        if installServer != nil, let manifestURL = pendingManifestURLString {
            pendingInstallPrompt = false
            installStatusText = "安装已发起，请按系统提示完成。"
            openInstallManifest(manifestURL)
        } else {
            pendingInstallPrompt = false
            driveInstall()
        }
    }

    private func requestInstallNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleInstallReadyNotification() {
        let content = UNMutableNotificationContent()
        content.title = "新版本已准备好"
        content.body = "点此安装 LUIYo \(latestVersion)（Build \(latestBuild)）"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: Self.installReadyNotificationID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func removeInstallReadyNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.installReadyNotificationID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.installReadyNotificationID])
    }

    private func postAlert(title: String, message: String) {
        userAlert = (title: title, message: message)
        alertSequence += 1
    }
}

// MARK: - URLSessionDownloadDelegate

extension AppUpdateChecker: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.phase == .downloading else { return }
            self.downloadedBytes = totalBytesWritten
            if totalBytesExpectedToWrite > 0 {
                self.totalBytes = totalBytesExpectedToWrite
            }
            if self.totalBytes > 0 {
                self.downloadProgress = min(1, Double(totalBytesWritten) / Double(self.totalBytes))
            }
            let bytesLine = self.totalBytes > 0
                ? "\(Self.formatBytes(totalBytesWritten)) / \(Self.formatBytes(self.totalBytes))"
                : "已下载 \(Self.formatBytes(totalBytesWritten))"
            UpdateLiveActivity.downloadProgressed(progress: self.downloadProgress, bytesLine: bytesLine)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file is deleted when this callback returns — move
        // it out synchronously, hand the result to the main queue.
        // (After a relaunch for background delivery the in-memory
        // metadata may be gone; read what startDownload persisted
        // for the file name here, and restore the state itself on
        // the main queue below.)
        var nameVersion = latestVersion
        var nameBuild = latestBuild
        if nameBuild == 0,
           let stored = UserDefaults.standard.dictionary(forKey: Self.pendingDownloadKey),
           let version = stored["version"] as? String,
           let build = stored["build"] as? Int {
            nameVersion = version
            nameBuild = build
        }
        let fileName = "LUIYo-\(nameVersion)-Build(\(nameBuild)).ipa"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destination)
        let moved = (try? FileManager.default.moveItem(at: location, to: destination)) != nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.restorePendingDownloadMetadata()
            self.downloadTask = nil
            self.clearPendingDownloadMetadata()
            if moved {
                self.downloadedFileURL = destination
                self.downloadProgress = 1
                self.phase = .downloaded
                self.statusText = "下载完成，确认后即可安装"
                UpdateLiveActivity.downloadEnded(statusText: "完成", succeeded: true)
                // Deliberately NO presentation here: the chain
                // (driveChain) takes the file into signing and
                // the install hand-off, surfacing only the
                // system's own install prompt. Presenting the
                // share sheet at this point (the pre-chain flow
                // did) stacked it under that prompt, and its
                // completion handler's auto-exit could then kill
                // the app — and with it the in-app install
                // server — before the installer had fetched the
                // IPA, failing the install. The share sheet now
                // exists only behind the page's explicit 分享
                // button (shareDownloaded above).
                self.driveChain()
            } else {
                self.phase = .failed
                self.statusText = Self.failureText
                UpdateLiveActivity.downloadEnded(statusText: "失败", succeeded: false)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.phase == .downloading else { return }
            self.downloadTask = nil
            if self.userCancelledDownload || (error as NSError).code == NSURLErrorCancelled {
                self.userCancelledDownload = false
                self.clearPendingDownloadMetadata()
                self.downloadProgress = 0
                self.downloadedBytes = 0
                self.phase = .updateAvailable
                self.statusText = "发现新版 \(self.latestVersion) (Build \(self.latestBuild))"
                UpdateLiveActivity.downloadCancelled()
            } else {
                self.phase = .failed
                self.statusText = Self.failureText
                UpdateLiveActivity.downloadEnded(statusText: "失败", succeeded: false)
            }
        }
    }

    /// All pending events of the background session have been
    /// delivered: release the system's completion handler so it
    /// can finish the background launch.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            let handler = self?.backgroundSessionCompletionHandler
            self?.backgroundSessionCompletionHandler = nil
            handler?()
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppUpdateChecker: UNUserNotificationCenterDelegate {
    /// The install-ready banner is pointless while the app is
    /// already in front of the user (activation surfaces the
    /// prompt directly), so it is never presented in-foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }

    /// A tap on 「新版本已准备好」 brings the app forward; the
    /// didBecomeActive path then opens the install prompt. The
    /// short delayed re-check covers the ordering of the two.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == Self.installReadyNotificationID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                if UIApplication.shared.applicationState == .active {
                    self?.activatePendingInstallIfNeeded()
                }
            }
        }
        completionHandler()
    }
}
