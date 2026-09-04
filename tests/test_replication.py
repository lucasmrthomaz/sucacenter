import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('replication', ROOT / 'ansible/files/replication.py')
rep = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rep)


def base_config():
    return {'devices': [], 'folders': [], 'defaults': {'device': {}, 'folder': {'devices': [], 'versioning': {}}}}


class ReplicationTests(unittest.TestCase):
    def test_direction_history_and_idempotence(self):
        peers = [{'id': 'PEER', 'ip': '192.168.1.103', 'name': 'worker02'}]
        for role, kind in [('source', 'sendonly'), ('replica', 'receiveonly')]:
            first = rep.desired_config(base_config(), 'SELF', role, peers, 30)
            self.assertEqual(first, rep.desired_config(first, 'SELF', role, peers, 30))
            folder = first['folders'][0]
            self.assertEqual(folder['type'], kind)
            self.assertFalse(folder['ignoreDelete'])
            if role == 'replica':
                self.assertEqual(folder['versioning']['type'], 'simple')
                self.assertEqual(folder['versioning']['params'], {'keep': '20', 'cleanoutDays': '30'})

    def test_unrelated_configuration_preserved(self):
        current = base_config()
        current['folders'].append({'id': 'personal', 'path': '/keep'})
        current['devices'].append({'deviceID': 'OTHER', 'name': 'keep'})
        before = copy.deepcopy(current)
        result = rep.desired_config(current, 'SELF', 'replica', [{'id': 'PEER', 'ip': '192.168.1.110', 'name': 'worker01'}], 30)
        self.assertEqual(current, before)
        self.assertEqual(result['folders'][0], before['folders'][0])
        self.assertEqual(result['devices'][0], before['devices'][0])

    def test_reject_role_change_and_wrong_disk_path(self):
        peers = [{'id': 'PEER', 'ip': '192.168.1.110', 'name': 'worker01'}]
        cfg = rep.desired_config(base_config(), 'SELF', 'replica', peers, 30)
        with self.assertRaises(ValueError):
            rep.desired_config(cfg, 'SELF', 'source', peers, 30)
        cfg['folders'][0]['path'] = '/mnt/shared'
        with self.assertRaises(ValueError):
            rep.desired_config(cfg, 'SELF', 'replica', peers, 30)

    def test_network_mount_rejected(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(rep, 'REPLICA', Path(folder)), patch.object(rep, 'command', return_value='nfs4'):
            with self.assertRaisesRegex(ValueError, 'local Linux filesystem'):
                rep.guard_path('replica')

    def test_nonempty_unmanaged_destination_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path / 'keep.txt').write_text('user data')
            with patch.object(rep, 'REPLICA', path), patch.object(rep, 'command', side_effect=['ext4', '{"filesystems": []}', '/dev/test ext4 uuid /']):
                with self.assertRaisesRegex(ValueError, 'unmanaged data'):
                    rep.guard_path('replica', path / 'not-managed')

    def test_missing_mount_marker_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            state = path / 'state'
            state.mkdir()
            (state / 'storage.json').write_text(rep.json.dumps({'path': str(path), 'signature': 'disk'}))
            with patch.object(rep, 'REPLICA', path), patch.object(rep, 'command', side_effect=['ext4', '{"filesystems": []}', 'disk']):
                with self.assertRaisesRegex(ValueError, 'Missing .stfolder'):
                    rep.guard_path('replica', state)

    def test_status_never_claims_offline_or_local_drift_as_ready(self):
        class API:
            connected = True
            drift = 0
            deletes = 0
            errors = []
            def call(self, endpoint):
                if endpoint == 'config':
                    return {'folders': [{'id': rep.FOLDER, 'path': '/replica', 'type': 'receiveonly', 'devices': [{'deviceID': 'SELF'}, {'deviceID': 'PEER'}]}]}
                if endpoint == 'system/status': return {'myID': 'SELF'}
                if endpoint == 'system/connections': return {'connections': {'PEER': {'connected': self.connected}}}
                if endpoint.startswith('db/status'): return {'state': 'idle', 'receiveOnlyTotalItems': self.drift}
                if endpoint.startswith('folder/errors'): return {'errors': self.errors}
                return {'completion': 100, 'needDeletes': self.deletes, 'remoteState': 'valid'}
        api = API()
        self.assertTrue(rep.status(api)['ready'])
        api.connected = False
        self.assertFalse(rep.status(api)['ready'])
        api.connected, api.drift = True, 1
        self.assertFalse(rep.status(api)['ready'])
        api.drift, api.deletes = 0, 1
        self.assertFalse(rep.status(api)['ready'])
        api.deletes, api.errors = 0, [{'path': 'unreadable', 'error': 'permission denied'}]
        self.assertFalse(rep.status(api)['ready'])
