import ActivityKit
import Foundation

/// Facade between the update engine and ActivityKit. Callers in
/// AppUpdateChecker stay unconditional: every entry point checks
/// the 在灵动岛与锁屏显示更新进度 switch (UpdateSettings.showProgress)
/// and the iOS 16.1 availability gate — below that the Live
/// Activity simply never starts and the in-app progress pill keeps
/// working exactly as before.
enum UpdateLiveActivity {
    static func downloadStarted(versionLabel: String) {
        guard UpdateSettings.showProgress else { return }
        if #available(iOS 16.1, *) {
            Controller.shared.start(versionLabel: versionLabel)
        }
    }

    static func downloadProgressed(progress: Double, bytesLine: String) {
        guard UpdateSettings.showProgress else { return }
        if #available(iOS 16.1, *) {
            Controller.shared.update(progress: progress, bytesLine: bytesLine)
        }
    }

    /// Completion or failure: the final state shows for a few
    /// seconds, then the system dismisses the activity.
    static func downloadEnded(statusText: String, succeeded: Bool) {
        if #available(iOS 16.1, *) {
            Controller.shared.end(statusText: statusText, succeeded: succeeded)
        }
    }

    /// A user cancel ends the activity at once (no final state).
    static func downloadCancelled() {
        if #available(iOS 16.1, *) {
            Controller.shared.cancel()
        }
    }

    @available(iOS 16.1, *)
    private final class Controller {
        static let shared = Controller()

        private var activity: Activity<UpdateActivityAttributes>?
        private var lastPercent = -1
        private var lastProgress: Double = 0

        func start(versionLabel: String) {
            cancel()
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let attributes = UpdateActivityAttributes(
                appName: AppConfiguration.displayName.isEmpty ? "LUIYo" : AppConfiguration.displayName,
                versionLabel: versionLabel)
            let state = UpdateActivityAttributes.ContentState(
                progress: 0, statusText: "下载中", bytesLine: "")
            activity = try? Activity.request(attributes: attributes, contentState: state, pushType: nil)
            lastPercent = 0
            lastProgress = 0
        }

        func update(progress: Double, bytesLine: String) {
            guard let activity else { return }
            // Throttle: the activity only changes on whole percents.
            let percent = Int((progress * 100).rounded(.down))
            guard percent != lastPercent else { return }
            lastPercent = percent
            lastProgress = progress
            let state = UpdateActivityAttributes.ContentState(
                progress: progress, statusText: "下载中", bytesLine: bytesLine)
            Task { await activity.update(using: state) }
        }

        func end(statusText: String, succeeded: Bool) {
            guard let activity else { return }
            self.activity = nil
            lastPercent = -1
            let state = UpdateActivityAttributes.ContentState(
                progress: succeeded ? 1 : lastProgress,
                statusText: statusText, bytesLine: "")
            Task {
                await activity.end(using: state, dismissalPolicy: .after(Date().addingTimeInterval(5)))
            }
        }

        func cancel() {
            guard let activity else { return }
            self.activity = nil
            lastPercent = -1
            Task { await activity.end(dismissalPolicy: .immediate) }
        }
    }
}
