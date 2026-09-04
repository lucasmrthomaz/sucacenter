#!/usr/bin/env bash
# Compilação sintética: 24 unidades C++ com e sem distcc, sem cache.
set -euo pipefail
source "$SUCACENTER_ROOT/lib/common.sh"
export LOCAL_SLOTS WORKER_SLOTS
exec python3 - <<'PY'
import concurrent.futures as cf
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
for tool in ('g++', 'distcc'):
    if not shutil.which(tool):
        raise SystemExit('Falta: ' + tool)
base = Path.home() / 'cluster'
hosts = (base / 'config/distcc-hosts').read_text().strip()
if not any(not x.startswith('localhost') and '/' in x for x in hosts.split()):
    raise SystemExit('Configure workers em config/distcc-hosts antes do benchmark.')
work = base / 'workloads'
work.mkdir(parents=True, exist_ok=True)
root = Path(tempfile.mkdtemp(prefix='bench-distcc-', dir=work))
os.chdir(root)
print('Projeto/logs:', root, flush=True)
sources = []
for unit in range(24):
    name = f'unit{unit}.cpp'
    lines = ['using U = unsigned long long;']
    for func in range(64):
        lines += [f'static U f{func}(U x) {{']
        for step in range(32):
            lines += [f'x ^= x >> {7 + step % 19}; x = x * 6364136223846793005ULL + {1+unit*4096+func*32+step}ULL;']
        lines += ['return x; }']
    lines += [f'U unit{unit}(U x) {{']
    lines += [f'x = f{i}(x);' for i in range(64)]
    lines += ['return x; }']
    Path(name).write_text('\n'.join(lines))
    sources.append(name)
Path('main.cpp').write_text('\n'.join(
    ['#include <cstdio>', 'using U = unsigned long long;'] +
    [f'U unit{i}(U);' for i in range(24)] + ['int main(){ U x=123;'] +
    [f'x=unit{i}(x);' for i in range(24)] + ['std::printf("%llu\\n",x); return 0;}']))
sources.append('main.cpp')
def build(name, workers, compiler):
    out = root / name
    out.mkdir()
    print(name, 'compilando...', flush=True)
    start = time.monotonic()
    def one(src):
        obj = out / (src + '.o')
        env = dict(os.environ, CCACHE_DISABLE='1', DISTCC_HOSTS=hosts,
                   DISTCC_FALLBACK='0', DISTCC_VERBOSE='1', DISTCC_LOG=str(out / (src + '.distcc.log')))
        with (out / (src + '.log')).open('w') as log:
            subprocess.run(compiler + ['-O2', '-std=c++17', '-c', src, '-o', str(obj)],
                           env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        return str(obj)
    with cf.ThreadPoolExecutor(max_workers=workers) as pool:
        objects = list(pool.map(one, sources))
    binary = out / 'test'
    subprocess.run(['g++', *objects, '-o', str(binary)], check=True)
    elapsed = time.monotonic() - start
    result = subprocess.check_output([str(binary)], text=True)
    print(f'{name}: {elapsed:.2f}s', flush=True)
    return elapsed, result
slots = sum(int(x.split('/')[1].split(',')[0]) for x in hosts.split() if '/' in x)
local, a = build('local', int(os.environ['LOCAL_SLOTS']), ['g++'])
cluster, b = build('cluster', slots, ['distcc', 'g++'])
if a != b:
    raise SystemExit('Resultados divergentes!')
logs = '\n'.join(p.read_text() for p in (root/'cluster').glob('*.distcc.log'))
if not re.search(r'compile .* on (?!localhost)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/\d+ completed ok', logs):
    raise SystemExit('Nenhuma compilação remota comprovada nos logs.')
print(f'OK: local={local:.2f}s cluster={cluster:.2f}s aceleração={local/cluster:.2f}x')
print('Carga sintética; não representa todos os projetos. Logs:', root)
PY
