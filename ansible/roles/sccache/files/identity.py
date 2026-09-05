#!/usr/bin/env python3
"""Root-only persistent identity; never print secrets. Re-run to renew the leaf."""
import base64
import ipaddress
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile


def run(*args):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def main():
    ip = str(ipaddress.IPv4Address(sys.argv[1]))
    os.umask(0o077)
    root = Path(__file__).resolve().parent
    changed = False
    secret_file = root / 'secrets.json'
    if not secret_file.exists():
        value = {'client_token': secrets.token_hex(32),
                 'server_key': base64.urlsafe_b64encode(secrets.token_bytes(32)).decode()}
        with tempfile.NamedTemporaryFile(mode='w', dir=root, delete=False) as f:
            json.dump(value, f)
        os.replace(f.name, secret_file)
        changed = True
    ca_key, ca_cert = root / 'ca.key', root / 'ca.crt'
    if ca_key.exists() != ca_cert.exists():
        raise RuntimeError('Incomplete CA identity: restore ca.key and ca.crt together from backup')
    if not ca_key.exists():
        with tempfile.TemporaryDirectory(dir=root) as temp:
            key, cert = Path(temp) / 'ca.key', Path(temp) / 'ca.crt'
            run('openssl', 'req', '-x509', '-newkey', 'rsa:3072', '-nodes',
                '-keyout', str(key), '-out', str(cert), '-days', '3650',
                '-subj', '/CN=SucaCenter sccache CA',
                '-addext', 'basicConstraints=critical,CA:TRUE',
                '-addext', 'keyUsage=critical,keyCertSign,cRLSign')
            os.replace(key, ca_key)
            os.replace(cert, ca_cert)
        changed = True
    # Do not silently rotate the trust root when it expires.
    run('openssl', 'x509', '-in', str(ca_cert), '-checkend', '2592000', '-noout')
    cert, key, address = root / 'scheduler.crt', root / 'scheduler.key', root / 'address'
    renew = not (cert.exists() and key.exists() and address.exists())
    if not renew:
        renew = address.read_text() != ip or subprocess.run(
            ['openssl', 'x509', '-in', str(cert), '-checkend', '2592000', '-noout'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0
    if renew:
        with tempfile.TemporaryDirectory(dir=root) as temp:
            tmp = Path(temp)
            ext = tmp / 'extensions'
            ext.write_text(f'subjectAltName=IP:{ip}\nbasicConstraints=critical,CA:FALSE\n'
                           'keyUsage=critical,digitalSignature,keyEncipherment\n'
                           'extendedKeyUsage=serverAuth\n')
            run('openssl', 'req', '-new', '-newkey', 'rsa:3072', '-nodes',
                '-keyout', str(tmp / 'key'), '-out', str(tmp / 'csr'),
                '-subj', '/CN=SucaCenter sccache scheduler')
            run('openssl', 'x509', '-req', '-in', str(tmp / 'csr'),
                '-CA', str(ca_cert), '-CAkey', str(ca_key),
                '-set_serial', '0x' + secrets.token_hex(16), '-days', '365',
                '-extfile', str(ext), '-out', str(tmp / 'cert'))
            os.replace(tmp / 'key', key)
            os.replace(tmp / 'cert', cert)
            address.write_text(ip)
        changed = True
    print(json.dumps({'changed': changed}))


if __name__ == '__main__':
    main()
