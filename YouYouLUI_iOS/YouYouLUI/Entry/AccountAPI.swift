import Foundation

/// Client for the account backend (`user-auth-v2.php`, live at
/// luioe.bbroot.com): email + password accounts with email codes,
/// one-account-one-device login (the device id IS the session token),
/// optional card binding, and a status heartbeat whose payload carries
/// the ban fields. All calls are POST JSON `?action=<a>` and every
/// response is `{ok: Bool, error?: String, ...}`.
enum AccountAPI {
    static let endpoint = URL(string: "https://luioe.bbroot.com/user-auth-v2.php")!

    enum Failure: Error {
        case network
        case server(String)
        case malformed
    }

    static func post(_ action: String,
                     _ params: [String: Any],
                     completion: @escaping (Result<[String: Any], Failure>) -> Void) {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "action", value: action)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
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
/// rest of the app). Deliberately separate keys from the OLD device-code
/// activation system (`DeviceIdentity`) — the account gate is only the
/// entry door; the two systems never touch each other's state.
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
    }

    static func clear() {
        KeychainStore.delete(Key.token)
        KeychainStore.delete(Key.email)
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
    case ok(email: String)
    case banned(title: String, subtitle: String, reason: String)
    /// Token no longer maps to a user (kicked / logged out server-side).
    case invalid
    /// Network or parse failure — the caller decides (the gate fails
    /// open: a splash must never lock a user out over a dead network).
    case unreachable
}

extension AccountAPI {
    static func fetchStatus(completion: @escaping (AccountStatus) -> Void) {
        guard let token = AccountSession.token else {
            completion(.invalid)
            return
        }
        post("status", ["token": token]) { result in
            switch result {
            case .failure:
                completion(.unreachable)
            case .success(let json):
                if (json["ok"] as? Bool) != true {
                    completion(json["logged_out"] as? Bool == true ? .invalid : .unreachable)
                } else if (json["banned"] as? Bool) == true {
                    completion(.banned(
                        title: json["ban_title"] as? String ?? "",
                        subtitle: json["ban_subtitle"] as? String ?? "",
                        reason: json["ban_reason"] as? String ?? ""))
                } else {
                    completion(.ok(email: json["email"] as? String ?? AccountSession.email ?? ""))
                }
            }
        }
    }
}
