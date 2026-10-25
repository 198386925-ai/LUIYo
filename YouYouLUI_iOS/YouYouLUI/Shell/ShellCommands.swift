import UIKit

extension MainShellViewController {
    /// Routes a command to the native work layer. Authorization rule: an
    /// unauthorized user may use everything EXCEPT exporting the ZIP, so
    /// only the export action is gated here (the work layer is only ever
    /// reached through this router and handleHomeCommand).
    func runNativeEngine(_ action: String, _ values: [String: Any]) {
        if action == "export", !isAuthorized {
            showAuthorizationRequired()
            return
        }
        switch action {
        case "state":
            engine.start()
        case "category":
            engine.setCategory(values["category"] as? String ?? "wechat")
        case "search":
            break // the homepage filters its own list from the same query
        case "remove":
            if let id = values["id"] as? Int { engine.remove(index: id) }
        case "clear":
            engine.clear()
        case "fill":
            engine.applyFill(query: values["query"] as? String ?? "")
        case "colors":
            engine.colorsUpdated()
        case "export":
            verifyExportAuthorization()
        default:
            break
        }
    }

    /// Build 71 export online verification (user rule): a locally
    /// authorized export still asks the server first. A live verdict
    /// rules: authorized → export; banned/invalid/unbound → block
    /// and refresh the local mirror. Only a truly unreachable server
    /// falls back to the cached local authorization (the user's
    /// no-network choice: offline exports keep working).
    /// Build 90: a server verdict from the last 60 s (launch gate /
    /// heartbeat) is reused, so a normal export no longer waits on
    /// the network again; a stale verdict still re-asks.
    private func verifyExportAuthorization() {
        // 60 秒内已有服务器结论（启动门 / 心跳刚问过）：直接导出，不再重复联网等。
        if AccountAuthorization.isServerVerdictFresh {
            self.engine.startExport()
            return
        }
        showNotice("正在验证授权…")
        AccountAPI.fetchStatus(timeout: 8) { [weak self] status in
            guard let self else { return }
            switch status {
            case .ok(let email, let svip, let svipExpiresAt, let displayName):
                AccountAuthorization.update(email: email, svip: svip, svipExpiresAt: svipExpiresAt, displayName: displayName)
                self.setAuthorization(AccountAuthorization.isAuthorized)
                if AccountAuthorization.isAuthorized {
                    self.engine.startExport()
                } else {
                    self.showAuthorizationRequired()
                }
            case .banned, .invalid:
                AccountAuthorization.update(email: AccountSession.email ?? "", svip: false, svipExpiresAt: 0, displayName: "")
                self.setAuthorization(false)
                self.showAuthorizationRequired()
            case .unreachable:
                self.engine.startExport()
            }
        }
    }

    /// Bubble-pack export gate: the same two layers as the main export
    /// (local fast-fail, then the Build 71 server re-check; unreachable
    /// falls back to the cached local authorization, which already
    /// passed the fast-fail above). Only the zip export is gated —
    /// playing in the editor stays free, like every other page.
    /// Build 90: same 60 s fresh-verdict reuse as the main export.
    func verifyBubbleExportAuthorization(completion: @escaping (Bool) -> Void) {
        if !AccountAuthorization.isAuthorized {
            showAuthorizationRequired()
            completion(false)
            return
        }
        // 60 秒内已有服务器结论：直接放行，不再重复联网等。
        if AccountAuthorization.isServerVerdictFresh {
            completion(true)
            return
        }
        showNotice("正在验证授权…")
        AccountAPI.fetchStatus(timeout: 8) { [weak self] status in
            guard let self else { return }
            switch status {
            case .ok(let email, let svip, let svipExpiresAt, let displayName):
                AccountAuthorization.update(email: email, svip: svip, svipExpiresAt: svipExpiresAt, displayName: displayName)
                self.setAuthorization(AccountAuthorization.isAuthorized)
                if AccountAuthorization.isAuthorized {
                    completion(true)
                } else {
                    self.showAuthorizationRequired()
                    completion(false)
                }
            case .banned, .invalid:
                AccountAuthorization.update(email: AccountSession.email ?? "", svip: false, svipExpiresAt: 0, displayName: "")
                self.setAuthorization(false)
                self.showAuthorizationRequired()
                completion(false)
            case .unreachable:
                completion(true)
            }
        }
    }

