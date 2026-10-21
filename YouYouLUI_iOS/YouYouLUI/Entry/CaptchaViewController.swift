import UIKit

/// Slider human-verification (Build 16), replacing the old
/// new-device email-confirmation flow end to end.
///
/// The backend issues one-time challenges (`captcha_new` → a
/// per-mille notch position, 120 s expiry); the user drags the
/// handle onto the notch and `captcha_verify` checks the landing
/// point (|x − target| ≤ 40 per-mille, drag ≥ 400 ms) and returns a
/// proof token bound to this device, valid 10 minutes and reusable
/// inside that window. Protected actions (send_code, register,
/// login, reset_password) require the proof as `captcha_proof`;
/// without one the server answers `code: captcha_required`.
///
/// The proof lives in MEMORY only — it is a short-lived anti-bot
/// token, not session state.

enum CaptchaStore {
    private static var proof: String?
    private static var expiresAt: Date = .distantPast

    static var validProof: String? {
        guard let proof, Date() < expiresAt else { return nil }
        return proof
    }

    static func store(_ proof: String, expiresIn: TimeInterval = 600) {
        self.proof = proof
        expiresAt = Date().addingTimeInterval(expiresIn)
    }

    static func invalidate() {
        proof = nil
        expiresAt = .distantPast
    }
}

enum CaptchaGate {
    /// Completes true when a valid proof is held afterwards (either
    /// already in memory or freshly verified); false on cancel.
    static func ensureProof(from presenter: UIViewController,
                            completion: @escaping (Bool) -> Void) {
        if CaptchaStore.validProof != nil {
            completion(true)
            return
        }
        let captcha = CaptchaViewController()
        captcha.onDone = completion
        captcha.modalPresentationStyle = .overFullScreen
        captcha.modalTransitionStyle = .crossDissolve
        presenter.present(captcha, animated: true)
    }
}

extension AccountFormBaseViewController {
    /// Runs one of the backend's captcha-protected actions: secures
    /// a slider proof first (the captcha sheet appears only when no
    /// valid proof is held — the register flow asks ONCE for
    /// 获取验证码 → 创建账户）, attaches `captcha_proof` + `device_id`,
    /// and if the server still answers `captcha_required` (a proof
    /// that expired between check and call), re-verifies once and
    /// retries. The completion receives the raw post result, or nil
    /// when the user cancelled the captcha — nothing was sent and
    /// callers simply stand down. `onStart` fires right before each
    /// actual send, so busy states only engage once a send is real.
    func performProtected(_ action: String, _ params: [String: Any],
                          onStart: (() -> Void)? = nil,
                          completion: @escaping (Result<[String: Any], AccountAPI.Failure>?) -> Void) {
        CaptchaGate.ensureProof(from: self) { [weak self] ok in
            guard let self else { return }
            guard ok else { completion(nil); return }
            onStart?()
            self.sendProtected(action, params, retried: false, completion: completion)
        }
    }

    private func sendProtected(_ action: String, _ params: [String: Any], retried: Bool,
                               completion: @escaping (Result<[String: Any], AccountAPI.Failure>?) -> Void) {
        var body = params
        body["device_id"] = AccountSession.deviceID
        if let proof = CaptchaStore.validProof { body["captcha_proof"] = proof }
        AccountAPI.post(action, body) { [weak self] result in
            guard let self else { return }
            if !retried,
               case .success(let json) = result,
               (json["ok"] as? Bool) != true,
               (json["code"] as? String) == "captcha_required" {
                CaptchaStore.invalidate()
                CaptchaGate.ensureProof(from: self) { [weak self] ok in
                    guard let self else { return }
                    guard ok else { completion(result); return }
                    self.sendProtected(action, params, retried: true, completion: completion)
                }
                return
            }
            completion(result)
        }
    }
}

// MARK: - Slider captcha sheet

final class CaptchaViewController: AccountFormBaseViewController {
    /// Fired once, after the sheet has dismissed: true with a proof
    /// stored, false when the user cancelled.
    var onDone: ((Bool) -> Void)?

