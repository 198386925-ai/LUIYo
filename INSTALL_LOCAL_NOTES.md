# LUIYo 本机直接安装（local install）说明

App 内「下载 → 签名 → 安装」全程不出 LUIYo、不经过任何服务器：
手机本机起一个 HTTPS 安装服务，把签好的包递给 iOS 系统安装。
这是 LCSign 的本地兜底同款做法（拆它的包确认过：远程节点全灭时，
它用手机本机的 GCDWebServer 服务完成安装）。

> 旧的服务器节点方案（install-node.php + InstallNodeUploader）已废弃：
> App 侧代码已删除；`~/workspace/your_files/install-node.php` 只是闲置
> 文件，不用上传、不用管它。

## 工作流程

1. App 在检查更新页下载新版 IPA，用已存的证书在本机签好（zsign，Build 26 已有）。
   「自动下载并签名」开关打开时，下载完成自动接着签名（这条链与安装方式无关，
   两种路线共用，保留不动）。
2. 签名成功后，offer 卡显示「签名完成 · 已通过签名校验」；主按钮「安装」，
   次按钮「分享」（分享的是已签名文件）。不再自动弹分享表。
3. 用户点「安装」→ `LocalInstallServer` 在本机随机高端口（20000–60000）
   起一个 HTTPS 服务：
   - `GET /manifest.plist`：现生成的 itms-services 清单，其中的包地址是
     `https://i.luioe.bbroot.com:<port>/app.ipa`；清单的 bundle id / 版本 /
     标题读自签好 IPA 自身的 Info.plist（读不到才用更新源的值兜底）。
   - `GET /app.ipa`：流式吐出签好的 IPA（带 Content-Length，不支持 Range）。
   - 其余路径一律 404。
4. App 打开 `itms-services://?action=download-manifest&url=<上面的清单地址>`，
   iOS 解析 `i.luioe.bbroot.com` → 127.0.0.1 → 连回本机服务 → 验 TLS 证书 →
   拉清单、拉包、弹系统安装确认。
5. 服务在 IPA 完整送出后再留 5 秒（系统有时会重读清单）自动停；总寿命
   上限 3 分钟；全程持有后台任务断言，用户点系统弹窗时服务不会被挂起杀掉。
6. 打开安装链接永远只由用户点按触发，自动签名链不会自己发起安装。

## 证书（唯一缺的那块拼图）

| 项 | 要求 |
| --- | --- |
| 内容 | PKCS#12（.p12），含 `i.luioe.bbroot.com` 的证书 + 私钥 + 完整证书链 |
| 签发方 | 公开受信任 CA（Let's Encrypt、ZeroSSL 都行）——iOS 系统安装器只认系统信任链，自签不行 |
| 文件名 | 必须正好是 `InstallServerCert.p12`（代码按这个名字找） |
| 放置位置 | `YouYouLUI_iOS/YouYouLUI/SettingsNative/InstallServerCert.p12`（与 LocalInstallServer.swift 同目录；pbxproj 的文件引用 + Resources 条目已预先写好，放文件即生效） |
| 密码 | 写进 `YouYouLUI/App/AppConfiguration.swift` 的 `installServerCertPassword` 常量（当前为空字符串占位） |

证书不在包里时（当下就是这种状态）：`LocalInstallServer.isAvailable == false`，
检查更新页**完全不显示「安装」按钮**，页面行为等于 Build 29 + 自动签名，
用户不会看到一个点了没用的按钮。

⚠️ 注意：pbxproj 里已经有 InstallServerCert.p12 的 Resources 条目，
**证书文件没放进去之前不要打包**——xcodebuild 会因找不到这个资源文件
直接失败。顺序必须是：先放证书文件，再打包。

## DNS（用户侧，一次性）

给 `luioe.bbroot.com` 加一条子域名解析：`i` → A 记录 → `127.0.0.1`。
这条解析对全世界都成立：任何设备解析 `i.luioe.bbroot.com` 都得到
127.0.0.1，也就是"它自己"，所以装谁的手机就连回谁的手机，不会串。

## 证书续期（约 90 天一次）

免费证书（Let's Encrypt / ZeroSSL）有效期约 90 天。到期前：
重新申请一张同域名的证书 → 打包成 .p12 → 替换
`SettingsNative/InstallServerCert.p12`（若换了密码，同步改
`AppConfiguration.installServerCertPassword`）→ 重新打包发版。
过期未换的后果：本机安装的 TLS 校验过不了，「安装」会失败，
但分享 / LCSign 两条老路不受影响。

## App 侧对应代码

- `SettingsNative/LocalInstallServer.swift`：NWListener + TLS 的本机
  HTTPS 服务（清单生成、IPA 流式发送、3 分钟寿命、后台断言）；
  身份从 `InstallServerCert.p12` 经 SecPKCS12Import 加载，证书链通过
  `sec_identity_create_with_certificates` 显式带上，保证系统安装器
  能拼出完整信任链。
- `SettingsNative/UpdateCheckViewController.swift`：`installTapped`
  起服务并打开 itms-services 链接；`refresh()` 用
  `LocalInstallServer.isAvailable` 决定「安装」按钮是否存在；
  自动签名链（开关开 + 下载完成 + 有证书 ⇒ 自动签，失败只写状态行）。
- `App/AppConfiguration.swift`：`installServerCertPassword` 常量。

## 尚未实测的点（等证书到位、打包后真机验）

- iOS 系统安装器对本机服务的实际拉取行为（清单 Content-Type、
  是否要求 Range、连接复用习惯）——按业界 OTA 的通行做法实现，
  只能真机证伪。
- NWListener 的 TLS 身份呈现与系统信任校验的配合，尤其是证书链
  是否被完整送出（已显式带链，仍以真机为准）。
