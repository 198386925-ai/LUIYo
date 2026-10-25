import Foundation

/// Static content for the UIKit settings page (guide + changelog), carried
/// over verbatim from the previous settings implementation.
struct SettingsGuideSection {
    let title: String
    let body: String
}

struct ChangelogEntry {
    let tag: String?
    let text: String
}

struct ChangelogVersion {
    let title: String
    let isCurrent: Bool
    let entries: [ChangelogEntry]
}

enum SettingsContent {
    static let guide: [SettingsGuideSection] = [
        ("关键词批量导入：", "图片文件名使用网页标题中的关键词即可模糊匹配，模糊关键词至少 3 个字，两个字请使用完整标题。"),
        ("双分类补全：", "用一张补全图片同时填充 LiquidUI 与原版微信中还没有图片的项目。"),
        ("自动联动：", "同一图标对应多个内部命名时，上传一次即可在导出时自动生成相关文件。"),
        ("颜色修改：", "可分别设置浅色选中、深色选中和全部图标颜色；不开启时保留默认处理。"),
        ("排除图标：", "补全后不想更换的项目可以点卡片上的删除按钮，该项目不会进入本次 ZIP。"),
        ("导出：", "生成 ZIP 后可改名，再通过 iPhone 系统分享菜单保存或分享。导出的 ZIP 解压后，把全部图片放进「文件」App → 微信 → LiquidUI/Icons 根目录（不带 @3x 的那组图也放这里），再到 LiquidUI 设置 → 全局换图标点「重新扫描图片文件夹」或重启微信。"),
    ].map { SettingsGuideSection(title: $0.0, body: $0.1) }

