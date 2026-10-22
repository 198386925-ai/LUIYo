import Combine
import Foundation
import UIKit

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

    /// Check the update feed at launch, at most once per 6 hours.
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
final class AppUpdateChecker: NSObject, ObservableObject {
    static let shared = AppUpdateChecker()

    /// The same static feed the launch version popup reads (it looks
    /// at `version_states`; this checker reads the release fields —
    /// the two never interfere).
    static let feedURL = URL(string: "https://luioe.bbroot.com/updates/latest.json")!

    private static let failureText = "连接失败，请检查网络和安装服务后重试。"
    private static let lastAutoCheckKey = "luiyo.update.lastAutoCheckAt"

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

    private lazy var downloadSession: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()
    private var downloadTask: URLSessionDownloadTask?

    private var currentBuild: Int {
        Int(AppConfiguration.buildNumber) ?? 0
    }

    // MARK: - Checking

    /// Launch path: gated by the 自动检查更新 switch and a 6-hour
    /// throttle, exactly like the reference page's footnote says.
    static func runLaunchAutoCheckIfNeeded() {
        guard UpdateSettings.autoCheck else { return }
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: lastAutoCheckKey)
        guard now - last >= 6 * 3600 else { return }
        UserDefaults.standard.set(now, forKey: lastAutoCheckKey)
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
        guard updateFound, downloadTask == nil,
              let url = URL(string: downloadURLString) else { return }
        userCancelledDownload = false
        downloadedFileURL = nil
        downloadedBytes = 0
        totalBytes = expectedTotalBytes
        downloadProgress = 0
        phase = .downloading
        statusText = "发现新版 \(latestVersion) (Build \(latestBuild))"
        downloadTask = downloadSession.downloadTask(with: url)
        downloadTask?.resume()
        UpdateLiveActivity.downloadStarted(versionLabel: "\(latestVersion) (Build \(latestBuild))")
    }

    func cancelDownload() {
        userCancelledDownload = true
        downloadTask?.cancel()
        downloadTask = nil
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

    /// Re-presents the share sheet for an already downloaded IPA.
    func shareDownloaded() {
        guard let fileURL = downloadedFileURL else { return }
        presentShareSheet(fileURL: fileURL)
    }

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
        let fileName = "LUIYo-\(latestVersion)-Build(\(latestBuild)).ipa"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destination)
        let moved = (try? FileManager.default.moveItem(at: location, to: destination)) != nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.downloadTask = nil
            if moved {
                self.downloadedFileURL = destination
                self.downloadProgress = 1
                self.phase = .downloaded
                self.statusText = "下载完成，确认后即可安装"
                UpdateLiveActivity.downloadEnded(statusText: "完成", succeeded: true)
                self.presentShareSheet(fileURL: destination)
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
}
