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
        return true
    }
}
