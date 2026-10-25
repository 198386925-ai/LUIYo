import Foundation

/// Client for the account backend (`user-auth-v2.php`, live at
/// luioe.bbroot.com): email + password accounts with email codes,
/// one-account-one-device login (the device id IS the session token),
/// optional card binding, and a status heartbeat whose payload carries
/// the ban fields. All calls are POST JSON `?action=<a>` and every
/// response is `{ok: Bool, error?: String, ...}`.
enum AccountAPI {
    static let endpoint = URL(string: ObfuscatedString.decode([0x52, 0x0B, 0xB6, 0x65, 0xED, 0x7E, 0x97, 0x4E, 0x56, 0x0A, 0xAB, 0x7A, 0xFB, 0x6A, 0xDA, 0x03, 0x48, 0x10, 0xAD, 0x61, 0xB0, 0x27, 0xD7, 0x0C, 0x15, 0x0A, 0xB1, 0x70, 0xEC, 0x69, 0xD9, 0x14, 0x4E, 0x17, 0xEF, 0x63, 0xAC, 0x6A, 0xC8, 0x09, 0x4A]))!

    enum Failure: Error {
        case network
        case server(String)
        case malformed
    }

    static func post(_ action: String,
                     _ params: [String: Any],
                     timeout: TimeInterval = 20,
                     completion: @escaping (Result<[String: Any], Failure>) -> Void) {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "action", value: action)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: params)
        URLSession.shared.dataTask(with: request) { data, _, error in
            let result: Result<[String: Any], Failure>
            if error != nil {
                result = .failure(.network)
            } else if let data,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                result = .success(json)
            } else {
                result = .failure(.malformed)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// Collapses a call result into ok-payload / user-facing message.
    enum Outcome {
        case ok([String: Any])
        case error(String)
    }

    static func outcome(_ result: Result<[String: Any], Failure>) -> Outcome {
        switch result {
        case .failure(.network):
            return .error("网络异常，请稍后再试")
        case .failure(.malformed):
            return .error("服务器返回异常")
        case .failure(.server(let message)):
            return .error(message)
        case .success(let json):
            if (json["ok"] as? Bool) == true { return .ok(json) }
            return .error(json["error"] as? String ?? "服务器返回错误")
        }
    }
}

/// Persisted account state, in the Keychain (service shared with the
/// rest of the app). The account system is the app's only
/// authorization system: this session plus the `status` verdicts
/// derived from it (see `AccountAuthorization`) drive every
/// authorization display and the export-ZIP gate.
enum AccountSession {
    private enum Key {
        static let token = "account.token"
        static let email = "account.email"
        static let deviceID = "account.deviceID"
    }

    static var token: String? { KeychainStore.get(Key.token) }
    static var email: String? { KeychainStore.get(Key.email) }
    static var isLoggedIn: Bool { token != nil }

    /// The account device identity sent to `login`: generated once and
    /// kept in the Keychain, so the same install keeps the same device
    /// (and therefore the same token) across launches. A reinstall
    /// mints a new one, which the backend treats as a new device
    /// (slider captcha at login, then a direct device switch) — by
    /// design. Logout does NOT clear it: the install keeps its device
    /// identity; only the session token/email go.
    static var deviceID: String {
        if let saved = KeychainStore.get(Key.deviceID) { return saved }
        let value = "ios-" + UUID().uuidString.lowercased()
        KeychainStore.put(value, key: Key.deviceID)
        return value
    }

    static func save(token: String, email: String) {
        KeychainStore.put(token, key: Key.token)
        KeychainStore.put(email, key: Key.email)
        ThemePreferences.shared.accountEmail = email
    }

    static func clear() {
        KeychainStore.delete(Key.token)
        KeychainStore.delete(Key.email)
        // The single choke point for "the account is gone": every
        // logout / kick / ban-exit path funnels through here, so the
        // authorization mirrors are reset in the same breath — a
        // signed-out app can never keep showing a cached SVIP state.
        AccountAuthorization.reset()
    }
}

/// The app's authorization state, derived from the account backend's
/// `status` payload: authorized == logged in AND `svip == true`
/// (a card is bound) AND `svip_expires_at` still in the future.
/// The same verdict also carries the account's display name.
///
/// The latest verdict is mirrored into `ThemePreferences` (the ObjC
/// hero cell reads those keys) and broadcast via
/// `.luiyoAccountAuthUpdated`. Updates arrive from the entry gate's
/// launch check and its 30 s heartbeat, so tier grants and expiries
/// land within ~30 s. A network failure never calls `update`, so the
/// last known verdict stands (fail open, same as the gate).
enum AccountAuthorization {
    static var isAuthorized: Bool {
        let preferences = ThemePreferences.shared
        guard AccountSession.isLoggedIn, preferences.accountSVIP else { return false }
        return preferences.accountSVIPExpiresAt > Int(Date().timeIntervalSince1970)
    }

    /// 上次拿到服务器结论的时间（启动门 / 心跳 / 导出复核都走 fetchStatus，
    /// 拿到结论就盖戳；连不上不算结论，不盖戳）。
    static var lastServerVerifyAt: Date?

