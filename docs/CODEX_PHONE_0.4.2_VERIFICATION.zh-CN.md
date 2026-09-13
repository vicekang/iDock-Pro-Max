# CellDock Codex 0.4.2 后台值守验证

日期：2026-09-13；版本：0.4.2-codex，构建 109。

## 现场证据与结论

用户反馈锁屏后可能无法拨入，尚未提供确切发生时间和锁屏方式。检查当晚电源日志未发现系统睡眠记录；现场为接电、开盖状态。现有日志无法把某次失败与锁屏建立因果关系，不能认定唯一根因已找到。

旧版 CellDock 没有声明自动接听期间的后台活动；WKWebView 使用默认 inactive scheduling 策略；接听 Timer 注册在默认运行循环模式。修复这些明确的后台运行缺口：

- 自动接听且模组存在时持有 `ProcessInfo` 活动，防止空闲睡眠和后台节流；退出、关闭自动接听或拔掉模组后释放。
- 通话或语音诊断时使用音频的 latency-critical 活动；未申请屏幕常亮，也未修改 pmset 或锁屏设置。
- WKWebView 使用公开的 `inactiveSchedulingPolicy = .none` 并保留音频渲染窗口。
- 接听轮询采用 common 模式；系统唤醒后重新刷新模组和网络状态。
- 本地私有 availability.json 记录心跳、睡眠/唤醒、模块存在、SIM/注册状态、来电及语音阶段，供下一次失败定位使用。记录不含号码或谈话内容。

## 测试

- 模拟活动句柄与真实 macOS 电源申请测试均通过；实际申请可在 pmset 中看到，停止后消失。测试覆盖重复更新不重复持有、通话升级、关闭/断开后释放、允许屏幕睡眠、心跳和延迟记录、文件权限。
- Python 桥接 5 项测试通过；WebRTC 音频转换、帧长、缓冲和静音测试通过；本地化检查通过。
- 完全无窗口的隔离 WebKit AudioContext 对照测试中，默认策略与 none 均停在 suspended。这不等于锁屏复现，也说明不能仅设置调度策略就删除现有渲染窗口；修复保留窗口。

## 安装版验证

- 从源码编译并安装，嵌套签名及主程序/helper/runtime 固定标识与证书要求验证通过。
- 实际 CellDock 进程的 `PreventUserIdleSystemSleep` 申请已在 pmset 中确认；该进程没有 `PreventUserIdleDisplaySleep` 申请。
- 模组为 SIM ready、LTE packet/voice registered、VoLTE session available，后台模式为 standby。
- 安装版 Codex 原生语音自检成功：167680 个接收样本，其中 13685 个为非静音样本。测试过程中通过界面隐藏 CellDock，结束后恢复窗口；此项不等同于锁屏实测。

## 待验收

- 真实锁屏后拨入及双方语音、录音需要用户配合实测。
- 明确进入系统睡眠、合盖导致睡眠、关机、USB 断开时不能保证接听；本次没有绕过系统睡眠或安全设置。
