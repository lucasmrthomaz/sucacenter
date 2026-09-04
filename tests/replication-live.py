"""Optional isolated Linux test with two real Syncthing processes; no SSH/systemd."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('replication', ROOT / 'ansible/files/replication.py')
rep = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rep)


def wait_for(predicate, label, seconds=60):
    end = time.monotonic() + seconds
    last = ''
    while time.monotonic() < end:
        try:
            if predicate(): return
        except Exception as error:
            last = str(error)
        time.sleep(0.5)
    raise AssertionError('Timed out: ' + label + ' ' + last)


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def main():
    if sys.platform != 'linux':
        raise RuntimeError('Run this isolated live test on Linux.')
    binary = sys.argv[1]
    # /tmp may be tmpfs; exercise the actual local-disk guard on /var/tmp.
    lab = Path(tempfile.mkdtemp(prefix='sucacenter-live-', dir='/var/tmp'))
    rep.SOURCE = lab / 'source'
    rep.REPLICA = lab / 'replica'
    rep.SOURCE.mkdir()
    rep.REPLICA.mkdir()
    states = [lab / 'source-state', lab / 'replica-state']
    ports = [free_port() for _ in range(4)]
    assert len(set(ports)) == 4
    processes, logs, apis = [], [], []
    try:
        for i, state in enumerate(states):
            assert rep.initialize(state, '127.0.0.1', ports[i], ports[i + 2], binary)
            rep.remember_storage('source' if i == 0 else 'replica', state)
            assert not rep.initialize(state, '127.0.0.1', ports[i], ports[i + 2], binary)
            log = (lab / ('node-' + str(i) + '.log')).open('w')
            logs.append(log)
            processes.append(subprocess.Popen([binary, 'serve', '--home=' + str(state), '--no-browser', '--no-restart', '--no-upgrade'],
                             stdout=log, stderr=subprocess.STDOUT, start_new_session=True))
            api = rep.API(state)
            wait_for(lambda: api.call('system/status'), 'API ready')
            apis.append(api)
        ids = [api.call('system/status')['myID'] for api in apis]
        for i, api in enumerate(apis):
            peer = [{'id': ids[1-i], 'ip': '127.0.0.1', 'port': ports[3-i], 'name': 'peer'}]
            role = 'source' if i == 0 else 'replica'
            assert rep.configure(api, states[i], role, peer, 30)['changed']
            # Let the daemon finish config normalization before testing a rerun.
            time.sleep(1)
            current = api.call('config')
            expected = rep.desired_config(current, ids[i], role, peer, 30)
            if current != expected:
                print('Config differences:', [key for key in current if current[key] != expected.get(key)])
                for actual, wanted in zip(current['folders'], expected['folders']):
                    print('Folder differences:', {key: [actual.get(key), wanted.get(key)] for key in wanted if actual.get(key) != wanted.get(key)})
            assert not rep.configure(api, states[i], role, peer, 30)['changed']
        original = rep.SOURCE / 'test-file.txt'
        received = rep.REPLICA / 'test-file.txt'
        original.write_text('first-version')
        apis[0].call('db/scan?folder=' + rep.FOLDER, 'POST')
        wait_for(lambda: received.read_text() == 'first-version', 'initial replica')
        original.write_text('second-version-with-more-data')
        apis[0].call('db/scan?folder=' + rep.FOLDER, 'POST')
        wait_for(lambda: received.read_text() == 'second-version-with-more-data', 'update replica')
        versions = rep.REPLICA / '.stversions'
        wait_for(lambda: any(p.read_text() == 'first-version' for p in versions.rglob('*.txt')), 'old version archived')
        original.unlink()  # Only the unique fixture created above.
        apis[0].call('db/scan?folder=' + rep.FOLDER, 'POST')
        wait_for(lambda: not received.exists(), 'delete propagation')
        wait_for(lambda: any(p.read_text() == 'second-version-with-more-data' for p in versions.rglob('*.txt')), 'deleted version archived')
        wait_for(lambda: all(rep.status(api)['ready'] for api in apis), 'reported ready')
        received.write_text('local-drift-must-not-propagate')
        apis[1].call('db/scan?folder=' + rep.FOLDER, 'POST')
        wait_for(lambda: rep.status(apis[1])['localChanges'] > 0, 'receive-only local changes')
        assert not original.exists()
        assert not rep.status(apis[1])['ready']
        print('PASS: real two-node replication, reconfiguration idempotence, overwrite history, deletion history, receive-only drift detection.')
    finally:
        for process in processes:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=20)
        for log in logs:
            log.close()
        print('Isolated test evidence: ' + str(lab))


if __name__ == '__main__':
    main()
