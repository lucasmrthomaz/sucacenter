from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PortainerTests(unittest.TestCase):
    def setUp(self):
        self.stack = (ROOT / 'stacks/portainer.yml').read_text()
        self.step = (ROOT / 'steps/10-portainer.sh').read_text()

    def test_stack_has_safe_swarm_topology(self):
        self.assertIn('portainer/portainer-ce:lts', self.stack)
        self.assertIn('portainer/agent:lts', self.stack)
        self.assertIn('mode: global', self.stack)
        self.assertIn('node.role == manager', self.stack)
        self.assertIn('published: 9443', self.stack)
        self.assertIn('mode: host', self.stack)
        self.assertIn('portainer_data:/data', self.stack)

    def test_internal_ports_are_not_published(self):
        self.assertNotIn('published: 8000', self.stack)
        self.assertNotIn('published: 9000', self.stack)
        self.assertNotIn('published: 9001', self.stack)

    def test_setup_is_guarded_and_idempotent(self):
        self.assertIn('ControlAvailable', self.step)
        self.assertIn('docker stack config', self.step)
        self.assertIn('docker stack deploy', self.step)
        self.assertNotIn('docker stack rm', self.step)
        self.assertIn('Servico inesperado', self.step)

    def test_cli_exposes_explicit_portainer_commands(self):
        cli = (ROOT / 'sucacenter.sh').read_text()
        self.assertIn('portainer setup', cli)
        self.assertIn('portainer validate', cli)
        self.assertIn('portainer status', cli)


if __name__ == '__main__':
    unittest.main()
