"""Validate generated configuration without installing packages or accessing hosts."""
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'bootstrap-monitoring.sh'


class MonitoringTests(unittest.TestCase):
    def blocks(self):
        return re.findall(r"<<'PY'\n(.*?)\nPY", SCRIPT.read_text(encoding='utf-8'), re.S)

    def test_embedded_python_compiles(self):
        blocks = self.blocks()
        self.assertGreaterEqual(len(blocks), 7)
        for index, code in enumerate(blocks):
            compile(code, f'embedded-{index}', 'exec')

    def test_generated_cluster_and_gitea_port(self):
        code = next(b for b in self.blocks() if "(p/'docker-compose.yml')" in b)
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p/'generate.py').write_text(code, encoding='utf-8')
            images = {'prometheus':'prom/prometheus@sha256:'+'a'*64,
                      'grafana':'grafana/grafana@sha256:'+'b'*64}
            (p/'images.json').write_text(json.dumps(images))
            for nodes in [[],[{'host':'192.0.2.10','node':'192.0.2.10','user':'cluster'}]]:
                with self.subTest(nodes=nodes):
                    (p/'nodes.json').write_text(json.dumps(nodes))
                    subprocess.run([sys.executable,str(p/'generate.py'),tmp,'0.0.0.0','3001'],check=True)
                    compose=json.loads((p/'docker-compose.yml').read_text())
                    prom=json.loads((p/'prometheus.yml').read_text())
                    dashboard=json.loads((p/'onepage.json').read_text(encoding='utf-8'))
                    self.assertEqual(compose['services']['grafana']['environment']['GF_SERVER_HTTP_PORT'],'3001')
                    self.assertNotIn('GF_SECURITY_ADMIN_PASSWORD',compose['services']['grafana']['environment'])
                    self.assertIn('--web.listen-address=127.0.0.1:9090',compose['services']['prometheus']['command'])
                    self.assertEqual(len(prom['scrape_configs'][0]['static_configs']),len(nodes)+1)
                    self.assertEqual(len(dashboard['panels']),6*(len(nodes)+1))
                    self.assertEqual(len({p['id'] for p in dashboard['panels']}),len(dashboard['panels']))
                    self.assertEqual(set(compose['volumes']),{'grafana-data','prometheus-data'})

    def test_reject_shell_injection_and_loopback(self):
        code = next(b for b in self.blocks() if 'raw, default, work' in b)
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'hosts.py'
            path.write_text(code,encoding='utf-8')
            for hosts in ['root@bad;command','-oProxyCommand=bad','root@127.0.0.1','a@b@c']:
                with self.subTest(hosts=hosts):
                    result=subprocess.run([sys.executable,str(path),hosts,'cluster',tmp],capture_output=True)
                    self.assertNotEqual(result.returncode,0)
