"""Carga sintética local, limitada em tempo; não mede ganho de distcc."""
import hashlib
import multiprocessing as mp
import os
import sys
import time

def work(seconds):
    end = time.monotonic() + seconds
    block = b'x' * (1024 * 1024)
    count = 0
    while time.monotonic() < end:
        hashlib.sha256(block).digest()
        count += 1
    return count

if __name__ == '__main__':
    seconds = int(sys.argv[1])
    if not 1 <= seconds <= 3600:
        raise SystemExit('Duração deve ser de 1 a 3600 segundos.')
    start = time.monotonic()
    try:
        with mp.Pool(os.cpu_count() or 1) as pool:
            total = sum(pool.map(work, [seconds] * (os.cpu_count() or 1)))
        print(f'{total / (time.monotonic() - start):.1f} MiB/s SHA-256')
    except KeyboardInterrupt:
        raise SystemExit(130)
