#!/usr/bin/env python3
"""Install notifications and bind one private owner chat to the existing bridge.

Apply integrations/feishu-phone-center/bridge.patch and build that bridge first.
Restart the existing bridge only after checking it has no active agent run.
"""
import argparse
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import time

from feishu_phone_center import DEFAULT_STATE, Feishu, ROOT, Store, Center


def private_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temp = path.with_name(path.name + '.tmp')
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temp.chmod(0o600)
    temp.replace(path)


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--chat-id', required=True)
    parser.add_argument('--owner-id', required=True)
    parser.add_argument('--app-id', required=True)
    parser.add_argument('--profile', default='codex')
    parser.add_argument('--lark-cli', default='/opt/homebrew/bin/lark-cli')
    parser.add_argument('--codex', default='/Applications/ChatGPT.app/Contents/Resources/codex')
    args = parser.parse_args()
    config = {'chatId': args.chat_id, 'ownerId': args.owner_id, 'appId': args.app_id,
              'profile': args.profile, 'larkCli': args.lark_cli, 'codex': args.codex}
    chat = Feishu(config).verify()
    directory = DEFAULT_STATE
    store = Store(directory)
    config_path = directory / 'config.json'
    if config_path.exists():
        existing = json.loads(config_path.read_text())
        if any(existing.get(k) != config[k] for k in ['chatId', 'ownerId', 'appId', 'profile']):
            raise RuntimeError('Existing notification destination differs; inspect before rebinding')
    private_json(config_path, config)
    workspace = directory / 'workspace'
    workspace.mkdir(exist_ok=True, mode=0o700)
    shutil.copy2(ROOT / 'integrations/feishu-phone-center/AGENTS.md', workspace / 'AGENTS.md')
    (workspace / 'INSTALLATION.md').write_text(
        f'CellDock 项目：{ROOT}\n电话 CLI：{ROOT}/scripts/codex_phone.py\n'
        f'通知 CLI：{ROOT}/scripts/feishu_phone_center.py\n'
        'CLI 调用格式：python3 <电话 CLI> <RPC 方法> <JSON 参数> --request-id <稳定 UUID>。\n'
        '敏感正文使用 stdin JSON：python3 <电话 CLI> sms.send - --request-id <稳定 UUID>。\n'
        '通知状态：python3 <通知 CLI> status。\n'
        f'绑定群：{args.chat_id}\n机主：{args.owner_id}\n'
        '身份绑定和通知目的地只在本机配置，不复制任何密钥。\n')
    home = pathlib.Path.home() / '.lark-channel'
    root_config = home / 'config.json'
    mappings = home / 'profiles' / args.profile / 'workspaces.json'
    backup = directory / 'backups' / time.strftime('%Y%m%d-%H%M%S')
    backup.mkdir(parents=True, mode=0o700)
    shutil.copy2(root_config, backup / 'bridge-config.json')
    if mappings.exists():
        shutil.copy2(mappings, backup / 'workspaces.json')
    value = json.loads(root_config.read_text())
    access = value['profiles'][args.profile]['access']
    access.setdefault('commandChats', {})[args.chat_id] = args.owner_id
    if args.chat_id not in access.setdefault('allowedChats', []):
        access['allowedChats'].append(args.chat_id)
    private_json(root_config, value)
    mapping = json.loads(mappings.read_text()) if mappings.exists() else {'chats': {}, 'named': {}}
    mapping.setdefault('chats', {})[args.chat_id] = {'cwd': str(workspace)}
    private_json(mappings, mapping)
    Center(store).poll()  # Establish the no-history-spam baseline before launch.
    logs = directory / 'logs'
    logs.mkdir(exist_ok=True, mode=0o700)
    label = 'com.celldock.feishu-phone-center'
    plist = pathlib.Path.home() / 'Library/LaunchAgents' / (label + '.plist')
    plist.parent.mkdir(parents=True, exist_ok=True)
    plist.write_bytes(plistlib.dumps({'Label': label, 'RunAtLoad': True, 'KeepAlive': True,
        'ThrottleInterval': 30, 'ProcessType': 'Background', 'Umask': 63,
        'ProgramArguments': [sys.executable, str(ROOT / 'scripts/feishu_phone_center.py'), 'run'],
        'WorkingDirectory': str(ROOT),
        'EnvironmentVariables': {'PATH': '/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'},
        'StandardOutPath': str(logs / 'stdout.log'), 'StandardErrorPath': str(logs / 'stderr.log')}))
    plist.chmod(0o600)
    domain = f'gui/{os.getuid()}'
    subprocess.run(['launchctl', 'bootout', domain + '/' + label], capture_output=True)
    subprocess.run(['launchctl', 'bootstrap', domain, str(plist)], check=True)
    print(json.dumps({'installed': True, 'chatName': chat['name'], 'workspace': str(workspace),
                      'launchAgent': label, 'bridgeRestartRequired': True}, ensure_ascii=False))


if __name__ == '__main__': main()
