import importlib.util
import pathlib
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('phone', pathlib.Path(__file__).resolve().parents[1] / 'scripts/codex_phone.py')
phone = importlib.util.module_from_spec(spec)
spec.loader.exec_module(phone)


class BridgeClientTests(unittest.TestCase):
    def test_mcp_initialization_and_tools(self):
        self.assertEqual(phone.mcp_response({'method': 'initialize'})['protocolVersion'], '2024-11-05')
        names = [item['name'] for item in phone.mcp_response({'method': 'tools/list'})['tools']]
        self.assertEqual(len(names), len(set(names)))
        self.assertIn('phone_dial', names)

    def test_sms_idempotency_preserved(self):
        with patch.object(phone, 'rpc', return_value={'ok': True}) as rpc:
            phone.call_tool('phone_sms_send', {'number': '+12025550100', 'body': 'test', 'request_id': 'unique-id'})
            rpc.assert_called_once_with('sms.send', {'number': '+12025550100', 'body': 'test'}, 'unique-id')

    def test_outbound_task_and_request_id_are_scoped_to_dial(self):
        with patch.object(phone, 'rpc', return_value={'ok': True}) as rpc:
            phone.call_tool('phone_dial', {'number': '+12025550100', 'ai': True,
                                         'task': 'Ask whether tomorrow at 3 pm works.', 'request_id': 'one-call'})
            rpc.assert_called_once_with('call.dial', {'number': '+12025550100', 'ai': True,
                                         'task': 'Ask whether tomorrow at 3 pm works.'}, 'one-call')

    def test_uncertain_delivery_remains_error(self):
        with patch.object(phone, 'rpc', return_value={'ok': False, 'deliveryUncertain': True}):
            result = phone.mcp_response({'method': 'tools/call', 'params': {'name': 'phone_sms_send', 'arguments': {'number': '+12025550100', 'body': 'test', 'request_id': 'id'}}})
            self.assertTrue(result['isError'])

    def test_fetch_rejects_non_http_and_embedded_credentials(self):
        for url in ['file:///etc/passwd', 'https://user:pass@example.com', 'gopher://example.com']:
            with self.assertRaises(ValueError):
                phone.cellular_fetch(url)

    def test_fetch_requires_actual_cellular_interface(self):
        with patch.object(phone, 'rpc', return_value={'ok': True, 'result': {'network': {'active': True, 'interface': 'en10; whoami'}}}):
            with self.assertRaises(ValueError):
                phone.cellular_fetch('https://example.com')


if __name__ == '__main__':
    unittest.main()