    private let whiteView = UIView()
    private let hintLabel = UILabel()
    private let trackView = UIView()
    private let notchView = UIView()
    private let fillView = UIView()
    private let handleView = UIView()
    private let statusLabel = UILabel()
    private let cancelButton = UIButton(type: .custom)

    private var challengeID: String?
    private var targetPerMille = 0
    private var handleX: CGFloat = 0
    private var dragStartX: CGFloat = 0
    private var dragStartTime: CFTimeInterval = 0
    private var verifying = false
    private var finished = false

    private let handleSize: CGFloat = 48

    override func viewDidLoad() {
        pageTitle = "安全验证"
        super.viewDidLoad()
        whiteView.backgroundColor = .white
        whiteView.layer.cornerRadius = 26
        cardView.addSubview(whiteView)

        hintLabel.text = "拖动滑块，将滑块移到缺口处完成验证。"
        hintLabel.font = .systemFont(ofSize: 13.5)
        hintLabel.textColor = AccountPalette.inkSoft
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        whiteView.addSubview(hintLabel)

        trackView.backgroundColor = splashHex("#f0f0f3")
        trackView.layer.cornerRadius = 24
        trackView.clipsToBounds = true
        whiteView.addSubview(trackView)
        notchView.backgroundColor = splashHex("#dcdce2")
        notchView.layer.borderWidth = 1.5
        notchView.layer.borderColor = splashHex("#c2c2cc").cgColor
        notchView.layer.cornerRadius = 24
        trackView.addSubview(notchView)
        fillView.backgroundColor = AccountPalette.dark.withAlphaComponent(0.14)
        trackView.addSubview(fillView)

        handleView.backgroundColor = .white
        handleView.layer.cornerRadius = 24
        handleView.layer.borderWidth = 1
        handleView.layer.borderColor = AccountPalette.line.cgColor
        handleView.layer.shadowColor = UIColor.black.cgColor
        handleView.layer.shadowOpacity = 0.18
        handleView.layer.shadowRadius = 8
        handleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        let chevron = UIImageView(
            image: UIImage(named: "AccountChevron")?.withRenderingMode(.alwaysTemplate))
        chevron.tintColor = AccountPalette.dark
        chevron.contentMode = .scaleAspectFit
        // The shipped chevron points down; a quarter turn makes it
        // the drag-right affordance.
        chevron.transform = CGAffineTransform(rotationAngle: -.pi / 2)
        chevron.frame = CGRect(x: (handleSize - 18) / 2, y: (handleSize - 18) / 2,
                               width: 18, height: 18)
        handleView.addSubview(chevron)
        whiteView.addSubview(handleView)
        handleView.addGestureRecognizer(
            UIPanGestureRecognizer(target: self, action: #selector(handlePanned(_:))))

        statusLabel.font = .systemFont(ofSize: 12.5)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        whiteView.addSubview(statusLabel)

        cancelButton.setTitle("取消", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 12.5)
        cancelButton.setTitleColor(splashHex("#aaacb6"), for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        whiteView.addSubview(cancelButton)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if challengeID == nil { loadChallenge() }
    }

    // MARK: Layout

    override func contentHeight(forWidth width: CGFloat) -> CGFloat {
        24 + 20 + 16 + 48 + 14 + 18 + 16 + 21 + 22
    }

    override func layoutContent(originY: CGFloat, width: CGFloat) {
        let h = contentHeight(forWidth: width)
        whiteView.frame = CGRect(x: 20, y: originY, width: width - 40, height: h)
        let w = width - 40 - 32
        var y: CGFloat = 24
        hintLabel.frame = CGRect(x: 16, y: y, width: w, height: 20)
        y += 20 + 16
        trackView.frame = CGRect(x: 16, y: y, width: w, height: handleSize)
        positionPieces()
        y += handleSize + 14
        statusLabel.frame = CGRect(x: 16, y: y, width: w, height: 18)
        y += 18 + 16
        cancelButton.frame = CGRect(x: 16, y: y, width: w, height: 21)
    }

    /// Places the notch (at the challenge target), the progress fill
    /// and the handle inside/along the track for the current state.
    private func positionPieces() {
        let trackW = trackView.bounds.width
        guard trackW > handleSize else { return }
        let maxX = trackW - handleSize
        let notchX = CGFloat(targetPerMille) / 1000 * maxX
        notchView.frame = CGRect(x: notchX, y: 0, width: handleSize, height: handleSize)
        handleX = min(max(handleX, 0), maxX)
        handleView.frame = CGRect(x: trackView.frame.minX + handleX,
                                  y: trackView.frame.minY,
                                  width: handleSize, height: handleSize)
        fillView.frame = CGRect(x: 0, y: 0, width: handleX + handleSize / 2,
                                height: handleSize)
    }

    // MARK: Challenge lifecycle

    private func loadChallenge() {
        challengeID = nil
        handleX = 0
        positionPieces()
        AccountAPI.post("captcha_new", ["device_id": AccountSession.deviceID]) { [weak self] result in
            guard let self, !finished else { return }
            switch AccountAPI.outcome(result) {
            case .ok(let json):
                challengeID = json["cid"] as? String
                targetPerMille = json["target"] as? Int ?? 0
                positionPieces()
            case .error:
                setStatus("验证加载失败，请取消后重试", danger: true)
            }
        }
    }

    @objc private func handlePanned(_ gesture: UIPanGestureRecognizer) {
        guard challengeID != nil, !verifying, !finished else { return }
        let maxX = trackView.bounds.width - handleSize
        guard maxX > 0 else { return }
        switch gesture.state {
        case .began:
            dragStartX = handleX
            dragStartTime = CACurrentMediaTime()
            setStatus(nil, danger: false)
        case .changed:
            handleX = min(max(dragStartX + gesture.translation(in: trackView).x, 0), maxX)
            positionPieces()
        case .ended:
            let perMille = Int((handleX / maxX * 1000).rounded())
            let durationMs = Int((CACurrentMediaTime() - dragStartTime) * 1000)
            verify(perMille: perMille, durationMs: durationMs)
        case .cancelled, .failed:
            resetHandle()
        default:
            break
        }
    }

    private func verify(perMille: Int, durationMs: Int) {
        guard let cid = challengeID else { resetHandle(); return }
        verifying = true
        AccountAPI.post("captcha_verify", [
            "cid": cid, "x": perMille, "duration_ms": durationMs,
            "device_id": AccountSession.deviceID
        ]) { [weak self] result in
            guard let self, !finished else { return }
            verifying = false
            switch AccountAPI.outcome(result) {
            case .ok(let json):
                if let proof = json["proof"] as? String {
                    let expires = (json["expires_in"] as? Int).map(TimeInterval.init) ?? 600
                    CaptchaStore.store(proof, expiresIn: expires)
                    setStatus("验证通过", danger: false, success: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.finish(true)
                    }
                } else {
                    fail(message: "验证未通过，请再试一次")
                }
            case .error(let message):
                fail(message: message)
            }
        }
    }

    /// A miss: shake the track, drop the handle back and fetch a
    /// fresh challenge (challenges are one-time).
    private func fail(message: String) {
        setStatus(message, danger: true)
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -9, 8, -5, 3, 0]
        shake.duration = 0.32
        trackView.layer.add(shake, forKey: "shake")
        resetHandle()
        loadChallenge()
    }

    private func resetHandle() {
        UIView.animate(withDuration: 0.22) {
            self.handleX = 0
            self.positionPieces()
        }
    }

    private func setStatus(_ text: String?, danger: Bool, success: Bool = false) {
        statusLabel.text = text
        statusLabel.textColor = success
            ? AccountPalette.success
            : (danger ? AccountPalette.danger : AccountPalette.muted)
    }

    @objc private func cancelTapped() {
        finish(false)
    }

    private func finish(_ ok: Bool) {
        guard !finished else { return }
        finished = true
        dismiss(animated: true) { [weak self] in
            self?.onDone?(ok)
        }
    }
}
