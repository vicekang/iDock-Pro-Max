# iDock Pro Max 0.5.1

基于 `141d0b4`，包含最新的手机网络切换、独立音色与本地开场白、飞书电话中心代码。

## 界面与品牌

- App、菜单栏、安装路径和四种语言中的产品名为 **iDock Pro Max**。
- 使用 macOS 26 的原生 `glassEffect`、玻璃按钮与材质容器；原生 AppKit 工具栏、连续分栏和统一选择态。
- 内容阅读层保持足够对比度，避免大段文字叠在多层玻璃上。遵循系统外观、减少透明度与减少动态效果；macOS 14/15 回退到系统材质。
- 新图标的可重现矢量生成脚本：`scripts/render_idock_icon.swift`。
- 更新页面指向本项目的 GitHub 发布页面，保留 CellDock 开源归属说明。

## 升级连续性

保持 `app.celldock.mac`、原签名证书、Application Support/CellDock、钥匙串及 Codex MCP 配置兼容。已有录音与逐句文字无需迁移。

新安装路径为 `/Applications/iDock Pro Max.app`。网络 helper 版本 16 严格校验新路径、应用标识和同一签名证书；从旧 CellDock 名称升级时需要一次系统管理员认证来替换旧 helper；已安装 helper 16 的 0.5.0 用户此次界面升级无需重复安装。没有扩大网络权限或关闭签名校验。

已启用的登录启动项会自动更新到新路径；未启用的登录启动项不会被开启。

## 构建

本机使用 `scripts/build_codex_local.py`、已有本地签名证书及 CLT 模块映射覆盖文件。脚本从 Info.plist 读取唯一版本号，编译应用和网络 helper，保留原已安装版本的 Sparkle 和 VoWiFi Go 运行时，再逐项签名验证。

```sh
python3 scripts/build_codex_local.py --base-app '/Applications/iDock Pro Max.app' --identity CERTIFICATE_SHA1 --swift-overlay /path/to/swift-modulemap-overlay.json --library-validation-exception
```

独立的安装维护入口（不会启动电话、发送短信或改路由）：

```sh
'/Applications/iDock Pro Max.app/Contents/MacOS/iDock Pro Max' --install-network-helper
'/Applications/iDock Pro Max.app/Contents/MacOS/iDock Pro Max' --network-helper-status
```

## 设计参考

本轮先检查实际录音页，再查看开发者官网截图与公开实现说明：

| 参考 | 采用的原则 | 对应改动 |
| --- | --- | --- |
| [CodeEdit](https://www.codeedit.app/) | 工具栏和连续内容面；统一导航密度 | `IDockToolbar.swift`，去除全高图标轨道 |
| [Latest / Max](https://max.codes/latest/) | 直接的列表与详情关系、稳定阅读背景 | 去掉列表和详情的全高圆角容器；该截图是布局参考，不作为 Liquid Glass 示例 |
| [Swift with Majid](https://swiftwithmajid.com/2025/07/16/glassifying-custom-swiftui-views/) | 玻璃响应背景内容，控制层与阅读层分开 | 搜索、列表选择使用简单填色，录音正文不再叠玻璃 |
| [Apple AppKit 新设计](https://developer.apple.com/videos/play/wwdc2025/310/) | 系统工具栏负责玻璃、控件分组与窗口圆角协调 | 真正的 `NSToolbar` / `NSToolbarItemGroup`，保留原生溢出与无障碍行为 |

设置页将 AI 接听独立成分类；后台说明、自定义开场白按需展开。类别使用 42pt 单行布局，内容分组半径 12pt，列表选择半径 8pt，常规卡片去掉阴影。录音页保留声纹与主要播放控件，取消套在联系人、播放器上的大玻璃框。

没有复制参考项目代码或资源。网页标记检测器不适用于此原生 SwiftUI/AppKit 项目，采用源码几何审查与安装版实际界面检查。

## 验证边界

验证结果见本次随附记录。界面测试与本地语音自检不等于真实蜂窝通话验收；硬件未连接时无法验证来电、通话和蜂窝上网。

### 0.5.0 基础验证（2026-09-15）

- 完整 app 与网络 helper 编译成功；主程序及所有嵌套签名验证成功。
- 4 种语言、1668 个本地化键验证通过。
- Swift/C 完整自检通过：通话解析、短信、网络协议、双向 M4A 保存、通话文字归档、后台电源管理、开场白播放、Codex 会话生命周期、联系人、USB 和 eSIM。
- Python 20 项通过，另完成完整脚本末尾 8 项模块便携策略测试；JS 8/48 kHz 音频重采样与队列测试通过。CLT 本机需要已有模块映射覆盖文件，初始裸 swiftc 的工具链重复模块错误已用该覆盖解决。
- 安装界面已确认产品名称、新图标、短信页和软件更新页。界面自动化服务在部分页面抓取时自身崩溃，应用与 RPC 持续正常，未把工具故障当成应用故障。
- 已有 7 份录音、通话归档及桥接 token 文件的 SHA-256 连续性验证通过（包含 1 份原声录音）。
- Codex 原生语音自检连接成功：8 kHz、172160 个样本，其中 14772 个有声样本。
- 已启用的登录启动项指向新的安装路径。
- 管理员认证已完成：已安装的 root helper 与随包 helper 哈希一致，签名身份校验通过；真实 XPC 握手返回 `protocol=12 identity=CellDock Network Helper/16 ready=true`。VoWiFi 运行时文件也与随包版本一致且签名通过。
- 本次未识别到 USB 模组，真实来电、蜂窝上网与锁屏来电未复测。

安装包：`iDock-Pro-Max-0.5.0-114-arm64.zip`。

SHA-256：`3298e168f6b50f256d008dea1aeff4f0b1abe4c942bb54dff6772806d325f7ed`。


### 0.5.1 界面修订验证（2026-09-15，构建 115）

- 编译后安装并实际检查短信、通用设置、深色、缩窄窗口及录音页面；确认取消三块全高圆角面板、原生工具栏显示正常、跨组选择同步、开关标题不再重复。透明窗口底色导致的工具栏发灰已修正。
- 侧栏保留用户首选宽度，缩窄窗口时为正文保留至少 420pt；拖动从当前可见分隔线起点计算，避免首选宽度被限制后拖动迟滞。
- 四种语言各 1675 个键，键集合一致；所有改动页面中的字面量 L10n 键齐全。
- 已有 1 份 M4A、5 份通话归档和桥接 token 共 7 个文件的哈希连续性通过；原生语音后端、自动接听及录音开关保持不变。
- helper 16 / IPC 12 的真实 XPC 握手通过。此次界面迭代没有修改辅助进程信任策略。
- 切换部分设置子页时，界面检查服务 `SkyComputerUseService` 自身出现 EXC_BREAKPOINT；iDock 与 RPC 仍在运行。这些子页未完成视觉自动验收，源码路由及入口已独立审查。
- 本次没有复测真实蜂窝通话；USB 模组当前未连接。

0.5.1 安装包：`iDock-Pro-Max-0.5.1-115-arm64.zip`。SHA-256：`1c5f01b12e0fe5afcba3bd64ea583fa60e84ce5cd7c0c37ce5445f5d740b093d`。
