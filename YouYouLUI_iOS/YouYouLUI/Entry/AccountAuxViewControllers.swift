import UIKit

/// Aux pages of the account gate, all in the register/login design
/// language (same card, same fields, same buttons): the password
/// reset form. Each form sits on a plain white region inside the
/// card, echoing the main page's `.forms` body. (The new-device
/// email-confirmation wait page is gone in Build 16 — the slider
/// captcha replaced that flow. The plain banned page is gone in
/// Build 20 — an account ban now shows the red fig2 banned popup,
/// see VersionPopup.accountBanPayload.)

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
        // Build 21: same captcha prefetch as the account page —
        // reset_password is a protected action too.
        CaptchaPrefetch.warm()
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
        passField.marginBottom = AccountMetrics.shortFieldGap
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
        let w = width - 2 * AccountMetrics.panelInset - 32
        var y: CGFloat = AccountMetrics.formPadTop
        for field in [emailField, codeField, passField] {
            y += field!.layout(width: w) + field!.marginBottom
        }
        return y + AccountMetrics.buttonHeight + AccountMetrics.formPadBottom
    }

    override func layoutContent(originY: CGFloat, width: CGFloat) {
        let h = contentHeight(forWidth: width)
        whiteView.frame = CGRect(x: AccountMetrics.panelInset, y: originY,
                                 width: width - 2 * AccountMetrics.panelInset, height: h)
        formW = width - 2 * AccountMetrics.panelInset - 32
        var y: CGFloat = AccountMetrics.formPadTop
        for field in [emailField, codeField, passField] {
            field!.view.frame = CGRect(x: 16, y: y, width: formW, height: 0)
            y += field!.layout(width: formW) + field!.marginBottom
        }
        layoutSuffixChip(emailChip, fieldWidth: formW)
        layoutCodeButton(codeButton, in: codeField, fieldWidth: formW)
        layoutEyeButton(passEye, fieldWidth: formW)
        submitButton.frame = CGRect(x: 16, y: y, width: formW, height: AccountMetrics.buttonHeight)
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
        performDirect("reset_password", [
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
