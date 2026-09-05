"""Identity lifecycle tests. Run on Linux with openssl; no cluster required."""
import base64
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest


@unittest.skipUnless(os.name == 'posix' and shutil.which('openssl'), 'requires Linux/OpenSSL')
class IdentityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        source = Path(__file__).resolve().parents[1] / 'ansible/roles/sccache/files/identity.py'
        shutil.copyfile(source, self.root / 'identity.py')

    def invoke(self, ip='192.168.1.110', check=True):
        return subprocess.run(['python3', str(self.root / 'identity.py'), ip],
                              text=True, capture_output=True, check=check)

    def test_idempotent_secret_permissions_and_ip_renewal(self):
        first = self.invoke()
        self.assertEqual(json.loads(first.stdout), {'changed': True})
        protected = ['secrets.json', 'ca.key', 'scheduler.key']
        original = {p.name: p.read_bytes() for p in self.root.iterdir() if p.is_file()}
        for name in protected:
            self.assertEqual(stat.S_IMODE((self.root / name).stat().st_mode), 0o600)
        secret = json.loads(original['secrets.json'])
        self.assertEqual(len(base64.urlsafe_b64decode(secret['server_key'])), 32)
        self.assertEqual(len(secret['client_token']), 64)
        self.assertNotIn(secret['client_token'], first.stdout + first.stderr)
        self.assertEqual(json.loads(self.invoke().stdout), {'changed': False})
        for name, data in original.items():
            self.assertEqual((self.root / name).read_bytes(), data)
        self.assertEqual(json.loads(self.invoke('192.168.1.111').stdout), {'changed': True})
        for name in ['secrets.json', 'ca.key', 'ca.crt']:
            self.assertEqual((self.root / name).read_bytes(), original[name])
        subprocess.run(['openssl', 'verify', '-CAfile', str(self.root / 'ca.crt'),
                        '-verify_ip', '192.168.1.111', str(self.root / 'scheduler.crt')],
                       check=True, capture_output=True)

    def test_incomplete_ca_fails_without_rotating_key(self):
        self.invoke()
        key = (self.root / 'ca.key').read_bytes()
        (self.root / 'ca.crt').unlink()
        self.assertNotEqual(self.invoke(check=False).returncode, 0)
        self.assertEqual((self.root / 'ca.key').read_bytes(), key)

    def test_invalid_address_creates_no_identity(self):
        self.assertNotEqual(self.invoke('worker01; false', check=False).returncode, 0)
        self.assertFalse((self.root / 'secrets.json').exists())


if __name__ == '__main__':
    unittest.main()
