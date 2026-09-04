#!/usr/bin/env python3
"""Dedicated SucaCenter Syncthing instance; never edits a personal instance."""
import argparse
import copy
import ipaddress
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

STATE = Path('/var/lib/sucacenter-syncthing')
SOURCE = Path('/srv/sucacenter/shared')
REPLICA = Path('/srv/sucacenter/replica-shared')
FOLDER = 'sucacenter-shared'
GUI_PORT = 8385
SYNC_PORT = 22001
LOCAL_FS = {'ext2', 'ext3', 'ext4', 'xfs', 'btrfs', 'zfs', 'f2fs'}


def command(args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout.strip()


def atomic_write(path, data):
    fd, temporary = tempfile.mkstemp(prefix='.new-', dir=path.parent)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def guard_path(role, state=STATE):
    path = SOURCE if role == 'source' else REPLICA
    if any(p.is_symlink() for p in [path, *path.parents]):
        raise ValueError('Symlink in managed path: ' + str(path))
    if path.exists() and not path.is_dir():
        raise ValueError('Managed path is not a directory: ' + str(path))
    if role == 'source' and not path.is_dir():
        raise ValueError('Source is missing. Configure NFS/storage first; it is never created here.')
    existing = path
    while not existing.exists():
        existing = existing.parent
    fstype = command(['findmnt', '-n', '-o', 'FSTYPE', '-T', str(existing)])
    if fstype not in LOCAL_FS:
        raise ValueError('Requires a local Linux filesystem, found ' + fstype)
    # Reject nested mounts too, including NFS below an otherwise local directory.
    mounts = json.loads(command(['findmnt', '--json', '--list', '-o', 'TARGET,FSTYPE']))
    for mount in mounts.get('filesystems', []):
        target = Path(mount['target'])
        if target != path and path in target.parents:
            raise ValueError('Nested mount inside shared data: ' + str(target))
    managed = state / 'managed.json'
    storage_record = state / 'storage.json'
    signature = command(['findmnt', '-n', '-o', 'SOURCE,FSTYPE,UUID,FSROOT', '-T', str(existing)])
    if storage_record.exists():
        stored = json.loads(storage_record.read_text())
        if stored != {'path': str(path), 'signature': signature}:
            raise ValueError('Storage identity changed; refusing to synchronize a different disk.')
        if not (path / '.stfolder').is_dir():
            raise ValueError('Missing .stfolder marker; restore the mount/marker before restarting.')
    elif (path / '.stfolder').exists():
        raise ValueError('Folder already belongs to another Syncthing configuration.')
    if role == 'replica' and path.exists() and any(path.iterdir()) and not managed.is_file():
        raise ValueError('Replica contains unmanaged data; choose a clean disk directory first.')
    free = shutil.disk_usage(existing).free
    if free < 256 * 1024 * 1024:
        raise ValueError('Less than 256 MiB free on the destination filesystem.')
    return {'path': str(path), 'filesystem': fstype, 'freeBytes': free, 'signature': signature}


def remember_storage(role, state=STATE):
    info = guard_path(role, state)
    path = Path(info['path'])
    if not (state / 'storage.json').exists():
        (path / '.stfolder').mkdir(mode=0o700)
        atomic_write(state / 'storage.json', json.dumps({'path': str(path), 'signature': info['signature']}).encode())


def modern(binary, subcommand):
    return subprocess.run([binary, subcommand, '--help'], capture_output=True).returncode == 0


def initialize(state, ip, gui_port=GUI_PORT, sync_port=SYNC_PORT, binary='syncthing'):
    ipaddress.IPv4Address(ip)
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    marker = state / 'managed.json'
    identity = {'ip': ip, 'guiPort': gui_port, 'syncPort': sync_port}
    if marker.exists():
        if json.loads(marker.read_text()) != identity:
            raise ValueError('Existing replication identity differs; automatic migration refused.')
        if not all((state / n).is_file() for n in ('config.xml', 'cert.pem', 'key.pem')):
            raise ValueError('Incomplete Syncthing state; restore its backup instead of regenerating identity.')
        return False
    if (state / 'config.xml').exists():
        raise ValueError('Unmanaged Syncthing state exists; refusing to replace it.')
    if modern(binary, 'generate'):
        command([binary, 'generate', '--home=' + str(state)])
    else:
        command([binary, '-generate=' + str(state)])
    config_path = state / 'config.xml'
    tree = ET.parse(config_path)
    root = tree.getroot()
    # Remove only newly generated default folder configuration, never its data.
    for folder in root.findall('folder'):
        root.remove(folder)
    options = root.find('options')
    def set_value(parent, tag, value):
        child = parent.find(tag)
        if child is None:
            child = ET.SubElement(parent, tag)
        child.text = str(value)
    for child in options.findall('listenAddress'):
        options.remove(child)
    set_value(options, 'listenAddress', 'tcp://' + ip + ':' + str(sync_port))
    for key in ('globalAnnounceEnabled', 'localAnnounceEnabled', 'relaysEnabled',
                'natEnabled', 'startBrowser', 'crashReportingEnabled'):
        set_value(options, key, 'false')
    set_value(options, 'urAccepted', -1)
    set_value(options, 'autoUpgradeIntervalH', 0)
    set_value(options, 'maxSendKbps', 10240)
    set_value(options, 'maxRecvKbps', 10240)
    set_value(options, 'limitBandwidthInLan', 'true')
    gui = root.find('gui')
    gui.set('enabled', 'true')
    gui.set('tls', 'false')
    set_value(gui, 'address', '127.0.0.1:' + str(gui_port))
    shutil.copy2(config_path, state / 'config.before-sucacenter.xml')
    atomic_write(config_path, ET.tostring(root, encoding='utf-8', xml_declaration=True))
    atomic_write(marker, json.dumps(identity).encode())
    return True


class API:
    def __init__(self, state=STATE):
        gui = ET.parse(state / 'config.xml').getroot().find('gui')
        self.key = gui.findtext('apikey')
        address = gui.findtext('address')
        if not address.startswith('127.0.0.1:') or not self.key:
            raise ValueError('Expected a loopback-only Syncthing API with a generated key.')
        self.base = 'http://' + address + '/rest/'
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def call(self, endpoint, method='GET', payload=None):
        request = urllib.request.Request(self.base + endpoint, method=method,
                    data=json.dumps(payload).encode() if payload is not None else None,
                    headers={'X-API-Key': self.key, 'Content-Type': 'application/json'})
        with self.opener.open(request, timeout=15) as response:
            content = response.read()
            return json.loads(content) if content else None


def desired_config(current, own_id, role, peers, days):
    if role not in ('source', 'replica') or not 1 <= days <= 3650 or not peers:
        raise ValueError('Invalid role, retention or empty peer set.')
    ids = [peer['id'] for peer in peers]
    if len(set(ids)) != len(ids) or own_id in ids:
        raise ValueError('Duplicate device identity or own device used as a peer.')
    result = copy.deepcopy(current)
    for peer in peers:
        ipaddress.IPv4Address(peer['ip'])
        device = next((d for d in result['devices'] if d['deviceID'] == peer['id']), None)
        if device is None:
            device = copy.deepcopy(result['defaults']['device'])
            result['devices'].append(device)
        device.update(deviceID=peer['id'], name=peer['name'],
                      addresses=['tcp://' + peer['ip'] + ':' + str(peer.get('port', SYNC_PORT))],
                      introducer=False, autoAcceptFolders=False, paused=False)
    folder = next((f for f in result['folders'] if f['id'] == FOLDER), None)
    path = str(SOURCE if role == 'source' else REPLICA)
    kind = 'sendonly' if role == 'source' else 'receiveonly'
    if folder is None:
        folder = copy.deepcopy(result['defaults']['folder'])
        result['folders'].append(folder)
    elif folder['path'] != path or folder['type'] != kind:
        raise ValueError('Existing managed folder path/role differs; migration refused.')
    old_peers = {d['deviceID']: d for d in folder.get('devices', [])}
    old_peers.update({i: old_peers.get(i, {'deviceID': i}) for i in [own_id, *ids]})
    if set(old_peers) - {own_id, *ids}:
        raise ValueError('Unexpected folder peers; refusing to silently remove or retain them.')
    folder.update(id=FOLDER, label='SucaCenter Shared', path=path, type=kind,
                  devices=[old_peers[i] for i in sorted(old_peers)], paused=False,
                  fsWatcherEnabled=True, rescanIntervalS=600, ignorePerms=True,
                  minDiskFree={'value': 5, 'unit': '%'}, ignoreDelete=False)
    versioning = copy.deepcopy(folder.get('versioning', {}))
    versioning.update(type='simple' if role == 'replica' else '',
                      params={'keep': '20', 'cleanoutDays': str(days)} if role == 'replica' else versioning.get('params'),
                      cleanupIntervalS=3600, fsPath='', fsType='basic')
    folder['versioning'] = versioning
    return result


def configure(api, state, role, peers, days):
    original = api.call('config')
    own_id = api.call('system/status')['myID']
    updated = desired_config(original, own_id, role, peers, days)
    changed = updated != original
    if changed:
        # API config includes its key; keep backups private and never print it.
        fd, backup = tempfile.mkstemp(prefix='config-backup-', suffix='.json', dir=state)
        with os.fdopen(fd, 'w') as stream:
            json.dump(original, stream)
        api.call('config', 'PUT', updated)
    if api.call('config/restart-required')['requiresRestart']:
        api.call('system/restart', 'POST')
    return {'changed': changed, 'folder': FOLDER, 'role': role, 'retentionDays': days}


def status(api):
    config = api.call('config')
    folder = next((f for f in config['folders'] if f['id'] == FOLDER), None)
    if folder is None:
        raise ValueError('Replication folder has not been configured.')
    own = api.call('system/status')['myID']
    local = api.call('db/status?' + urllib.parse.urlencode({'folder': FOLDER}))
    errors = api.call('folder/errors?' + urllib.parse.urlencode({'folder': FOLDER, 'perpage': 10})).get('errors') or []
    connections = api.call('system/connections')['connections']
    peers = []
    for peer in folder['devices']:
        device = peer['deviceID']
        if device == own:
            continue
        completion = api.call('db/completion?' + urllib.parse.urlencode({'folder': FOLDER, 'device': device}))
        peers.append({'id': device, 'connected': connections.get(device, {}).get('connected', False),
                      'completion': completion.get('completion', 0),
                      'needItems': completion.get('needItems', 0),
                      'needDeletes': completion.get('needDeletes', 0),
                      'remoteState': completion.get('remoteState', 'valid')})
    ready = bool(peers) and not errors and not folder.get('paused', False) and local.get('state') == 'idle'
    ready = ready and not any(local.get(key, 0) for key in ('needTotalItems', 'needBytes', 'pullErrors', 'receiveOnlyTotalItems'))
    ready = ready and all(p['connected'] and p['completion'] == 100 and not p['needItems']
                          and not p['needDeletes'] and p['remoteState'] == 'valid' for p in peers)
    return {'ready': bool(ready), 'folder': FOLDER, 'path': folder['path'], 'type': folder['type'],
            'state': local.get('state'), 'needBytes': local.get('needBytes', 0),
            'needItems': local.get('needTotalItems', 0), 'errors': local.get('pullErrors', 0),
            'folderErrors': errors,
            'localChanges': local.get('receiveOnlyTotalItems', 0), 'peers': peers}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['guard', 'initialize', 'serve', 'identity', 'configure', 'status'])
    parser.add_argument('--role', choices=['source', 'replica'], default='replica')
    parser.add_argument('--ip')
    parser.add_argument('--days', type=int, default=30)
    args = parser.parse_args()
    os.umask(0o077)
    if args.action == 'guard':
        result = guard_path(args.role)
    elif args.action == 'initialize':
        result = {'changed': initialize(STATE, args.ip)}
        remember_storage(args.role)
    elif args.action == 'serve':
        binary = shutil.which('syncthing')
        flags = [binary] + (['serve'] if modern(binary, 'serve') else [])
        os.execv(binary, flags + ['--home=' + str(STATE), '--no-browser', '--no-restart', '--no-upgrade'])
    else:
        api = API()
        if args.action == 'identity':
            result = {'id': api.call('system/status')['myID']}
        elif args.action == 'configure':
            result = configure(api, STATE, args.role, json.load(sys.stdin), args.days)
        else:
            result = status(api)
    print(json.dumps(result))
    return 2 if args.action == 'status' and not result['ready'] else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        # Never include REST bodies or process output that could contain credentials.
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
