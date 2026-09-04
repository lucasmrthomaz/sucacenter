#!/usr/bin/env bash
# Bash 4+, ASCII-only. Python 3 handles safe collection and backups.
set -euo pipefail
umask 077
MODE="${1:---run}"
case "$MODE" in
    --prepare|--validate|--run) ;;
    *) printf 'Usage: bash bootstrap-sucacenter.sh [--prepare|--validate|--run]\n' >&2; exit 2 ;;
esac
command -v python3 >/dev/null || { printf 'ERROR: python3 is required.\n' >&2; exit 1; }
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export SUCACENTER_PACKAGE="$SCRIPT_DIR"
DEST_DIR="$(python3 - <<'PY'
import os
import pathlib
import shutil
import sys
import tempfile

home = pathlib.Path.home().resolve()
package = pathlib.Path(os.environ['SUCACENTER_PACKAGE']).resolve()
raw = pathlib.Path(os.environ.get('SUCACENTER_BOOTSTRAP_DIR', str(home / 'sucacenter-bootstrap'))).expanduser()
if raw.is_symlink():
    sys.exit('ERROR: destination must not be a symlink.')
dest = raw.resolve()
if dest.name != 'sucacenter-bootstrap' or dest == home or dest in home.parents:
    sys.exit('ERROR: destination must be a dedicated directory named sucacenter-bootstrap.')
if dest.exists() and not dest.is_dir():
    sys.exit('ERROR: destination is not a directory.')
source = pathlib.Path(os.environ.get('SUCACENTER_SOURCE_DIR', str(home / 'sucacenter-user'))).expanduser().resolve()
order = ['slurm.yml', 'storage.yml', 'samba.yml', 'gitea.yml', 'healthcheck.yml']
dest.parent.mkdir(parents=True, exist_ok=True)
stage = pathlib.Path(tempfile.mkdtemp(prefix='.sucacenter-stage-', dir=dest.parent))
(stage / 'playbooks').mkdir()
report = ['SucaCenter collection report', 'Source: ' + str(source), '']
found = []
try:
    for name in order:
        candidates = ([source / name] if 'SUCACENTER_SOURCE_DIR' in os.environ
                      else [source / name, package / 'playbooks' / name])
        selected = next((p for p in candidates if p.is_file()), None)
        if selected is None:
            report.append('MISSING: ' + name)
            continue
        if selected.stat().st_size == 0:
            raise ValueError('Empty playbook: ' + str(selected))
        shutil.copy2(selected, stage / 'playbooks' / name)
        found.append(name)
        report.append('FOUND: ' + name + ' <- ' + str(selected))
    candidates = ([pathlib.Path(os.environ['SUCACENTER_INVENTORY']).expanduser()] if 'SUCACENTER_INVENTORY' in os.environ
                  else [home / 'inventory.ini', source / 'inventory.ini', package / 'inventory.ini'])
    inventory = next((p for p in candidates if p.is_file()), None)
    if inventory is None:
        report.append('MISSING: inventory.ini (required before validation or execution)')
    else:
        if inventory.stat().st_size == 0:
            raise ValueError('Empty inventory: ' + str(inventory))
        shutil.copy2(inventory, stage / 'inventory.ini')
        report.append('FOUND: inventory.ini <- ' + str(inventory))
    site = '---\n' + (''.join('- import_playbook: playbooks/' + n + '\n' for n in found) if found else '[]\n')
    (stage / 'site.yml').write_text(site, encoding='ascii')
    (stage / 'missing-playbooks.txt').write_text('\n'.join(report) + '\n', encoding='utf-8')
    shutil.copy2(package / 'bootstrap-sucacenter.sh', stage / 'bootstrap-sucacenter.sh')
    (stage / 'bootstrap-sucacenter.sh').chmod(0o700)
    if (package / 'originals').is_dir():
        shutil.copytree(package / 'originals', stage / 'originals')
    if (package / 'README.md').is_file():
        shutil.copy2(package / 'README.md', stage / 'README.md')
    else:
        (stage / 'README.md').write_text('Run: bash bootstrap-sucacenter.sh --validate\nThen: bash bootstrap-sucacenter.sh --run\nSee missing-playbooks.txt.\n', encoding='ascii')
    backup = None
    if dest.exists():
        backup = pathlib.Path(tempfile.mkdtemp(prefix='sucacenter-bootstrap.backup-', dir=dest.parent))
        # Exact checked destination only. All source copies are already staged.
        dest.rename(backup / 'previous-directory')
        print('Backup: ' + str(backup / 'previous-directory'), file=sys.stderr)
    try:
        stage.rename(dest)
    except Exception:
        if backup is not None:
            (backup / 'previous-directory').rename(dest)
        raise
    print('\n'.join(report), file=sys.stderr)
    print(str(dest))
except Exception as exc:
    print('Staging retained at: ' + str(stage), file=sys.stderr)
    sys.exit('ERROR: ' + str(exc))
PY
)"
printf 'Prepared: %s\n' "$DEST_DIR"
if [[ "$MODE" == --prepare ]]; then exit 0; fi
for dependency in ansible ansible-inventory ansible-playbook ssh; do
    command -v "$dependency" >/dev/null || { printf 'ERROR: missing %s\n' "$dependency" >&2; exit 1; }
done
[[ -s "$DEST_DIR/inventory.ini" ]] || { printf 'ERROR: supply the real inventory.ini, then rerun.\n' >&2; exit 1; }
cd -- "$DEST_DIR"
printf 'Checkpoint: inventory\n'
ansible-inventory -i inventory.ini --list > inventory-resolved.json
python3 - <<'PY'
import json
import pathlib
import sys
data = json.loads(pathlib.Path('inventory-resolved.json').read_text())
def members(group, seen=None):
    seen = set() if seen is None else seen
    if group in seen:
        return set()
    seen.add(group)
    entry = data.get(group, {})
    result = set(entry.get('hosts', []))
    for child in entry.get('children', []):
        result |= members(child, seen)
    return result
hosts = data.get('_meta', {}).get('hostvars', {})
for node, address in {'worker01': '192.168.1.110', 'worker02': '192.168.1.103'}.items():
    if node not in members('workers'):
        sys.exit('ERROR: workers must include ' + node)
    if str(hosts.get(node, {}).get('ansible_host', node)) != address:
        sys.exit('ERROR: set ansible_host=' + address + ' for ' + node + ' in the real inventory.')
if members('controller') != {'worker01'}:
    sys.exit('ERROR: controller must contain worker01 only for these playbooks.')
if not any(pathlib.Path('playbooks').glob('*.yml')):
    sys.exit('ERROR: no playbooks found.')
PY
printf 'Checkpoint: syntax (storage.yml requires ansible.posix)\n'
for playbook in playbooks/*.yml; do
    ansible-playbook -i inventory.ini "$playbook" --syntax-check
done
ansible-playbook -i inventory.ini site.yml --syntax-check
printf 'Checkpoint: SSH and remote Python connectivity\n'
ansible -i inventory.ini all -m ansible.builtin.ping
if [[ "$MODE" == --validate ]]; then
    printf 'Validation completed. No provisioning playbooks were run.\n'
    exit 0
fi
printf 'Checkpoint: provisioning\n'
ansible-playbook -i inventory.ini site.yml --ask-become-pass
printf 'SucaCenter bootstrap completed.\n'
