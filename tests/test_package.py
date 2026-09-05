import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile
ROOT = Path(__file__).resolve().parents[1]
class PackageTests(unittest.TestCase):
    def test_standalone_help_and_archive_contents(self):
        subprocess.run([os.sys.executable, str(ROOT/'tools/package.py')], check=True, capture_output=True)
        version = (ROOT/'VERSION').read_text().strip()
        with zipfile.ZipFile(ROOT/f'dist/sucacenter-{version}.zip') as z:
            names = z.namelist()
            self.assertIn('sucacenter/README.md', names)
            self.assertIn('sucacenter/bootstrap-monitoring.sh', names)
            self.assertIn('sucacenter/docs/monitoramento.md', names)
            self.assertIn('sucacenter/steps/07-swarm.sh', names)
            self.assertIn('sucacenter/ansible/inventory.ini', names)
            self.assertIn('sucacenter/ansible/playbooks/healthcheck.yml', names)
            self.assertIn('sucacenter/steps/08-services.sh', names)
            self.assertIn('sucacenter/ansible/files/replication.py', names)
            self.assertIn('sucacenter/ansible/replication.yml', names)
            self.assertNotIn('sucacenter/config/settings.env', names)
            self.assertFalse(any('/.git/' in n or '__pycache__' in n for n in names))
        with tempfile.TemporaryDirectory() as folder:
            result = subprocess.run(['bash', str(ROOT/'dist/bootstrap-sucacenter.sh'), 'help'],
                                    env=dict(os.environ, HOME=folder), text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('SucaCenter ' + version, result.stdout)