    static let changelog: [ChangelogVersion] = [
        ChangelogVersion(title: "Version 1.0.8", isCurrent: true, entries: [
            ChangelogEntry(tag: "新增", text: "新增 App 内签名与本机直接安装：在 LUIYo 内用导入的证书给新版本签名并校验，签名后可直接在本机安装，不再跳转其他签名工具。"),
            ChangelogEntry(tag: "新增", text: "新增证书详情查看：点证书可看证书名称、团队 ID、描述文件名称、到期时间与包含的设备 UDID；导入证书支持 zip 压缩包，导出同为 zip。"),
            ChangelogEntry(tag: "新增", text: "新增修改密码：我的账号资料页新增「修改密码」，输入原密码验证后即可设置新密码（至少 8 个字符，需含大写和小写字母各 1 个），修改后当前设备保持登录。"),
            ChangelogEntry(tag: "新增", text: "新增气泡包：底栏新增「气泡包」页，点气泡放图，自动按规则命名，导出 zip 即可上传（导出需授权）。"),
            ChangelogEntry(tag: "新增", text: "新增气泡包英文文件名隐藏开关：工具栏新增「英文文件名」切换，藏起其它气泡旁的英文文件名，导出 zip 不受影响。"),
            ChangelogEntry(tag: "新增", text: "新增气泡包批量导入待分配：批量导入的图不再按文件名自动认，先进待分配区，点图后选左边/右边顺序填空。"),
            ChangelogEntry(tag: "新增", text: "新增气泡包其它气泡待分配：待分配区新增「放其它」按钮，按顺序填下一个空其它气泡（红包/转账/礼物等）。"),
            ChangelogEntry(tag: "优化", text: "优化气泡包工具栏切换：命名、夜间版、倍数改用滑动分段，选中项以滑块标示；说明文字去掉卡片背景，改为纯文字。"),
            ChangelogEntry(tag: "优化", text: "优化气泡包工具栏按钮尺寸：导出按钮与其它按钮统一高度，切换分段高度减小。"),
            ChangelogEntry(tag: "优化", text: "优化气泡包空格子：去掉虚线描边，只留底色和名字。"),
            ChangelogEntry(tag: "优化", text: "优化气泡包其它气泡切换行：分类标题文字改为居中。"),
            ChangelogEntry(tag: "优化", text: "优化气泡包标题栏副标题：改为「点气泡放图 自动按规则命名 导出即可使用」。"),
            ChangelogEntry(tag: "优化", text: "优化气泡包文件名开关：从工具栏移到标题栏，替换深/浅配色按钮。"),
            ChangelogEntry(tag: "优化", text: "优化气泡包工具栏：倍数移到命名后面，改用下拉选择器。"),
            ChangelogEntry(tag: "优化", text: "优化气泡包导入：删除点气泡导入入口，图片只从批量导入进待分配区。"),
            ChangelogEntry(tag: "优化", text: "优化气泡包预览：移除图片大小滑条，预览恢复真实尺寸（像素 ÷ 倍数）。"),
            ChangelogEntry(tag: "优化", text: "优化导出验证：不再联网复核，只看本地授权（启动门与心跳已验证过），有授权直接导出。"),
            ChangelogEntry(tag: "优化", text: "优化气泡包预览：导入图片不再按自己尺寸贴出来，而是像微信里真正用起来那样拉伸铺满整个气泡当皮，字显示在上面。"),
            ChangelogEntry(tag: "优化", text: "优化气泡包工作区：文字与其它分开，各自有批量导图与待分配（上面只放左边/右边，下面只放其它），不再共用一套。"),
            ChangelogEntry(tag: "优化", text: "优化待分配：放进气泡后图不再从待分配消失（只有清空才走），可多选打勾按顺序批量放（勾上显示 1、2、3，第一张进第一个空位）。"),
            ChangelogEntry(tag: "优化", text: "优化待分配提示：删掉‘放左边 → 下一个’这类文字，改成‘已勾选：’后面跟勾选的圈圈（按勾的顺序排）。"),
            ChangelogEntry(tag: "优化", text: "优化待分配选中描边：由 3 磅改细为 2 磅。"),
            ChangelogEntry(tag: "优化", text: "优化待分配已勾选行：一直显示‘上○ 中○ 下○ 单○’（字在圈前），勾选后对应圈变打勾。"),
            ChangelogEntry(tag: "修复", text: "修复气泡包聊天区左右留白边的问题：聊天底贴满手机框，气泡间距不变。"),
            ChangelogEntry(tag: "修复", text: "修复 App 内签名完成后校验误报「签名校验失败」、签名文件被删除的问题。"),
            ChangelogEntry(tag: "修复", text: "修复启动图在打开瞬间闪过紫色的问题。"),
            ChangelogEntry(tag: "修复", text: "修复切换注册 / 登录时白色面板底部闪现直角的问题。"),
            ChangelogEntry(tag: "修复", text: "修复打开 App 时系统启动屏闪紫的问题：启动屏改用与启动图一致的蓝色渐变。"),
            ChangelogEntry(tag: "修复", text: "修复切换登录 / 注册时表单内容短暂空白的问题。"),
            ChangelogEntry(tag: "修复", text: "更新日志查看页的卡片改为毛玻璃效果"),
            ChangelogEntry(tag: "修复", text: "修复气泡包批量导入时认不出的图被塞进文字气泡、导致导出文件名错乱的问题：认不出的图改为单独提示，不再进入导出。"),
            ChangelogEntry(tag: "修复", text: "修复气泡包编辑器界面与网页版不一致的问题：选中药丸与导出按钮恢复蓝色、气泡尾巴与空心虚线边框正常显示、底部输入框补齐、滚动时底栏不再消失。"),
            ChangelogEntry(tag: "修复", text: "修复气泡包编辑器进度条圆角过大导致显示为透镜形的问题：圆角改为条高的一半，恢复正常胶囊条。"),
            ChangelogEntry(tag: "修复", text: "修复气泡包淡色空格子看不见的问题：遮罩、通用卡片底的空位底色加深，在浅底上能看清。"),
            ChangelogEntry(tag: "修复", text: "修复隐藏英文文件名时气泡被拉满的问题：隐藏后气泡保持原来大小和位置。"),
            ChangelogEntry(tag: "修复", text: "修复夜间编辑时输入框仍为白色的问题：输入框与语音/表情/更多跟随夜间视图变深。"),
            ChangelogEntry(tag: "修复", text: "修复放图后气泡被图片原尺寸撑大的问题：气泡大小只按消息内容，图片只拉伸铺满，不再撑大。"),
        ]),
        ChangelogVersion(title: "Version 1.0.7-1", isCurrent: false, entries: [
            ChangelogEntry(tag: "新增", text: "自定义颜色新增「深色模式」分组：可单独开关深色图标反转，并自定义深色颜色。"),
            ChangelogEntry(tag: "优化", text: "界面与干活部分全面改为原生实现（UIKit 界面），滑动与切换更流畅。"),
            ChangelogEntry(tag: "优化", text: "液态玻璃卡片统一旧版效果：圆角加大、去掉阴影、卡片间距收紧。"),
            ChangelogEntry(tag: "优化", text: "全局字号按字号表精细调整；设置页卡片标题、副标题改为同行显示并居中；首页分类切换改为滑动分段效果；精简更新日志。"),
            ChangelogEntry(tag: "优化", text: "首页搜索只匹配图标标题；「双分类补全」支持按搜索过滤。"),
            ChangelogEntry(tag: "优化", text: "设置页自定义字体改为入口，点开再选导入或恢复；「跟随系统」改名为「系统」。"),
            ChangelogEntry(tag: "优化", text: "自定义字体改为独立页面：内置多套字体，英文与中文字体可分开选择，首页、规则页、设置页可分别使用不同字体；设置页五个卡片换上新图标。"),
            ChangelogEntry(tag: "修复", text: "修复深色模式图标无条件反转、设置页标题颜色不跟随深色模式的问题。"),
            ChangelogEntry(tag: "修复", text: "修复启动闪退，以及首页工具按钮文字被玻璃盖住、顶部搜索框被压扁的问题。"),
            ChangelogEntry(tag: "修复", text: "修复设置页折叠卡展开收起时内容重叠、收起有残留的问题。"),
            ChangelogEntry(tag: "修复", text: "修复切换底栏搜索不立即生效、隐藏搜索框和状态行时首页留空白的问题。"),
        ]),
        ChangelogVersion(title: "Version 1.0.7", isCurrent: false, entries: [
            ChangelogEntry(tag: "优化", text: "启动授权秒进：已登录时直接进入界面，后台静默验证，不再等待转圈。"),
            ChangelogEntry(tag: "优化", text: "底栏切换增加柔和渐入动效，页面过渡更顺滑。"),
            ChangelogEntry(tag: "优化", text: "自定义颜色页开关改为 iPhone 系统样式。"),
            ChangelogEntry(tag: "修复", text: "修复主题折叠时开关按钮卡顿残留的问题。"),
            ChangelogEntry(tag: "修复", text: "修复首页/规则/设置切换时闪过旧页面残影的问题。"),
            ChangelogEntry(tag: "修复", text: "修复设置主题中开关按钮的显示残留，改用 iOS 风格开关。"),
        ]),
        ChangelogVersion(title: "Version 1.0.6", isCurrent: false, entries: [
            ChangelogEntry(tag: "新增", text: "支持图标上传、关键词批量导入、双分类补全与 ZIP 导出。"),
            ChangelogEntry(tag: "优化", text: "首页、规则与设置采用系统原生玻璃，低版本自动使用原生磨砂；缩小工具栏文字与规则条目间距。"),
            ChangelogEntry(tag: "优化", text: "原版微信与 LiquidUI 分类及导入入口互换，默认显示原版微信；统一反馈与客服联系入口图标。"),
            ChangelogEntry(tag: "优化", text: "移除分类描边、规则分割线及多余阴影；卡片颜色仅作用于授权上方的品牌卡，统一开关样式。"),
            ChangelogEntry(tag: "修复", text: "修复导入图片删除、补全导出、主题字体保存及底栏搜索布局切换。"),
            ChangelogEntry(tag: "修复", text: "优化底栏切换响应，恢复悬浮底栏与首页安全区，保持设置展开状态。"),
            ChangelogEntry(tag: "修复", text: "插件信息与更新日志支持定位展开，再次点击收起。"),
        ]),
        ChangelogVersion(title: "Version 1.0.5", isCurrent: false, entries: [
            ChangelogEntry(tag: "优化", text: "修复已知问题。"),
            ChangelogEntry(tag: nil, text: "该版本为首发测试。"),
        ]),
        ChangelogVersion(title: "Version 1.0.4", isCurrent: false, entries: [
            ChangelogEntry(tag: "新增", text: "主题支持工具栏卡片透明度、滚动缩小底栏及自定义背景图片；设置自动保存。"),
            ChangelogEntry(tag: "新增", text: "底栏搜索改为关闭、合并、分开三段切换，保留已保存的搜索布局；关闭后恢复顶部搜索框。"),
            ChangelogEntry(tag: "优化", text: "相同或相近用途的图标合并为一个上传入口，共用图标归原版微信；LiquidUI 分类保留专属入口，导出保留全部对应文件名。"),
            ChangelogEntry(tag: "优化", text: "首页上传项每排两列，左图右标题；LiquidUI 与原版微信的导入项和规则分组标题统一缩小；更新规则按大标题合并展示。"),
            ChangelogEntry(tag: "优化", text: "导出 ZIP 改名使用系统原生弹窗。"),
            ChangelogEntry(tag: "优化", text: "补全图片和自定义颜色入口略微加粗描边，增加柔和淡色底。"),
            ChangelogEntry(tag: "优化", text: "首页工具卡片改用纯色，其他卡片保持原生材质。"),
            ChangelogEntry(tag: "优化", text: "清空固定蓝色、白色文字；导出 ZIP 固定绿色、白色文字。"),
            ChangelogEntry(tag: "优化", text: "首页分类和设置切换同步配色：未选中底色跟随卡片颜色，选中底色跟随按钮颜色。"),
            ChangelogEntry(tag: "修复", text: "合并和分开底栏搜索均可点击，打开原生全屏搜索页，自动弹出键盘，关闭后返回原页面。"),
            ChangelogEntry(tag: "修复", text: "深色液态玻璃下六个按钮不明显，按钮保持独立纯色并自动适配文字颜色。"),
            ChangelogEntry(tag: "修复", text: "原生底栏文字跟随导入字体，恢复默认和重新打开也同步生效。"),
            ChangelogEntry(tag: "修复", text: "分开搜索改用系统原生独立搜索标签，底栏与搜索统一对齐、尺寸及安全区位置。"),
        ]),
        ChangelogVersion(title: "Version 1.0.3", isCurrent: false, entries: [
            ChangelogEntry(tag: "新增", text: "主题增加按钮颜色，首页按钮与分类底色同步；浅色、深色分别保存。"),
            ChangelogEntry(tag: "新增", text: "跟随系统、浅色与深色外观；背景颜色分别保存并随外观切换。"),
            ChangelogEntry(tag: "优化", text: "搜索框位于反馈问题下方，随材质切换为液态玻璃或原生磨砂。"),
            ChangelogEntry(tag: "优化", text: "首页六个操作按钮保持纯色，其他卡片保留原有材质。"),
            ChangelogEntry(tag: "优化", text: "分类未选中底色使用按钮颜色，增加透明度以呈现柔和层次。"),
            ChangelogEntry(tag: "优化", text: "分类、材质与外观使用紧凑原生分段控件；缩短设置卡片。"),
            ChangelogEntry(tag: "优化", text: "移除自定义卡片描边，鸣谢仅在设置页随内容排布。"),
            ChangelogEntry(tag: "修复", text: "展开动画结束时的高度跳动和重复点击状态。"),
        ]),
        ChangelogVersion(title: "Version 1.0.2", isCurrent: false, entries: [
            ChangelogEntry(tag: "新增", text: "卡片液态效果开关；关闭后切换为 UIKit 原生磨砂效果。"),
            ChangelogEntry(tag: "新增", text: "主题内自定义字体，可导入 TTF、OTF、WOFF、WOFF2 文件并持久保存。"),
            ChangelogEntry(tag: "新增", text: "卡片材质、液态玻璃、原生磨砂两种模式直接切换/低于26+不生效液态玻璃。"),
            ChangelogEntry(tag: "新增", text: "主题增加卡片颜色，可修改纯色卡片颜色"),
            ChangelogEntry(tag: "优化", text: "规则页移除图片导入入口，仅显示规则名称与图标规则名。"),
            ChangelogEntry(tag: "优化", text: "首页采用新的双列卡片UI，上传区工具区与顶部信息重新布局。"),
            ChangelogEntry(tag: "优化", text: "设置页入口卡片进一步压缩高度与文字尺寸。"),
            ChangelogEntry(tag: "优化", text: "首页白色工具控件、搜索框、颜色展开项、清空按钮、分类未选中项和上传框统一接入 UIKit 原生玻璃/磨砂材质。"),
            ChangelogEntry(tag: "优化", text: "材质切换与首页分类分段切换改为参考图的胶囊式，选中项使用内嵌白色圆角块。"),
            ChangelogEntry(tag: "优化", text: "首页按钮、搜索框、颜色入口与导出操作统一为分类栏同类圆润胶囊轮廓。"),
            ChangelogEntry(tag: "优化", text: "纯色模式下首页操作框统一为同一中性底色，补全图片、自定义颜色、清空等入口保持清晰可见。"),
            ChangelogEntry(tag: "修复", text: "设置页使用说明与更新日志改为原位下拉拉伸卡片。"),
            ChangelogEntry(tag: "修复", text: "规则页顶部安全区与状态栏重叠问题。"),
            ChangelogEntry(tag: "修复", text: "首页、规则、设置三页卡片视觉统一，首页工具卡不再使用单独的透明样式。"),
            ChangelogEntry(tag: "修复", text: "使用说明、更新日志与主题卡片收起响应延迟，收起动画改为快速响应。"),
            ChangelogEntry(tag: "修复", text: "纯色模式默认不显示卡片描边；只有主动开启卡片描边后才显示所选描边颜色。"),
            ChangelogEntry(tag: "修复", text: "背景颜色现在同步到 UIKit 根视图，修改后立即生效并保存。"),
            ChangelogEntry(tag: "修复", text: "首页双分类切换中间露出的白色材质块；分类容器不再重复叠加玻璃。"),
            ChangelogEntry(tag: "修复", text: "液态玻璃与原生磨砂在刷新、筛选和重绘时原生材质层重新绑定导致的跳动。"),
        ]),
        ChangelogVersion(title: "Version 1.0.1", isCurrent: false, entries: [
            ChangelogEntry(tag: "新增", text: "全局换图标规则页，可按规则名称与图标规则名查找。"),
            ChangelogEntry(tag: "新增", text: "关键词批量导入、双分类补全、同名项目自动联动与 ZIP 自定义名称分享。"),
            ChangelogEntry(tag: "新增", text: "浅色选中、深色选中及全部图标颜色自定义。"),
            ChangelogEntry(tag: "优化", text: "设置页的使用说明与更新日志改为原位下拉拉伸，不再弹出独立页面。"),
            ChangelogEntry(tag: "优化", text: "iOS 26+ 使用 UIKit 系统原生 Liquid Glass；不使用 CSS 自绘玻璃。"),
            ChangelogEntry(tag: "优化", text: "iOS 25 及以下自动回退 UIKit 原生 systemMaterial 磨砂。"),
            ChangelogEntry(tag: "优化", text: "规则页移除图片导入入口，只保留规则名称与图标规则名。"),
            ChangelogEntry(tag: "修复", text: "规则页安全区，避免标题与状态栏重叠。"),
        ]),
        ChangelogVersion(title: "Version 1.0.0", isCurrent: false, entries: [
            ChangelogEntry(tag: "新增", text: "优优 LUI 图标补全基础功能。"),
            ChangelogEntry(tag: "新增", text: "LiquidUI / 原版微信图标上传、补全与 ZIP 导出。"),
        ]),
    ]
}
