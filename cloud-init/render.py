"""Prepara um seed NoCloud; requer Python 3.9+ e ssh-keygen no controlador."""
import argparse
import json
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("node", help="Nome da pasta em nodes/, por exemplo worker03")
    parser.add_argument("--public-key", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path,
                        help="Diretorio novo; nunca sobrescreve um seed existente")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", args.node):
        parser.error("Nome de no invalido")
    try:
        key = args.public_key.read_text(encoding="utf-8").strip()
        if len(key.splitlines()) != 1 or not re.match(
                r"^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(?:256|384|521)) [A-Za-z0-9+/]+=*(?: .*)?$", key):
            parser.error("Forneca uma unica chave PUBLICA OpenSSH (.pub), sem opcoes")
        subprocess.run(["ssh-keygen", "-lf", str(args.public_key.resolve())],
                       check=True, capture_output=True)
        template = (root / "common/user-data.yaml").read_text(encoding="utf-8")
        if template.count("__MASTER_PUBLIC_KEY__") != 1:
            parser.error("Template deve conter exatamente um __MASTER_PUBLIC_KEY__")
        files = {"user-data": template.replace("__MASTER_PUBLIC_KEY__", json.dumps(key))}
        for name in ("meta-data", "network-config"):
            files[name] = (root / "nodes" / args.node / (name + ".yaml")).read_text(encoding="utf-8")
        args.output.mkdir(parents=True, exist_ok=False)
        for name, content in files.items():
            (args.output / name).write_bytes(content.encode("utf-8"))
    except (OSError, UnicodeError, subprocess.CalledProcessError) as exc:
        parser.error(f"Nao foi possivel gerar o seed: {exc}")
    print(f"Seed criado em {args.output}. Confira a rede antes do primeiro boot.")


if __name__ == "__main__":
    main()
