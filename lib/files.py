"""Ferramentas de arquivos: saídas novas, integridade e caminhos relativos."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def new_directory(path):
    if path.exists():
        raise ValueError(f'Destino deve ser novo: {path}')
    path.mkdir(parents=True)

def execute(action, args):
    if action == 'checksum':
        root = Path(args[0] if args else Path.home() / 'cluster/shared-files').resolve()
        out = Path(args[1]) if len(args) > 1 else Path.home() / 'cluster/logs/checksum.json'
        files = {}
        for file in sorted(root.rglob('*')):
            if file.is_file() and not file.is_symlink() and file.resolve() != out.resolve():
                files[str(file.relative_to(root))] = digest(file)
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open('x') as f:
            json.dump(files, f, indent=2)
        print(out)
    elif action == 'verify':
        root = Path(args[0]).resolve()
        manifest = json.loads(Path(args[1]).read_text())
        for rel, expected in manifest.items():
            path = (root / rel).resolve()
            if not path.is_relative_to(root) or not path.is_file() or digest(path) != expected:
                raise ValueError(f'Falha de integridade: {rel}')
        print(f'OK: {len(manifest)} arquivos (arquivos extras não são verificados).')
    elif action in ('archive', 'compress'):
        src, out = Path(args[0]).resolve(), Path(args[1])
        if not src.exists():
            raise ValueError('Origem ausente.')
        if out.resolve().is_relative_to(src):
            raise ValueError('Arquivo de saída não pode estar dentro da origem.')
        # Exclusive create: nunca substitui um backup anterior.
        with out.open('xb') as f, tarfile.open(fileobj=f, mode='w:gz') as tar:
            def safe_member(member):
                if not (member.isfile() or member.isdir()):
                    raise ValueError('Links/dispositivos não são arquivados por este helper.')
                return member
            tar.add(src, arcname=src.name, filter=safe_member)
        print(out)
    elif action == 'decompress':
        archive, target = Path(args[0]), Path(args[1])
        with tarfile.open(archive, 'r:*') as tar:
            members = tar.getmembers()
            root = target.resolve()
            for member in members:
                name = Path(member.name)
                if name.is_absolute() or '..' in name.parts or not (member.isfile() or member.isdir()):
                    raise ValueError(f'Membro inseguro: {member.name}')
                if not (root / name).resolve().is_relative_to(root):
                    raise ValueError('Caminho fora do destino.')
            new_directory(target)
            # Extrai manualmente apenas arquivos regulares/diretórios; sem permissões especiais.
            for member in members:
                path = target / member.name
                if member.isdir():
                    path.mkdir(parents=True, exist_ok=True)
                else:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    with tar.extractfile(member) as inp, path.open('xb') as out:
                        shutil.copyfileobj(inp, out)
        print(target)
    else:
        src, dst = Path(args[0]).resolve(), Path(args[1]).resolve()
        if src.is_dir() and dst.is_relative_to(src):
            raise ValueError('Destino não pode estar dentro da origem.')
        if not src.exists():
            raise ValueError('Origem ausente.')
        value = args[2] if len(args) > 2 else None
        files = [src] if src.is_file() else sorted(p for p in src.rglob('*') if p.is_file() and not p.is_symlink())
        images = {'.jpg', '.jpeg', '.png', '.webp', '.tiff', '.bmp'}
        video = {'.mp4', '.mkv', '.avi', '.mov', '.webm', '.mpeg'}
        audio = {'.mp3', '.wav', '.flac', '.ogg', '.m4a', '.aac'}
        if action.startswith('image-'):
            files = [p for p in files if p.suffix.lower() in images]
            tool = shutil.which('magick') or shutil.which('convert')
            if not tool:
                raise ValueError('ImageMagick ausente.')
            fmt = value or 'png'
            if action == 'image-convert' and fmt not in {'png', 'jpg', 'webp', 'tiff', 'bmp'}:
                raise ValueError('Formato de imagem inválido.')
        else:
            files = [p for p in files if p.suffix.lower() in (video if action == 'video' else audio | video)]
            tool = shutil.which('ffmpeg')
            if not tool:
                raise ValueError('ffmpeg ausente.')
        if not files:
            raise ValueError('Nenhuma entrada compatível.')
        new_directory(dst)
        for file in files:
            rel = Path(file.name) if src.is_file() else file.relative_to(src)
            # Mantém a extensão original no nome para evitar colisão foto.jpg/foto.png.
            ext = (fmt if action == 'image-convert' else 'jpg') if action.startswith('image-') else ('mp4' if action == 'video' else 'mp3')
            out = dst / rel.parent / (rel.name + '.' + ext)
            out.parent.mkdir(parents=True, exist_ok=True)
            if action == 'image-convert':
                command = [tool, str(file), str(out)]
            elif action == 'image-resize':
                width = int(value or 1280)
                if width <= 0:
                    raise ValueError('Largura deve ser positiva.')
                command = [tool, str(file), '-auto-orient', '-resize', f'{width}x{width}>', str(out)]
            elif action == 'image-optimize':
                quality = int(value or 85)
                if not 1 <= quality <= 100:
                    raise ValueError('Qualidade deve ser 1–100.')
                command = [tool, str(file), '-auto-orient', '-strip', '-quality', str(quality), str(out)]
            elif action == 'video':
                command = [tool, '-nostdin', '-n', '-i', str(file), '-c:v', 'libx264', '-crf', '23',
                           '-preset', 'fast', '-threads', '2', '-c:a', 'aac', str(out)]
            elif action == 'audio':
                command = [tool, '-nostdin', '-n', '-i', str(file), '-vn', '-c:a', 'libmp3lame', '-q:a', '3', str(out)]
            else:
                raise ValueError('Operação desconhecida.')
            subprocess.run(command, check=True)
            print(out)

if __name__ == '__main__':
    try:
        execute(sys.argv[1], sys.argv[2:])
    except (ValueError, IndexError, OSError, tarfile.TarError, subprocess.CalledProcessError) as error:
        raise SystemExit(f'ERRO: {error}')
