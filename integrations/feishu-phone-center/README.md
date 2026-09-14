# 飞书外呼中心

CellDock 0.4.6 将电话卡接到机主已有的飞书 Codex 机器人。普通来电、短信、通话文字在固定私有群留档；疑似紧急事项 @ 机主。机主在群里 @ 机器人，用自然语言查询、外呼或发短信。

## 使用

- `@机器人 电话状态`
- `@机器人 最近谁联系过我？`
- `@机器人 给张三打电话，问明天下午三点是否方便开会。`
- `@机器人 给指定号码发短信，说我晚十分钟到。`
- `@机器人 挂断当前电话。`

联系人重名或信息不足时会询问。号码、短信正文和目的已明确时直接执行。外呼目的通过 `call.dial.task` 限定在这通电话，保存到该通记录，不改全局接听角色。主动外呼使用 AI 助理致电开场，不播放“本人不方便接听”的来电专用录音。

当前部署的飞书应用仅把真正 @ 到机器人的消息送给桥接。普通群消息免 @ 的本地入口已支持，但是否收到事件仍取决于飞书应用权限；不能仅修改本地开关就声称免 @ 可用。

## 组成与边界

`scripts/feishu_phone_center.py` 用经过认证的本机只读电话 API 获取事件、最近短信和增量通话存档。每秒轮询，通话文字约每 4 秒成批通知；实际延时取决于转写和飞书网络。来电响铃、未接通、通话结束、AI/录音故障也会通知。

结束后使用已登录 Codex 的独立临时会话整理来意、待办、期限。该会话不继承用户配置，禁用 MCP、应用、Shell、联网搜索和多代理。原始短信和通话内容不具备电脑操作权限。整理失败会明确提示，原文照常送达。关键词优先提醒加上 AI 归纳判断只能辅助确定优先级，不能保证识别所有紧急事项。

SQLite 保存游标、通知队列、发送回执、通话增量位置和摘要任务。先落盘再发送；网络失败复用相同飞书幂等键。超过飞书幂等窗口的未知投递结果会进入 `uncertain`，需核对后处理，避免重复发送。首次启用不补发历史；后续重启从持久状态恢复。CellDock 保留最近 2000 个事件，短信及通话 API 各取最近 100 项；长期离线超过这些范围可能无法完整补齐，事件缺口会提醒。录音仍留在本机，不自动上传。

桥接中的 `access.commandChats` 将指定群绑定到唯一真人 open ID；其他成员、机器人和缺失身份的消息在进入 agent 前丢弃。该群的技术调用日志从回复中隐藏。其他群的访问、@ 和显示设置继续沿用原值。

## 安装

前提：同一用户下 CellDock 0.4.6 正在运行；现有 `lark-channel-bridge` 已连接；已登录的 `lark-cli` profile 对应同一机器人；已确认目标私有群和机主身份。

1. 在已有桥接源码中应用 `bridge.patch`，执行 `pnpm typecheck`、相关测试和 `pnpm build`。补丁基于 bridge 0.2.2 / `8468b1c63f0109aeedac28eb6e3d789b22a228f9` 及本机已有的 `silentDeniedChats` 扩展，只包含本功能差异。先 `git apply --check`；不同基线需合并同等改动，不能覆盖既有本地修改。
2. 检查现有桥接没有进行中的任务，然后执行：

   ```bash
   python3 scripts/install_feishu_phone_center.py \
     --profile codex --app-id <现有应用ID> \
     --chat-id <私有群ID> --owner-id <机主openID>
   lark-channel-bridge restart --profile codex
   ```

安装器核验群主与私有群、核对 app ID，备份并增量更新群绑定，建立专用工作区和登录即启动的 LaunchAgent。Mac 需联网，CellDock 和模块需保持可用。没有增加第二个飞书 WebSocket 接收器，也没有复制应用密钥或更换机器人。

本机数据目录：`~/Library/Application Support/CellDock/FeishuPhoneCenter/`。包含 `config.json`（固定目的地和程序路径，不含密钥）、私有队列、工作区、日志及配置备份。不要提交此目录。运行 `python3 scripts/feishu_phone_center.py status` 查看最近轮询、积压、回执和错误。

MCP 新增 `phone_center_status`、`phone_notify_owner`；其他已授权 Codex 工作流也能通过后者把需机主关注的事项放入同一队列。此能力不能从外部短信/来电内容获得调用授权。

停用通知：`launchctl bootout gui/$(id -u)/com.celldock.feishu-phone-center`，同时移走对应 `~/Library/LaunchAgents/com.celldock.feishu-phone-center.plist` 防止下次登录启动。若需撤销命令入口，只删除本群的 `commandChats`、工作区和允许群绑定，再在空闲时重启桥接；不要用旧的完整配置覆盖之后新增的其他设置。

## 验证

```bash
python3 -m unittest discover -s Tests -p 'test_*phone*.py'
# 以下命令会向已配置的群发送清楚标注的测试消息，须有机主授权：
python3 scripts/test_feishu_phone_center_live.py --send-test-messages --output <私有验收目录>
```

2026-09-14 本机验收：12 项 Python 测试、Swift 存档测试、桥接 515 项原测试及 3 项新访问策略测试通过；桥接类型检查/构建、CellDock 完整签名构建通过。6 条模拟短信/来电/实况/结束/事项整理已真实投递到目标群并回读，紧急提醒真实 @ 机主；服务重启后继续轮询且无重复投递。机主亲自在群中 @ 机器人发送“电话状态”，Codex 调用两个状态 MCP 工具后成功回复，飞书界面已确认显示。新外呼任务参数和短信请求 ID 使用模拟执行验证；本次没有向任何真实号码外呼或发送测试短信。
