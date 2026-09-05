#!/usr/bin/env python3
"""Unique offline crate; require a remote success, not silent local fallback."""
import json
from pathlib import Path
import subprocess
import tempfile
import uuid


def remote_count():
    data = json.loads(subprocess.check_output(
        ['sccache', '--show-stats', '--stats-format', 'json'], text=True))
    return sum(data['stats']['dist_compiles'].values())


before = remote_count()
with tempfile.TemporaryDirectory(prefix='sucacenter-sccache-smoke-') as temp:
    root = Path(temp)
    (root / 'src').mkdir()
    (root / 'Cargo.toml').write_text(
        '[package]\nname="sucacenter_sccache_smoke"\nversion="0.1.0"\nedition="2021"\n')
    (root / 'src/lib.rs').write_text('pub fn nonce() -> &' + "'static str { \"" + uuid.uuid4().hex + '\" }\n')
    subprocess.run(['cargo', 'build', '--release', '--offline'], cwd=root, check=True)
after = remote_count()
if after <= before:
    raise SystemExit('Rust built, but no distributed success was recorded; inspect builder/client journals')
print('OK: unique Rust library compiled remotely')
