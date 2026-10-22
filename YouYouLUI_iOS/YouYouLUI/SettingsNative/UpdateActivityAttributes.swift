import ActivityKit
import Foundation

/// Live Activity payload for an update download, shared verbatim
/// between the app (which starts/updates the activity) and the
/// LUIYoLiveActivity widget extension (which renders it). The file
/// is a member of BOTH targets — the two sides must agree on the
/// attributes and content-state shape or the system cannot match
/// the running activity to its UI.
@available(iOS 16.1, *)
struct UpdateActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 0...1 download fraction.
        var progress: Double
        /// 下载中 / 完成 / 失败
        var statusText: String
        /// "12.4 MB / 24.0 MB" style byte line ("" when unknown).
        var bytesLine: String
    }

    /// The app's display name ("LUIYo").
    var appName: String
    /// The update being downloaded, e.g. "1.0.9 (Build 27)".
    var versionLabel: String
}
