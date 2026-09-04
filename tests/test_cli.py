import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class CLITests(unittest.TestCase):
    def invoke(self, *args, home=None):
        env = dict(os.environ, SUCACENTER_ROOT=str(ROOT))
        if home:
            env['HOME'] = str(home)
        return subprocess.run(['bash', str(ROOT / 'sucacenter.sh'), *args],
                              env=env, capture_output=True, text=True)
    def test_help_and_invalid_step(self):
        self.assertEqual(self.invoke('help').returncode, 0)
        with tempfile.TemporaryDirectory() as home:
            self.assertNotEqual(self.invoke('step', 'missing', home=home).returncode, 0)
    def test_preserve_nodes_and_install_twice(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder)
            (home / 'cluster').mkdir()
            nodes = home / 'cluster/nodes'
            nodes.write_text(':\ncustom-worker\n')
            before = nodes.read_bytes()
            for _ in range(2):
                result = self.invoke('step', 'workspace', home=home)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(nodes.read_bytes(), before)
            self.assertTrue((home / 'bin/cluster-decompress').exists())
    def test_build_propagates_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path / 'Cargo.toml').write_text('')
            (path / 'cargo').write_text('#!/bin/sh\nexit 17\n', newline='\n')
            (path / 'cargo').chmod(0o755)
            env = dict(os.environ, SUCACENTER_ROOT=str(ROOT), PATH=str(path) + ':' + os.environ['PATH'])
            result = subprocess.run(['bash', str(ROOT / 'lib/build.sh'), 'test', str(path)], env=env)
            self.assertEqual(result.returncode, 17)
