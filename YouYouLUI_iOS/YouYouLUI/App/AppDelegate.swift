import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.overrideUserInterfaceStyle = MainShellViewController.savedAppearanceStyle
        window.backgroundColor = ThemePalette.adaptiveBackground
        #if DEBUG && targetEnvironment(simulator)
        if let scenario = ProcessInfo.processInfo.environment["LUI_SNAPSHOT"] {
            // Snapshot/debug runs skip the account backend entirely;
            // "preview-inline-auth" previews the unauthorized state.
            let shell = MainShellViewController()
            shell.setAuthorization(scenario != "preview-inline-auth")
            window.rootViewController = shell
            window.makeKeyAndVisible()
            self.window = window
            return true
        }
        #endif
        window.rootViewController = EntryGateViewController()
        window.makeKeyAndVisible()
        self.window = window
        VersionPopup.checkIfNeeded(hostWindow: window)
        // Recreate the update checker's background download
        // session at every launch: transfers started by a
        // previous process reconnect to it, and a transfer that
        // finished while the app was gone delivers its
        // completion (and runs the sign/install chain) here.
        AppUpdateChecker.shared.prepareForBackgroundDelivery()
        return true
    }

    /// The system relaunched the app to deliver a background
    /// download session's events: hand the completion handler
    /// to the checker, which invokes it once the session has
    /// delivered everything (urlSessionDidFinishEvents).
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        AppUpdateChecker.shared.backgroundSessionCompletionHandler = completionHandler
        AppUpdateChecker.shared.prepareForBackgroundDelivery()
    }
}
