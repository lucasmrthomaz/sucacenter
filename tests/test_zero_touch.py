from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ZeroTouchTests(unittest.TestCase):
    def test_local_state_is_ignored(self):
        for path in (
            "ansible/inventory.local.ini",
            "config/config.local.yml",
            "secrets/vars.yml",
            "backups/example.tar.gz",
        ):
            result = subprocess.run(
                ["git", "check-ignore", "-q", path], cwd=ROOT, check=False
            )
            self.assertEqual(result.returncode, 0, path)

    def test_public_inventory_contains_no_lab_addresses(self):
        inventory = (ROOT / "ansible/inventory.example.ini").read_text()
        self.assertIn("ansible_connection=local", inventory)
        self.assertNotIn("192.168.", inventory)

    def test_operational_commands_are_available(self):
        command = (ROOT / "tools/suca").read_text()
        for name in ("status)", "update)", "backup)", "restore)"):
            self.assertIn(name, command)


if __name__ == "__main__":
    unittest.main()
