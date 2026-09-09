#!/usr/bin/env python3
"""Validate portable GitHub checkout packaging and local document links."""
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]

class BuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='agenttype-build-test-')
        self.base = Path(self.temp.name)
        self.checkout = self.base / 'arbitrary-repository-main'
        shutil.copytree(ROOT, self.checkout, ignore=shutil.ignore_patterns('dist', '__pycache__', '.git', '.DS_Store'))
        self.output = self.base / 'packages'
        self.version = (ROOT / 'VERSION').read_text().strip()
        self.prefix = 'AgentType-' + self.version

    def tearDown(self):
        self.temp.cleanup()

    def build(self):
        return subprocess.run([sys.executable, str(self.checkout / 'scripts/build.py'),
                               '--output-dir', str(self.output)],capture_output=True,text=True,timeout=10)

    def test_portable_build_metadata_permissions_and_exclusions(self):
        (self.checkout / '.env').write_text('PRIVATE=do-not-package')
        (self.checkout / 'work').mkdir()
        (self.checkout / 'work/private.txt').write_text('private')
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        archive_path = self.output / (self.prefix + '.zip')
        with zipfile.ZipFile(archive_path) as archive:
            names = archive.namelist()
            for path in ('install.sh','VERSION','project.json','.gitignore','.github/workflows/ci.yml','docs/INSTALL.md'):
                self.assertIn(self.prefix + '/' + path, names)
            self.assertFalse(any('/.env' in path or '/work/' in path or '/dist/' in path or '/.git/' in path for path in names))
            self.assertTrue(archive.getinfo(self.prefix + '/shell/ghostty-im').external_attr >> 16 & 0o111)
            self.assertIsNone(archive.testzip())
        sums = (self.output / (self.prefix + '-SHA256SUMS.txt')).read_text().splitlines()
        for line in sums:
            expected, name = line.split('  ', 1)
            self.assertEqual(hashlib.sha256((self.output / name).read_bytes()).hexdigest(), expected)

    def test_standalone_spoon_is_self_contained(self):
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.output / (self.prefix + '.spoon.zip')) as archive:
            prefix = 'GhosttyInputMethod.spoon/'
            for path in ('init.lua','README.md','LICENSE','shell/ghostty-im','shell/ghostty-input-method.zsh'):
                self.assertIn(prefix + path, archive.namelist())
            self.assertNotIn('docs/INSTALL.md', archive.read(prefix + 'README.md').decode())

    def test_version_mismatch_fails(self):
        (self.checkout / 'VERSION').write_text('9.9.9\n')
        self.assertNotEqual(self.build().returncode, 0)
        self.assertFalse(self.output.exists())

    def test_local_markdown_links_resolve(self):
        for file in ROOT.rglob('*.md'):
            if 'dist' in file.relative_to(ROOT).parts:
                continue
            text = file.read_text()
            for target in re.findall(r'(?<!!)\[[^\]]*\]\(([^)]+)\)', text):
                if target.startswith(('https://','http://','#','mailto:')):
                    continue
                path = target.split('#',1)[0]
                self.assertTrue((file.parent / path).exists(), str(file.relative_to(ROOT)) + ': ' + target)

if __name__ == '__main__':
    unittest.main(verbosity=2)
