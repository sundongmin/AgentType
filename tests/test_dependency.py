#!/usr/bin/env python3
"""Dependency tests use temporary directories and fake commands, never real installs."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
URL = 'https://github.com/Hammerspoon/hammerspoon/releases/download/1.1.1/Hammerspoon-1.1.1.zip'

class DependencyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ghostty-dependency-test-')
        self.base = Path(self.temp.name)
        self.home = self.base / 'home with spaces'
        self.home.mkdir()
        self.stage = self.base / 'stage'
        self.stage.mkdir()
        self.log = self.base / 'log'
        self.env = dict(os.environ, GIM_PACKAGE=str(ROOT), GIM_HOME=str(self.home),
                        GIM_STAGE=str(self.stage), GIM_LOG=str(self.log))

    def tearDown(self):
        self.temp.cleanup()

    def shell(self, body):
        setup = '''emulate -LR zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL
package_dir=$GIM_PACKAGE
target_home=$GIM_HOME
stage_dir=$GIM_STAGE
dry_run=0
die() { print -u2 -r -- "$*"; exit 1; }
source "$package_dir/scripts/ensure-hammerspoon.zsh"
'''
        return subprocess.run(['/bin/zsh', '-c', setup + body], env=self.env, text=True,
                              capture_output=True, timeout=10)

    def branches(self, body):
        return self.shell('''
gim_find_hammerspoon() {
    [[ -f "$target_home/installed" ]] || return 1
    REPLY="$target_home/Applications/Hammerspoon.app"
}
gim_find_brew() {
    [[ -x "$target_home/brew" ]] || return 1
    REPLY="$target_home/brew"
}
gim_application_dir() { REPLY="$target_home/Applications"; }
gim_install_github() { print GITHUB >> "$GIM_LOG"; touch "$target_home/installed"; }
''' + body)

    def brew(self, fail=False, create=True):
        file = self.home / 'brew'
        file.write_text('#!/bin/zsh\nprint -rl -- "$@" >> "$GIM_LOG"\n' +
                        ('exit 23\n' if fail else ('touch "$GIM_HOME/installed"\n' if create else 'exit 0\n')))
        file.chmod(0o700)

    def test_existing_app_is_reused(self):
        (self.home / 'installed').touch()
        self.brew()
        result = self.branches('gim_ensure_hammerspoon')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('复用已安装', result.stdout)
        self.assertFalse(self.log.exists())

    def test_homebrew_is_preferred(self):
        self.brew()
        result = self.branches('gim_ensure_hammerspoon')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(),
                         ['install','--cask','--appdir=' + str(self.home / 'Applications'),'hammerspoon'])

    def test_no_homebrew_uses_github(self):
        result = self.branches('gim_ensure_hammerspoon')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), 'GITHUB\n')

    def test_brew_failure_stops_without_silent_fallback(self):
        self.brew(fail=True)
        result = self.branches('gim_ensure_hammerspoon')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Homebrew 安装 Hammerspoon 失败', result.stderr)
        self.assertNotIn('GITHUB', self.log.read_text())

    def test_successful_command_with_missing_app_is_failure(self):
        self.brew(create=False)
        result = self.branches('gim_ensure_hammerspoon')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('未找到完整的 Hammerspoon.app', result.stderr)

    def test_dry_run_never_fetches_or_installs(self):
        for use_brew in (False, True):
            if use_brew:
                self.brew()
            result = self.branches('dry_run=1; gim_ensure_hammerspoon')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('未下载、未安装', result.stdout)
            self.assertFalse(self.log.exists())
            self.assertFalse((self.home / 'Applications').exists())

    def metadata(self, **updates):
        release = {'tag_name':'1.1.1', 'draft':False, 'prerelease':False,
                   'assets':[{'name':'Hammerspoon-1.1.1.zip', 'browser_download_url':URL,
                              'digest':'sha256:' + 'a' * 64}]}
        release.update(updates)
        return release

    def parse(self, release):
        metadata = self.base / 'release.json'
        metadata.write_text(json.dumps(release))
        return subprocess.run(['/usr/bin/osascript','-l','JavaScript',str(ROOT / 'scripts/release-asset.js'),
                               str(metadata)], capture_output=True, text=True, timeout=10)

    def test_official_release_parser(self):
        result = self.parse(self.metadata())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['1.1.1',URL,'a'*64])

    def test_parser_rejects_nonofficial_assets_and_missing_digest(self):
        for field, value in [('browser_download_url','https://example.com/evil.zip'), ('digest',None)]:
            release = self.metadata()
            release['assets'][0][field] = value
            self.assertNotEqual(self.parse(release).returncode, 0)
        self.assertNotEqual(self.parse(self.metadata(prerelease=True)).returncode, 0)

    def test_download_failure_stops_before_install(self):
        result = self.shell('''gim_fetch() { return 1; }
gim_copy_app() { touch "$GIM_LOG"; }
gim_install_github "$target_home/Applications"
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('无法读取官方 GitHub 发行信息', result.stderr)
        self.assertFalse(self.log.exists())

    def test_digest_mismatch_stops_before_extraction(self):
        metadata = self.base / 'release.json'
        metadata.write_text(json.dumps(self.metadata()))
        self.env['GIM_METADATA'] = str(metadata)
        result = self.shell('''gim_fetch() {
    if [[ $1 == *releases/latest ]]; then cp "$GIM_METADATA" "$2"
    else print broken > "$2"; fi
}
gim_copy_app() { touch "$GIM_LOG"; }
gim_install_github "$target_home/Applications"
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SHA-256 不匹配', result.stderr)
        self.assertFalse(self.log.exists())
        self.assertFalse((self.stage / 'hammerspoon-download/extracted').exists())

    def test_move_does_not_replace_existing_app(self):
        source, destination = self.base / 'source', self.base / 'destination'
        source.mkdir()
        destination.mkdir()
        (source / 'marker').write_text('new')
        (destination / 'marker').write_text('existing')
        result = subprocess.run(['/usr/bin/osascript','-l','JavaScript',str(ROOT / 'scripts/move-app.js'),
                                 str(source),str(destination)],capture_output=True,text=True,timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((destination / 'marker').read_text(), 'existing')
        self.assertEqual((source / 'marker').read_text(), 'new')

    def test_copy_app_uses_temporary_sibling_then_moves(self):
        source = self.base / 'Hammerspoon.app'
        source.mkdir()
        (source / 'marker').write_text('application')
        self.env['GIM_APP_SOURCE'] = str(source)
        result = self.shell('gim_copy_app "$GIM_APP_SOURCE" "$target_home/Applications"')
        self.assertEqual(result.returncode, 0, result.stderr)
        destination = self.home / 'Applications'
        self.assertEqual((destination / 'Hammerspoon.app/marker').read_text(), 'application')
        self.assertEqual([p.name for p in destination.iterdir()], ['Hammerspoon.app'])

if __name__ == '__main__':
    unittest.main(verbosity=2)
