import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'ansible/bootstrap-sucacenter.sh').read_text(encoding='ascii')
BLOCKS = [part.split('\nPY\n')[0] for part in SOURCE.split("<<'PY'\n")[1:]]


class ServicesTests(unittest.TestCase):
    def test_collect_rerun_and_backup(self):
        with tempfile.TemporaryDirectory() as folder:
            dest = Path(folder) / 'sucacenter-bootstrap'
            env = dict(os.environ, SUCACENTER_PACKAGE=str(ROOT / 'ansible'),
                       SUCACENTER_SOURCE_DIR=str(ROOT / 'ansible/playbooks'),
                       SUCACENTER_INVENTORY=str(ROOT / 'ansible/inventory.ini'),
                       SUCACENTER_BOOTSTRAP_DIR=str(dest))
            for iteration in range(2):
                result = subprocess.run([sys.executable, '-c', BLOCKS[0]], env=env,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn('MISSING:', result.stderr)
                self.assertEqual((dest / 'site.yml').read_text(), (ROOT / 'ansible/site.yml').read_text())
                self.assertEqual((dest / 'inventory.ini').read_bytes(), (ROOT / 'ansible/inventory.ini').read_bytes())
                self.assertTrue((dest / 'originals/gitea.yml').is_file())
                env['SUCACENTER_PACKAGE'] = str(dest)
            self.assertEqual(len(list(Path(folder).glob('sucacenter-bootstrap.backup-*'))), 1)

    def test_inventory_guard(self):
        data = {'workers': {'hosts': ['worker01', 'worker02']},
                'controller': {'hosts': ['worker01']},
                '_meta': {'hostvars': {'worker01': {'ansible_host': '192.168.1.110'},
                                      'worker02': {'ansible_host': '192.168.1.103'}}}}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path / 'playbooks').mkdir()
            (path / 'playbooks/slurm.yml').write_text('---\n[]\n')
            for valid in (True, False):
                if not valid:
                    data['_meta']['hostvars']['worker01']['ansible_host'] = '192.168.1.999'
                (path / 'inventory-resolved.json').write_text(json.dumps(data))
                result = subprocess.run([sys.executable, '-c', BLOCKS[1]], cwd=path,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, valid, result.stderr)

    def test_gitea_reuses_docker_and_original_is_retained(self):
        merged = (ROOT / 'ansible/playbooks/gitea.yml').read_text(encoding='utf-8')
        original = (ROOT / 'ansible/originals/gitea.yml').read_text(encoding='utf-8')
        self.assertNotIn('ansible.builtin.apt:', merged)
        self.assertIn('docker compose version', merged)
        self.assertIn('docker.io', original)

    def test_no_install_cannot_run_services(self):
        with tempfile.TemporaryDirectory() as folder:
            result = subprocess.run(['bash', str(ROOT / 'sucacenter.sh'), 'services', 'run', '--no-install'],
                                    env=dict(os.environ, HOME=folder), capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('--no-install', result.stderr)
