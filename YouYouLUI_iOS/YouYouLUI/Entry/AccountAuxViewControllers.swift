import UIKit

/// Aux pages of the account gate, all in the register/login design
/// language (same card, same fields, same buttons): the password
/// reset form and the blocking banned page. Each form sits on a
/// plain white region inside the card, echoing the main page's
/// `.forms` body. (The new-device email-confirmation wait page is
/// gone in Build 16 — the slider captcha replaced that flow.)

// MARK: - Reset password

final class ResetPasswordViewController: AccountFormBaseViewController {
    /// Fired with the email once the password has been reset.
    var onResetSuccess: ((String) -> Void)?

    private let whiteView = UIView()
    private var emailField: FormField!
    private var emailChip: SuffixChip!
    private var codeField: FormField!
    private var codeButton: UIButton!
    private var countdown: CodeCountdown!
    private var passField: FormField!
    private var passEye: EyeButton!
    private let submitButton = DarkButton()

    override func viewDidLoad() {
        pageTitle = "找回密码"
        super.viewDidLoad()
        whiteView.backgroundColor = .white
        whiteView.layer.cornerRadius = 26
        cardView.addSubview(whiteView)
        let (emailF, chip) = makeEmailField()
        emailField = emailF; emailChip = chip
        emailChip.onLayoutNeeded = { [weak self] in self?.relayout(animated: false) }
        let (codeF, codeBtn) = makeCodeField(target: self, action: #selector(getCodeTapped))
        codeField = codeF; codeButton = codeBtn
        countdown = CodeCountdown(button: codeBtn)
        let (passF, eye) = makePasswordField(
            placeholder: "设置新密码", hint: "至少 8 个字符，需含大写和小写字母各 1 个。")
        passField = passF; passEye = eye
        passField.marginBottom = 7
        for field in [emailField, codeField, passField] {
            whiteView.addSubview(field!.view)
            field!.onHeightChanged = { [weak self] in self?.relayout(animated: true) }
        }
        submitButton.setTitle("重置密码", for: .normal)
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        whiteView.addSubview(submitButton)
    }

    private var formW: CGFloat = 0

    override func contentHeight(forWidth width: CGFloat) -> CGFloat {
        let w = width - 40 - 32
        var y: CGFloat = 22
        for field in [emailField, codeField, passField] {
            y += field!.layout(width: w) + field!.marginBottom
        }
        return y + 48 + 22
    }

    override func layoutContent(originY: CGFloat, width: CGFloat) {
        let h = contentHeight(forWidth: width)
        whiteView.frame = CGRect(x: 20, y: originY, width: width - 40, height: h)
        formW = width - 40 - 32
        var y: CGFloat = 22
        for field in [emailField, codeField, passField] {
            field!.view.frame = CGRect(x: 16, y: y, width: formW, height: 0)
            y += field!.layout(width: formW) + field!.marginBottom
        }
        layoutSuffixChip(emailChip, fieldWidth: formW)
        layoutCodeButton(codeButton, in: codeField, fieldWidth: formW)
        layoutEyeButton(passEye, fieldWidth: formW)
        submitButton.frame = CGRect(x: 16, y: y, width: formW, height: 48)
    }

    @objc private func getCodeTapped() {
        if countdown.isCounting { return }
        let email = emailChip.resolvedEmail()
        if emailField.text.trimmingCharacters(in: .whitespaces).isEmpty {
            emailField.setError("请输入邮箱地址。"); return
        }
        if !AccountViewController.emailValid(email) {
            emailField.setError("邮箱格式不完整，请检查。"); return
        }
        emailField.setError(nil)
        performProtected("send_code", ["email": email, "purpose": "reset"],
                         onStart: { [weak self] in self?.codeButton.isEnabled = false }
        ) { [weak self] result in
            guard let self, let result else { return }
            switch AccountAPI.outcome(result) {
            case .ok:
                countdown.start()
            case .error(let message):
                codeButton.isEnabled = true
                if message.contains("未注册") { emailField.setError(message) }
                else { codeField.setError(message) }
            }
        }
    }

    @objc private func submitTapped() {
        let email = emailChip.resolvedEmail()
        var firstBad: UITextField?
        if emailField.text.trimmingCharacters(in: .whitespaces).isEmpty {
            emailField.setError("请输入邮箱地址。"); firstBad = emailField.input
        } else if !AccountViewController.emailValid(email) {
            emailField.setError("邮箱格式不完整，请检查。"); firstBad = firstBad ?? emailField.input
        } else { emailField.setError(nil) }
        let code = codeField.text.trimmingCharacters(in: .whitespaces)
        if code.isEmpty {
            codeField.setError("请输入验证码。"); firstBad = firstBad ?? codeField.input
        } else if !(code.count == 6 && code.allSatisfy({ $0.isNumber })) {
            codeField.setError("验证码为 6 位数字。"); firstBad = firstBad ?? codeField.input
        } else { codeField.setError(nil) }
        if let issue = AccountViewController.passwordIssue(passField.text) {
            passField.setError(issue); firstBad = firstBad ?? passField.input
        } else { passField.setError(nil) }
        if let firstBad {
            firstBad.becomeFirstResponder()
            return
        }
        performProtected("reset_password", [
            "email": email, "password": passField.text, "code": code
        ], onStart: { [weak self] in self?.submitButton.setBusy("正在重置…") }
        ) { [weak self] result in
            guard let self, let result else { return }
            switch AccountAPI.outcome(result) {
            case .ok:
                submitButton.setSuccess()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    self.onResetSuccess?(email)
                }
            case .error(let message):
                submitButton.restore(title: "重置密码")
                if message.contains("验证码") { codeField.setError(message) }
                else if message.contains("密码") { passField.setError(message) }
                else { emailField.setError(message) }
            }
        }
    }
}

