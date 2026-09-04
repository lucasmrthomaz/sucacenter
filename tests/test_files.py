import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('files', ROOT / 'lib/files.py')
files = importlib.util.module_from_spec(spec)
spec.loader.exec_module(files)

class FileTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.src = self.root / 'source'
        self.src.mkdir()
        (self.src / 'a space.txt').write_text('hello')
    def tearDown(self):
        self.tmp.cleanup()
    def test_roundtrip_and_no_overwrite(self):
        arc = self.root / 'backup.tar.gz'
        files.execute('archive', [str(self.src), str(arc)])
        files.execute('decompress', [str(arc), str(self.root / 'restored')])
        self.assertEqual((self.root / 'restored/source/a space.txt').read_text(), 'hello')
        with self.assertRaises(FileExistsError):
            files.execute('archive', [str(self.src), str(arc)])
    def test_checksum_detects_changes(self):
        manifest = self.root / 'checksum.json'
        files.execute('checksum', [str(self.src), str(manifest)])
        files.execute('verify', [str(self.src), str(manifest)])
        (self.src / 'a space.txt').write_text('changed')
        with self.assertRaises(ValueError):
            files.execute('verify', [str(self.src), str(manifest)])
    def test_traversal_rejected(self):
        arc = self.root / 'bad.tar'
        with tarfile.open(arc, 'w') as t:
            member = tarfile.TarInfo('../outside')
            member.size = 1
            t.addfile(member, io.BytesIO(b'x'))
        with self.assertRaises(ValueError):
            files.execute('decompress', [str(arc), str(self.root / 'restored')])
        self.assertFalse((self.root / 'outside').exists())
    def test_manifest_escape_rejected(self):
        manifest = self.root / 'bad.json'
        manifest.write_text(json.dumps({'../outside': 'abc'}))
        with self.assertRaises(ValueError):
            files.execute('verify', [str(self.src), str(manifest)])
    def test_link_rejected(self):
        arc = self.root / 'link.tar'
        with tarfile.open(arc, 'w') as t:
            m = tarfile.TarInfo('link')
            m.type = tarfile.SYMTYPE
            m.linkname = '/etc/passwd'
            t.addfile(m)
        with self.assertRaises(ValueError):
            files.execute('decompress', [str(arc), str(self.root / 'restored')])
