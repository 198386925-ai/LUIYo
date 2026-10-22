import UIKit

/// Builds the app's root shell. Authorization no longer gates the
/// shell's existence — the entry gate (account door) decides who
/// gets in at all; the shell is only SEEDED with the account
/// system's current verdict (`AccountAuthorization`, from the
/// backend `status` payload), and the entry gate's heartbeat keeps
/// pushing fresh verdicts into it while it lives.
enum AppRoot {
    static func makeRootViewController() -> UIViewController {
        let shell = MainShellViewController()
        shell.setAuthorization(AccountAuthorization.isAuthorized)
        return shell
    }
}
