# LUIYo（UIKit 版）

当前版本：**1.0.8**（`Info.plist` 的 `CFBundleVersion` 为准，每次交付 +1）

LUIYo 是一款图标主题素材处理工具：导入素材后可按命名规则批量整理、补全与预览图标，最后一键导出 ZIP。本仓库是主 App 的现行源码，已完成从旧网页方案到纯原生方案的迁移：

- **纯 UIKit 实现**：全工程零 `import SwiftUI`，界面全部由 UIKit 控制器构建。
- **零网页内容**：IPA 内不包含任何网页文件，旧版由脚本实现的图标处理引擎已用原生 Swift 重新实现（`Engine/`）。
- **系统原生材质**：界面使用 iOS 系统原生玻璃/磨砂材质，不自绘仿制。

可执行文件名为 `YouYouLUI`，Bundle ID 为 `com.youyou.lui`。

## 主要功能

- **首页**：素材导入与管理、工具栏操作（反馈、批量导入、补全图片、清空、导出 ZIP）、图标预览与状态显示。
- **规则页**：命名规则的浏览与核对（内置规则数据见 `RulesNative/`）。
- **我的**：设置入口页，含外观、字体、反馈、更新检查等。
- **字体与外观**：可分别选择一款英文字体与一款中文字体，并按页（首页 / 规则页 / 设置页）勾选应用范围；内置字体放在 `Fonts/`；配色通过系统取色器调整。
- **触感与音效反馈**：全局 `AppFeedback` 提供 4 档触感与 4 档提示音（合成点击声）设置。
- **授权与更新**：App 启动后联网校验授权状态，并支持检查新版本（仅功能描述，服务细节不在本仓库公开）。
- **导出 ZIP**：图标处理结果打包导出；该功能为授权功能，未授权状态下不可用，其余功能不受影响。

## 原生层结构

源码位于 `YouYouLUI_iOS/YouYouLUI/`，按职责分层：

| 目录 | 职责 |
| --- | --- |
| `App/` | 进程入口、根控制器选择、Bundle 配置（`AppDelegate`、`AppRoot`、`AppConfiguration`） |
| `Shell/` | 三页容器：Tab 结构、页面切换、搜索（`MainShellViewController`、`ShellTabs` 等） |
| `Home/` | 首页：素材列表、工具栏、图标目录与主题（`HomeViewController`、`NativeHomeModel`、`NativeHomeCatalog`） |
| `RulesNative/` | 规则页与命名规则数据（`RulesViewController`、`NamingRulesData`） |
| `SettingsNative/` | 设置页：外观、字体、更新检查（`SettingsViewController`、`FontSettingsViewController`、`AppUpdateChecker`） |
| `Engine/` | 原生图标处理引擎：图片处理、图标生成、ZIP 写入（`IconEngine`、`EngineImageProcessing`、`ZipWriter`）及规则/预览数据 JSON |
| `Theme/` | 偏好存储、调色板、字体库与字体控制（`ThemePreferences`、`ThemePalette`、`FontLibrary`） |
| `Activation/` | 授权流程：会话、心跳校验、设备标识、封禁弹窗（`ActivationSession`、`ActivationClient`、`DeviceIdentity`） |
| `Security/` | Keychain 令牌存储（`KeychainStore`） |
| `Export/` | ZIP 导出与系统分享（`ZipExportCoordinator`） |
| `Media/` | 照片/文件选择、头像存储（`ImagePickerCoordinator`、`AvatarStore`） |
| `Materials/` | 原生材质视图（`NativeMaterialView`） |
| `Support/` | 颜色、弹窗、路径、卡片等工具（`ColorHex`、`AlertPresenter`、`AppPaths`、`UIKitCards`） |
| `SettingsHero/` | 设置页品牌卡（Objective-C，`LUISettingsHeroAdapter`、`LUISettingsHeroCell`） |
| `Fonts/`、`Icons/`、`Assets.xcassets` | 内置字体、工具栏/页面图标与图片资产 |

## 构建

使用 GitHub Actions 的 **Build LUIYo IPA** 工作流（`.github/workflows/build-ipa.yml`，macOS 15 Intel runner + Xcode 26）：

- 推送到 `main` 或在 Actions 页手动 Run workflow 即可打包；
- 构建脚本为 `scripts/build-ipa.sh`，本地等价命令：`bash scripts/build-ipa.sh`；
- 产物为未签名 IPA，安装前使用自己的签名方式。

## 交付命名约定

- IPA 与源码备份包统一命名：`LUIYo-1.x.x-Build(n)`（如 `LUIYo-1.0.8-Build(7).ipa`）。
- 每次交付同时提供一份干净的源码备份 zip：只包含真实源码，不含 `patches/`、`scripts/fix-*.py`、`scripts/build-ipa.sh.bak`、`scripts/split-assets/`。
- 更新日志按版本号分段维护在 `scripts/release-notes.json`，旧版本记录不删除；同一版本内条目顺序为新增 → 优化 → 修复。