// MARK: - Banned (blocking)

final class BannedViewController: AccountFormBaseViewController {
    var onButton: (() -> Void)?

    private let banTitleText: String
    private let banSubtitleText: String
    private let banReasonText: String
    private let buttonTitle: String

    private let whiteView = UIView()
    private let subtitleLabel = UILabel()
    private let reasonLabel = UILabel()
    private let actionButton = DarkButton()

    init(banTitle: String, banSubtitle: String, banReason: String, buttonTitle: String) {
        banTitleText = banTitle
        banSubtitleText = banSubtitle
        banReasonText = banReason
        self.buttonTitle = buttonTitle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        pageTitle = banTitleText.isEmpty ? "账号已被封禁" : banTitleText
        super.viewDidLoad()
        whiteView.backgroundColor = .white
        whiteView.layer.cornerRadius = 26
        cardView.addSubview(whiteView)
        subtitleLabel.text = banSubtitleText
        subtitleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        subtitleLabel.textColor = AccountPalette.ink
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        whiteView.addSubview(subtitleLabel)
        reasonLabel.text = banReasonText
        reasonLabel.font = .systemFont(ofSize: 14)
        reasonLabel.textColor = AccountPalette.muted
        reasonLabel.textAlignment = .center
        reasonLabel.numberOfLines = 0
        whiteView.addSubview(reasonLabel)
        actionButton.setTitle(buttonTitle, for: .normal)
        actionButton.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        whiteView.addSubview(actionButton)
    }

    private func textHeight(_ label: UILabel, width: CGFloat) -> CGFloat {
        guard let text = label.text, !text.isEmpty else { return 0 }
        return ceil((text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: label.font as Any], context: nil).height)
    }

    override func contentHeight(forWidth width: CGFloat) -> CGFloat {
        let w = width - 40 - 32
        var h: CGFloat = 28
        let subH = textHeight(subtitleLabel, width: w)
        if subH > 0 { h += subH + 12 }
        let reasonH = textHeight(reasonLabel, width: w)
        if reasonH > 0 { h += reasonH }
        return h + 28 + 48 + 26
    }

    override func layoutContent(originY: CGFloat, width: CGFloat) {
        let h = contentHeight(forWidth: width)
        whiteView.frame = CGRect(x: 20, y: originY, width: width - 40, height: h)
        let w = width - 40 - 32
        var y: CGFloat = 28
        let subH = textHeight(subtitleLabel, width: w)
        if subH > 0 {
            subtitleLabel.frame = CGRect(x: 16, y: y, width: w, height: subH)
            y += subH + 12
        }
        let reasonH = textHeight(reasonLabel, width: w)
        if reasonH > 0 {
            reasonLabel.frame = CGRect(x: 16, y: y, width: w, height: reasonH)
            y += reasonH
        }
        actionButton.frame = CGRect(x: 16, y: y + 28, width: w, height: 48)
    }

    @objc private func buttonTapped() { onButton?() }
}
