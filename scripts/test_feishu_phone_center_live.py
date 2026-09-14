#!/usr/bin/env python3
"""Send explicitly labeled synthetic phone events to the configured owner chat.

Never dials or sends SMS. Requires --send-test-messages as a deliberate opt-in.
Uses a separate test ledger; the production notification cursor is untouched.
"""
import argparse
import json
import pathlib
import time

from feishu_phone_center import Center, Store, Feishu, DEFAULT_STATE, load_config, deliver_one, summary_one


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--send-test-messages', action='store_true', required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    config = load_config(DEFAULT_STATE)
    sender = Feishu(config)
    sender.verify()
    store = Store(args.output / 'ledger')
    now = time.time()
    call = {'callID': 'synthetic-acceptance-' + str(int(now)), 'number': '模拟来电（非真实号码）',
            'direction': 'incoming', 'startedAt': now, 'endedAt': now + 12,
            'transcript': [
                {'role': 'assistant', 'text': '【测试】我是机主的 AI 电话助理，请问有什么事？'},
                {'role': 'user', 'text': '【测试】紧急演练：请在今天五点前确认会议安排。'}]}
    sms = {'id': 'synthetic-sms-' + str(int(now)), 'peer': '模拟短信（非真实号码）', 'outgoing': False,
           'timestamp': now, 'body': '【测试】明天下午三点开会，请有空确认。'}
    payload = {'status': {'lastEvent': 0, 'call': {'phase': 'idle'}}, 'events': [],
               'sms.list': [sms], 'calls.list': [call], 'calls.get': call}
    def read(method, params=None):
        return payload[method]
    with store.transaction():
        store.set('baseline', now - 1)
        store.set('cursor', 0)
    center = Center(store, read, prefix='【外呼中心 · 模拟测试】\n')
    center.poll()
    count = store.db.execute('SELECT count(*) FROM outbox').fetchone()[0]
    Center(store, read).poll()
    assert store.db.execute('SELECT count(*) FROM outbox').fetchone()[0] == count
    while summary_one(store, config):
        pass
    with store.transaction():
        store.db.execute("UPDATE outbox SET body='【外呼中心 · 模拟测试】' || char(10) || body WHERE body NOT LIKE '【外呼中心 · 模拟测试】%'")
    deadline = time.time() + 100
    while time.time() < deadline:
        deliver_one(store, sender)
        if store.db.execute("SELECT count(*) FROM outbox WHERE state='pending'").fetchone()[0] == 0:
            break
        time.sleep(0.5)
    rows = [dict(row) for row in store.db.execute('SELECT key,state,message_id,urgent,error FROM outbox ORDER BY created,key')]
    result = {'noRealCallOrSMS': True, 'replayDeduplicated': True, 'notifications': rows, 'status': store.status()}
    args.output.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = args.output / 'result.json'
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    path.chmod(0o600)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if not all(row['state'] == 'sent' for row in rows):
        raise SystemExit(1)


if __name__ == '__main__': main()