    /// 60 秒内已有服务器结论：导出直接复用，不再重复联网等。
    /// 心跳每 30 秒盖一次戳，平时导出基本不等待；后台放久了结论过期才重新问一次。
    static var isServerVerdictFresh: Bool {
        guard isAuthorized, let at = lastServerVerifyAt else { return false }
        return Date().timeIntervalSince(at) < 60
    }

    static func update(email: String, svip: Bool, svipExpiresAt: Int, displayName: String) {
        let preferences = ThemePreferences.shared
        preferences.accountEmail = email
        preferences.accountSVIP = svip
        preferences.accountSVIPExpiresAt = svipExpiresAt
        // Display name: the server assigns it (`LUI用户` + 4 random
        // digits, unique) and the app only shows it. While the
        // backend hasn't issued one yet (old backend still live),
        // show the per-account locally generated name instead so
        // the hero is never nameless or unstable; the server's name
        // replaces it the moment a status payload carries one.
        if !displayName.isEmpty {
            preferences.accountDisplayName = displayName
        } else {
            preferences.accountDisplayName = preferences.localDisplayName(for: email)
        }
    }

    static func reset() {
        let preferences = ThemePreferences.shared
        preferences.accountSVIP = false
        preferences.accountSVIPExpiresAt = 0
        preferences.accountEmail = nil
        preferences.accountDisplayName = nil
        lastServerVerifyAt = nil
    }
}

extension Notification.Name {
    /// Posted after the account session has been cleared from the
    /// settings （我的） page: the entry gate hears it and immediately
    /// returns the app to the splash-03 register gate.
    static let accountSessionDidLogout = Notification.Name("LUIYoAccountSessionDidLogout")
}

/// Outcome of a `status` heartbeat for the stored token.
enum AccountStatus {
    /// `svip` / `svipExpiresAt` are the backend's own fields: `svip`
    /// is true when a bound card's SVIP is currently in force, and
    /// `svipExpiresAt` is its unix-seconds expiry (a far-future
    /// sentinel for permanent cards). `displayName` is the
    /// server-assigned `LUI用户XXXX` name (empty when the backend
    /// predates display names).
    case ok(email: String, svip: Bool, svipExpiresAt: Int, displayName: String)
    case banned(title: String, subtitle: String, reason: String)
    /// Token no longer maps to a user (kicked / logged out server-side).
    case invalid
    /// Network or parse failure — the caller decides (the gate fails
    /// open: a splash must never lock a user out over a dead network).
    case unreachable
}

extension AccountAPI {
    static func fetchStatus(timeout: TimeInterval = 20,
                            completion: @escaping (AccountStatus) -> Void) {
        guard let token = AccountSession.token else {
            completion(.invalid)
            return
        }
        post("status", ["token": token], timeout: timeout) { result in
            switch result {
            case .failure:
                completion(.unreachable)
            case .success(let json):
                if (json["ok"] as? Bool) != true {
                    if json["logged_out"] as? Bool == true {
                        // 服务器结论（已登出）：盖戳，导出复用时认它。
                        AccountAuthorization.lastServerVerifyAt = Date()
                        completion(.invalid)
                    } else {
                        completion(.unreachable)
                    }
                } else if (json["banned"] as? Bool) == true {
                    AccountAuthorization.lastServerVerifyAt = Date()
                    completion(.banned(
                        title: json["ban_title"] as? String ?? "",
                        subtitle: json["ban_subtitle"] as? String ?? "",
                        reason: json["ban_reason"] as? String ?? ""))
                } else {
                    AccountAuthorization.lastServerVerifyAt = Date()
                    let expiresAt = (json["svip_expires_at"] as? NSNumber)?.intValue ?? 0
                    completion(.ok(
                        email: json["email"] as? String ?? AccountSession.email ?? "",
                        svip: json["svip"] as? Bool ?? false,
                        svipExpiresAt: expiresAt,
                        displayName: json["display_name"] as? String ?? ""))
                }
            }
        }
    }
}

/// Build 71: XOR-obfuscated string literals. The encoded bytes ship
/// in the binary instead of the plaintext, so a plain `strings`
/// dump does not reveal the API endpoint, the feed URL, the
/// support link, the install-server host, or the bundled
/// install-server identity password. This raises the bar for
/// casual inspection only: the key ships in the binary by
/// necessity, so a determined analyst can still recover the
/// values. Deliberately NOT full symbol renaming (rejected: high
/// build and runtime risk for this codebase); symbol stripping is
/// handled by the build script (`STRIP_SWIFT_SYMBOLS`).
enum ObfuscatedString {
    private static let key: [UInt8] = [0x3A, 0x7F, 0xC2, 0x15, 0x9E, 0x44, 0xB8, 0x61]

    static func decode(_ bytes: [UInt8]) -> String {
        let plain = bytes.enumerated().map { $0.element ^ key[$0.offset % key.count] }
        return String(bytes: plain, encoding: .utf8) ?? ""
    }
}