    /// Commands raised by the native homepage.
    func handleHomeCommand(_ action: String, _ values: [String: Any]) {
        if action == "export", !isAuthorized { showAuthorizationRequired(); return }
        guard nativeHomeReady else { return }
        switch action {
        case "upload", "batch", "fillImage":
            let kind = ImagePickerCoordinator.Kind(rawValue: action) ?? .upload
            imagePicker.chooseImage(kind: kind, index: values["id"] as? Int)
        case "clear":
            AlertPresenter.confirm(title: "清空上传图片？",
                                   message: "将移除本次上传与补全图片。",
                                   confirmTitle: "清空",
                                   destructive: true,
                                   on: self) { [weak self] in
                self?.runNativeEngine("clear", [:])
            }
        case "authorize":
            showAuthorizationRequired()
        default:
            runNativeEngine(action, values)
        }
    }

    func receiveFiles(_ files: [[String: String]], kind: ImagePickerCoordinator.Kind, index: Int?) {
        let engineFiles = files.compactMap { raw -> EngineFile? in
            guard let base64 = raw["base64"], let data = Data(base64Encoded: base64) else { return nil }
            return EngineFile(name: raw["name"] ?? "image.png", data: data)
        }
        switch kind {
        case .upload:
            if let index, let first = engineFiles.first { engine.receiveSingle(index: index, file: first) }
        case .batch:
            engine.receiveBatch(engineFiles)
        case .fillImage:
            if let first = engineFiles.first { engine.receiveFillImage(first) }
        }
    }

    func showNotice(_ text: String) {
        AlertPresenter.notice(message: text, on: self)
    }

    func showAuthorizationRequired() {
        let alert = UIAlertController(title: "尚未激活",
                                      message: "其他功能都可以正常使用，只有导出 ZIP 需要激活。激活来自你的账号：账号绑定卡密且 SVIP 未过期即为已激活。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .cancel))
        alert.addAction(UIAlertAction(title: "前往设置", style: .default) { [weak self] _ in
            guard let self else { return }
            self.selectPage(.settings)
            self.navigateFromNativeTab(ShellPage.settings.rawValue)
        })
        present(alert, animated: true)
    }

    // MARK: - Bottom search

    func presentBottomSearch() {
        guard bottomSearchEnabled, !openingSearch, activeSearchController == nil,
              presentedViewController == nil else { return }
        activeSearchPage = activePage.name
        let query = activePage == .rules ? rulesModel.query : homeModel.query
        showSearchOverlay(state: ["query": query, "page": activeSearchPage, "placeholder": "搜索"])
    }

    private func showSearchOverlay(state: [String: Any]) {
        let page = SearchOverlayViewController()
        page.query = state["query"] as? String ?? ""
        page.themeFont = fontController.font(for: .home)
        page.backgroundImage = backgroundImageView.image
        page.placeholder = state["placeholder"] as? String ?? "搜索"
        page.onSearch = { [weak self] query in self?.applyBottomSearch(query) }
        page.onClose = { [weak self] in
            guard let self else { return }
            self.homeModel.query = ""
            self.rulesModel.query = ""
            let overlay = self.activeSearchController
            self.activeSearchController = nil
            overlay?.willMove(toParent: nil)
            overlay?.view.removeFromSuperview()
            overlay?.removeFromParent()
            UIView.performWithoutAnimation {
                self.keepContentBelowNativeBar()
                self.view.layoutIfNeeded()
                self.updateLayoutMetrics(force: true)
            }
        }
        activeSearchController = page
        // A transparent child overlay leaves the live page and tab bar attached.
        addChild(page)
        page.view.frame = view.bounds
        page.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(page.view)
        page.view.layer.zPosition = 3
        page.didMove(toParent: self)
        page.view.layoutIfNeeded()
        page.searchField.becomeFirstResponder()
    }

    func applyBottomSearch(_ query: String) {
        if activeSearchPage == "home" { homeModel.query = query }
        if activeSearchPage == "rules" { rulesModel.query = query }
    }
}
