# Mac / iPhone 自动切换（0.4.3-codex，实验功能）

目标：模块插在运行 CellDock 的 Mac 上时保留电话、短信和数据；拔下插到手机后由模块独立提供网络。首次在 Mac 的「设置 → 通用 → Mac / iPhone」开启，之后无需每次手动切模式。此实现已在一块 Baiwang QDC507 上验证 Mac 自动恢复与独立网络；**iPhone 端仍待实机验收，不能据此承诺所有 iPhone 即插即用。**

## GitHub 调研及采用依据

- [imbbbbb/celldock-for-mac](https://github.com/imbbbbb/celldock-for-mac)，研究快照 `a09cf9f`：提供 MacFull / iPhone-iPad DataOnly 手动模式，完整 USBCFG 白名单、配置快照及读回策略。其记录的固件为 `.007`，本机 `.009` 的支持另由实物检查建立。
- [perry421/CellDock](https://github.com/perry421/CellDock)：USBModeController 手动管理 Mac/iPhone USB 音频模式；其 iOS 远程桥接与本需求的手机直接连接 USB 模块不同。
- [KirisameLonnet/qdc507-macos-serial-driver](https://github.com/KirisameLonnet/qdc507-macos-serial-driver)：USB 网络模式及 macOS ECM / AT 接口的说明。
- [Whale-518/dji-4g-mod-ipad-network](https://github.com/Whale-518/dji-4g-mod-ipad-network) 未采用：示例把最后一个 USBCFG 开关当作 ECM，但该字段实际是音频，不能拿它代替 usbnet 配置。
- Apple [USB-C iPhone 连接支持](https://support.apple.com/zh-cn/105099) 说明 USB 以太网配件支持；不是此模块兼容性认证。

参考项目提供了手动模式切换的依据。自动恢复 Mac 声卡、模块端临时守护和实物验证是本分支新增工作，没有声称参考项目已经实现此自动流程。

## 配置和生命周期

仅对本次验证的 `Baiwang / 2C7C:0125 / QDC507GLEFM21_01.001.01.009` 开放写入。要求既有 ECM（usbnet=1），且当前 USBCFG 精确匹配下列其中之一，未知状态不自动修复：

| 配置 | diag,nmea,AT,modem,net,ADB,audio | 用途 |
|---|---|---|
| Mac 固定模式 | 1,1,1,1,1,1,1 | 原有默认配置 |
| 自动切换的启动配置 | 1,1,1,1,1,1,0 | 手机网络，无 USB 声卡 |

开启时先按模块 IMEI 的 SHA-256 标识保存原配置（不在文件中保存 IMEI 明文），再只改变 audio 开关；必须精确读回后才重启。备份位于 `~/Library/Application Support/CellDock/ModulePortability/`，模块目录 0700、记录 0600。写入或读回响应不明确时不重试写入，只等待重连检查。CLI 的持久操作还带幂等请求 ID。

默认启动实际 USB functions 为 `diag,serial,ecm,ffs`。手机的数据来自模块已有的 LTE、DHCP、DNS 和转发服务，独立于 Mac 或 CellDock。ECM 和 ADB/AT 保留；最后一个开关仅控制音频。

CellDock 连接后先确认没有正在进行的电话、读取启动配置并清理遗留语音路由，再通过 ADB 启动校验过的临时脚本，将当前 USB functions 改成 `diag,serial,ecm,ffs,audio`。重新枚举后沿用现有 QDC507 UAC/D4 通话链路。持久 USBCFG 保持 audio=0，不反复写 flash，也未启用未经验证的原始 PCM 备用桥。

临时脚本用 `setsid` 脱离 ADB 会话；本模块上单用 `nohup` 不能保证 ADB 退出后进程存活。模块断电会自然回到启动配置。若模块保持外接电源，临时脚本检测 VBUS 丢失或持续 3 秒 USB 断开后恢复手机接口；短暂重新枚举不会立即移除声卡。**若经带电集线器极速换主机、VBUS 没有变化且断开不足 3 秒，目前不能保证识别换机；验收时应直接拔下模块，让模块断电后接手机。**

脚本只写 USB sysfs 和 `/run` 临时目录，不修改只读固件分区、开机脚本、APN 或 DNS。原有来电自动接听偏好保持不变。

## 使用与恢复

- 连接 Mac 并运行 CellDock，设置中开启「Mac / iPhone 自动切换」，等待显示「Mac 声卡已自动恢复」。开关针对当前通信模块。
- 手机连接时不需要运行 CellDock，也不需要配代理或手填 IP/APN。手机本身必须支持该 USB 网卡、数据线和供电方式。
- USB-C iPhone 优先直接连接数据线；Lightning iPhone 的转接与供电须按具体型号另行验证。iOS 可能要求先解锁或允许配件连接，这类系统安全行为无法由 Mac 程序消除。
- 恢复原有模式：在同一设置中选择「恢复 Mac 固定模式」。同样备份、读回后重启；不要回退旧版 App 后直接猜测写入配置。

CLI / MCP：

```sh
python3 scripts/codex_phone.py portability.status
python3 scripts/codex_phone.py portability.configure '{"enabled":true}' --request-id YOUR_UNIQUE_ID
python3 scripts/codex_phone.py portability.configure '{"enabled":false}' --request-id ANOTHER_UNIQUE_ID
```

请求响应只表示配置步骤结果。重连后查询 `enabled`、`macAudioReady`、`connection`，并核对通话及网络状态。`iphoneAcceptance` 明确保持 `pending-physical-test`，没有用 Mac 测试冒充 iPhone 测试。

## 验收边界

2026-09-14 已验证：全套项目回归检查；8 项新增固件/脚本行为测试；模块保存 audio=0 后重启，在 CellDock 退出时通过模块 DNS 解析并从 en11 完成 HTTPS 200；开启 CellDock 后恢复 Mac 声卡，SIM、语音/数据注册、VoLTE 正常；原生 AI 语音收到有效音频，蜂窝 HTTPS 200。macOS 默认路由仍是原有 Wi-Fi。

仍须用户配合：实际 iPhone 型号/iOS/线材和供电条件下的插入上网，以及 Mac ↔ iPhone 多轮拔插。按照用户此前选择，没有拨打/接听真实电话或发送测试短信，因此真实通话及短信往返未在本次升级重新验收。

iPhone 验收时临时关闭手机 Wi-Fi 与手机内置 SIM 的蜂窝数据，解锁后接模块，等待约 30–60 秒并打开一个新网页，避免被手机自己的网络掩盖结果。完成后恢复手机原有网络开关；再把模块接回 Mac，核对自动恢复状态。
