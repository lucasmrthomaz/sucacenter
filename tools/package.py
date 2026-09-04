"""Gera ZIP e instalador autocontido do código, sem configurações privadas."""
import base64
import hashlib
import gzip
import io
from pathlib import Path
import tarfile
import zipfile
root = Path(__file__).resolve().parents[1]
paths = []
for name in ['sucacenter.sh', 'README.md', 'VERSION', 'CHANGELOG.md', '.gitignore',
             '.gitattributes', '.github', 'config', 'lib', 'commands', 'steps', 'tests', 'docs', 'tools']:
    item = root / name
    for p in sorted(item.rglob('*')) if item.is_dir() else [item]:
        if not p.is_file() or p.is_symlink() or '__pycache__' in p.parts or p.suffix == '.pyc':
            continue
        if p.parent == root / 'config' and '.example' not in p.name:
            continue
        paths.append(p)
paths.sort()
out = root / 'dist'
out.mkdir(exist_ok=True)
version = (root / 'VERSION').read_text().strip()
buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode='w') as tar:
    for p in paths:
        data = p.read_bytes().replace(b'\r\n', b'\n')
        info = tarfile.TarInfo('sucacenter/' + p.relative_to(root).as_posix())
        info.size = len(data)
        info.mode = 0o755 if p.suffix == '.sh' or p.parent.name == 'commands' else 0o644
        info.mtime = 0
        tar.addfile(info, io.BytesIO(data))
payload = gzip.compress(buf.getvalue(), mtime=0)
digest = hashlib.sha256(payload).hexdigest()
loader = r'''#!/usr/bin/env bash
# SucaCenter: pacote autocontido; não baixa código nem inclui credenciais.
set -euo pipefail
command -v base64 >/dev/null
command -v sha256sum >/dev/null
mkdir -p "$HOME/cluster/installations"
stage=$(mktemp -d "$HOME/cluster/installations/release.XXXXXX")
awk 'found {print} /^__SUCACENTER_PAYLOAD__$/ {found=1}' "$0" | base64 -d > "$stage/payload.tar.gz"
printf '%s  %s\n' 'PAYLOAD_HASH' "$stage/payload.tar.gz" | sha256sum -c -
tar -xzf "$stage/payload.tar.gz" -C "$stage"
echo "Pacote extraído em $stage/sucacenter"
if (($# == 0)); then set -- setup; fi
exec bash "$stage/sucacenter/sucacenter.sh" "$@"
exit 1
__SUCACENTER_PAYLOAD__
'''
sh = out / 'bootstrap-sucacenter.sh'
sh.write_bytes(loader.replace('PAYLOAD_HASH', digest).encode() + base64.encodebytes(payload))
zip_path = out / f'sucacenter-{version}.zip'
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in paths:
        entry = zipfile.ZipInfo('sucacenter/' + p.relative_to(root).as_posix(), (2026, 1, 1, 0, 0, 0))
        entry.external_attr = (0o100755 if p.suffix == '.sh' or p.parent.name == 'commands' else 0o100644) << 16
        z.writestr(entry, p.read_bytes().replace(b'\r\n', b'\n'), compress_type=zipfile.ZIP_DEFLATED)
(out / 'SHA256SUMS').write_text('\n'.join(
    f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}' for p in (sh, zip_path)) + '\n')
print(sh)
print(zip_path)
