"""Synthetic scanner regression tests, stdlib only; no repair or network operations."""
from pathlib import Path
import importlib.util
import contextlib
import io
import unittest

spec = importlib.util.spec_from_file_location('release_scan', Path(__file__).resolve().parents[1] / 'release/verify.py')
scan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scan)


class ScannerRules(unittest.TestCase):
    def test_secret_patterns_use_only_fictional_values(self):
        for text in ['sk-' + 'FICTITIOUS0' * 4, 'ghp_' + 'FICTITIOUS0' * 4,
                     '-----BEGIN ' + 'PRIVATE KEY-----']:
            self.assertIsNotNone(scan.SECRET.search(text))

    def test_credential_url(self):
        self.assertIsNotNone(scan.CREDENTIAL_URL.search('https://' + 'fictional-user:fictional-pass' + '@example.invalid/repo.git'))
        self.assertIsNone(scan.CREDENTIAL_URL.search('https://api.deepseek.com'))

    def test_personal_directory(self):
        self.assertIsNotNone(scan.PRIVATE_PATH.search('Z:' + '/Users/fictional-owner/private'))
        self.assertIsNone(scan.PRIVATE_PATH.search('%USERPROFILE%/repair-records'))

    def test_path_traversal(self):
        for name in ['../outside', '/absolute', 'Z:/outside', 'safe/../../outside']:
            self.assertFalse(scan.safe_relative(name))
        self.assertTrue(scan.safe_relative('core/ps/collect.ps1'))

    def test_assignment_detection(self):
        for text in ['api_key=FICTITIOUS_ONLY_1234', '"password": "FICTITIOUS_ONLY_1234"']:
            self.assertIsNotNone(scan.ASSIGNMENT.search(text))


if __name__ == '__main__':
    unittest.main()
