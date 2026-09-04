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
        with zipfile.ZipFile(ROOT/'dist/sucacenter-1.0.0.zip') as z:
            names = z.namelist()
            self.assertIn('sucacenter/README.md', names)
            self.assertIn('sucacenter/steps/07-swarm.sh', names)
            self.assertNotIn('sucacenter/config/settings.env', names)
            self.assertFalse(any('/.git/' in n or '__pycache__' in n for n in names))
        with tempfile.TemporaryDirectory() as folder:
            result = subprocess.run(['bash', str(ROOT/'dist/bootstrap-sucacenter.sh'), 'help'],
                                    env=dict(os.environ, HOME=folder), text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('SucaCenter 1.0.0', result.stdout)
