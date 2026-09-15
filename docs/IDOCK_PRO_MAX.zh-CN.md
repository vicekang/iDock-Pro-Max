# iDock Pro Max 0.5.0

基于 `141d0b4`，包含最新的手机网络切换、独立音色与本地开场白、飞书电话中心代码。

## 界面与品牌

- App、菜单栏、安装路径和四种语言中的产品名为 **iDock Pro Max**。
- 使用 macOS 26 的原生 `glassEffect`、玻璃按钮与材质容器；浮动导航、分栏和统一选择态。
- 内容阅读层保持足够对比度，避免大段文字叠在多层玻璃上。遵循系统外观、减少透明度与减少动态效果；macOS 14/15 回退到系统材质。
- 新图标的可重现矢量生成脚本：`scripts/render_idock_icon.swift`。
- 更新页面指向本项目的 GitHub 发布页面，保留 CellDock 开源归属说明。

## 升级连续性

保持 `app.celldock.mac`、原签名证书、Application Support/CellDock、钥匙串及 Codex MCP 配置兼容。已有录音与逐句文字无需迁移。

新安装路径为 `/Applications/iDock Pro Max.app`。网络 helper 版本 16 严格校验新路径、应用标识和同一签名证书；本次改名需要一次系统管理员认证来替换旧 helper。没有扩大网络权限或关闭签名校验。

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

[Apple：Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)

## 验证边界

验证结果见本次随附记录。界面测试与本地语音自检不等于真实蜂窝通话验收；硬件未连接时无法验证来电、通话和蜂窝上网。

### 本机验证（2026-09-15）

- 完整 app 与网络 helper 编译成功；主程序及所有嵌套签名验证成功。
- 4 种语言、1668 个本地化键验证通过。
- Swift/C 完整自检通过：通话解析、短信、网络协议、双向 M4A 保存、通话文字归档、后台电源管理、开场白播放、Codex 会话生命周期、联系人、USB 和 eSIM。
- Python 20 项通过，另完成完整脚本末尾 8 项模块便携策略测试；JS 8/48 kHz 音频重采样与队列测试通过。CLT 本机需要已有模块映射覆盖文件，初始裸 swiftc 的工具链重复模块错误已用该覆盖解决。
- 安装界面已确认产品名称、新图标、短信页和软件更新页。界面自动化服务在部分页面抓取时自身崩溃，应用与 RPC 持续正常，未把工具故障当成应用故障。
- 已有 7 份录音、通话归档及桥接 token 文件的 SHA-256 连续性验证通过（包含 1 份原声录音）。
- Codex 原生语音自检连接成功：8 kHz、172160 个样本，其中 14772 个有声样本。
- 已启用的登录启动项指向新的安装路径。
- 本次未识别到 USB 模组，真实来电、蜂窝上网与锁屏来电未复测。

安装包：`iDock-Pro-Max-0.5.0-114-arm64.zip`。

SHA-256：`3298e168f6b50f256d008dea1aeff4f0b1abe4c942bb54dff6772806d325f7ed`。
