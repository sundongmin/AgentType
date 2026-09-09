#!/usr/bin/env python3
"""Isolated filesystem and zsh integration tests; never source user dotfiles."""
import os
import pty
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ghostty-im-test-')
        self.base = Path(self.temp.name)
        self.home = self.base / "user space ' quote $ dollar `tick`"
        self.home.mkdir()
        self.hs = self.home / '.hammerspoon'
        self.hs.mkdir()
        self.rc = self.home / '.zshrc'
        self.rc.write_text('# my shell\nexport MY_EXISTING_SETTING=keep\n')
        self.init = self.hs / 'init.lua'
        self.init.write_text('-- my config\nlocal my_setting = true\n')
        self.before = (self.rc.read_bytes(), self.init.read_bytes())
        self.sources = self.base / 'sources.tsv'
        self.sources.write_text('com.apple.keylayout.ABC\tABC\tother\n'
                                'com.tencent.inputmethod.wetype.pinyin\t微信输入法\tchinese\n'
                                'com.apple.inputmethod.SCIM.ITABC\t简体拼音\tchinese\n')

    def tearDown(self):
        self.temp.cleanup()

    def manage(self, action='install', *args, ok=True, env=None, choose=True):
        options = list(args)
        if (choose and action == 'install' and '--agent-source' not in options
                and '--dry-run' not in options and not (self.hs / 'GhosttyInputMethod/config.lua').exists()):
            options += ['--agent-source', 'com.tencent.inputmethod.wetype.pinyin']
        cmd = ['/bin/zsh', str(ROOT / (action + '.sh')), '--target-home', str(self.home), *options]
        environment = dict(os.environ if env is None else env, GIM_TEST_INPUT_SOURCES=str(self.sources))
        result = subprocess.run(cmd, text=True, capture_output=True, env=environment, timeout=10)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def interactive_install(self, answers):
        master, slave = pty.openpty()
        try:
            environment = dict(os.environ, GIM_TEST_INPUT_SOURCES=str(self.sources))
            process = subprocess.Popen(['/bin/zsh', str(ROOT / 'install.sh'), '--target-home', str(self.home)],
                                       stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       env=environment, text=True)
            os.close(slave)
            slave = -1
            os.write(master, answers.encode())
            try:
                output, _ = process.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                output, _ = process.communicate()
                self.fail('picker did not terminate: ' + output)
            return process.returncode, output
        finally:
            os.close(master)
            if slave != -1:
                os.close(slave)

    def test_interactive_selection_invalid_input_then_second_choice(self):
        code, output = self.interactive_install('999\nabc\n\n2\n')
        self.assertEqual(code, 0, output)
        self.assertIn('1) 微信输入法', output)
        self.assertIn('2) 简体拼音', output)
        self.assertNotIn('1) ABC', output)
        self.assertIn('请输入列表中的编号', output)
        config = (self.hs / 'GhosttyInputMethod/config.lua').read_text()
        self.assertIn('com.apple.inputmethod.SCIM.ITABC', config)
        self.assertIn('pollInterval = 0.15', config)

    def test_single_choice_still_requires_selection(self):
        self.sources.write_text('com.apple.keylayout.ABC\tABC\tother\n'
                                'com.tencent.inputmethod.wetype.pinyin\t微信输入法\tchinese\n')
        result = self.manage(ok=False, choose=False)
        self.assertIn('非交互安装需要 --agent-source', result.stderr)
        code, output = self.interactive_install('1\n')
        self.assertEqual(code, 0, output)
        self.assertIn('已选择: 微信输入法', output)

    def test_cancel_does_not_modify_configuration(self):
        code, output = self.interactive_install('q\n')
        self.assertNotEqual(code, 0)
        self.assertIn('安装已取消', output)
        self.assertEqual(self.before, (self.rc.read_bytes(), self.init.read_bytes()))
        self.assertFalse((self.hs / 'GhosttyInputMethod').exists())

    def test_no_enabled_chinese_source(self):
        self.sources.write_text('com.apple.keylayout.ABC\tABC\tother\n')
        result = self.manage(ok=False, choose=False)
        self.assertIn('没有找到已启用、可切换的中文输入法', result.stderr)
        self.assertEqual(self.before, (self.rc.read_bytes(), self.init.read_bytes()))

    def test_unknown_explicit_source_is_rejected(self):
        result = self.manage('install', '--agent-source', 'com.not.installed', ok=False)
        self.assertIn('未启用或不可切换', result.stderr)
        self.assertEqual(self.before, (self.rc.read_bytes(), self.init.read_bytes()))

    def test_upgrade_migrates_old_poll_default_and_keeps_input_source(self):
        self.manage()
        config = self.hs / 'GhosttyInputMethod/config.lua'
        config.write_text(config.read_text().replace('0.15', '0.25'))
        self.sources.unlink()  # Upgrade must not need a new source scan or prompt.
        self.manage()
        self.assertIn('pollInterval = 0.15', config.read_text())
        self.assertIn('com.tencent.inputmethod.wetype.pinyin', config.read_text())

    def test_dry_run_no_mutations(self):
        self.manage('install', '--dry-run')
        self.assertEqual(self.before, (self.rc.read_bytes(), self.init.read_bytes()))
        self.assertEqual(sorted(p.name for p in self.hs.iterdir()), ['init.lua'])

    def test_install_upgrade_uninstall_preserves_user_content(self):
        self.manage('install', '--agent-source', 'com.apple.inputmethod.SCIM.ITABC')
        config = self.hs / 'GhosttyInputMethod/config.lua'
        self.assertIn('com.apple.inputmethod.SCIM.ITABC', config.read_text())
        config.write_text(config.read_text().replace('0.15', '0.35'))
        self.manage()
        self.assertIn('0.35', config.read_text())
        self.assertEqual(self.rc.read_text().count('# BEGIN GhosttyInputMethod'), 1)
        self.assertEqual(self.init.read_text().count('-- BEGIN GhosttyInputMethod'), 1)
        self.rc.write_text(self.rc.read_text() + '# new setting after install\n')
        self.manage('uninstall')
        self.assertEqual(self.rc.read_bytes(), self.before[0] + b'# new setting after install\n')
        self.assertEqual(self.init.read_bytes(), self.before[1])
        self.assertFalse((self.hs / 'GhosttyInputMethod').exists())
        self.assertFalse((self.hs / 'Spoons/GhosttyInputMethod.spoon').exists())
        self.assertTrue((self.hs / 'GhosttyInputMethod-backups').is_dir())

    def test_detects_legacy_without_writes(self):
        self.init.write_text('local ghosttyIM = {}\n')
        previous = self.init.read_bytes()
        self.manage(ok=False)
        self.assertEqual(self.init.read_bytes(), previous)
        self.assertEqual(self.rc.read_bytes(), self.before[0])

    def test_rejects_malformed_and_repeated_blocks(self):
        for content in ['# BEGIN GhosttyInputMethod managed v1\nanything\n',
                        '# END GhosttyInputMethod managed v1\n',
                        ('# BEGIN GhosttyInputMethod managed v1\n# END GhosttyInputMethod managed v1\n') * 2]:
            self.rc.write_text(content)
            self.manage(ok=False)
            self.assertEqual(self.rc.read_text(), content)

    def test_rejects_symlink_dotfile(self):
        source = self.base / 'managed-dotfile'
        source.write_text('unchanged\n')
        self.rc.unlink()
        self.rc.symlink_to(source)
        self.manage(ok=False)
        self.assertTrue(self.rc.is_symlink())
        self.assertEqual(source.read_text(), 'unchanged\n')

    def test_custom_zshrc_remembered_by_uninstaller(self):
        custom = self.home / 'custom.zshrc'
        custom.write_text('# custom\n')
        self.manage('install', '--zshrc', str(custom))
        self.manage('uninstall')
        self.assertEqual(custom.read_text(), '# custom\n')
        self.assertEqual(self.rc.read_bytes(), self.before[0])

    def test_invalid_sources_and_bad_existing_syntax(self):
        self.manage('install', '--agent-source', 'bad"; os.execute("bad")', ok=False)
        self.rc.write_text('if broken syntax\n')
        self.manage(ok=False)
        self.assertEqual(self.init.read_bytes(), self.before[1])

    def test_rollback_on_commit_failure(self):
        fake = self.base / 'bin'
        fake.mkdir()
        cp = fake / 'cp'
        cp.write_text('#!/bin/zsh\nfor a in "$@"; do\n[[ $a == */GhosttyInputMethod.spoon ]] && exit 77\ndone\nexec /bin/cp "$@"\n')
        cp.chmod(0o700)
        env = dict(os.environ, PATH=str(fake) + ':' + os.environ['PATH'])
        self.manage(ok=False, env=env)
        self.assertEqual(self.before, (self.rc.read_bytes(), self.init.read_bytes()))
        self.assertFalse((self.hs / 'GhosttyInputMethod').exists())

    def setup_shell(self):
        self.manage()
        fake = self.base / 'bin'
        fake.mkdir()
        hs = fake / 'hs'
        hs.write_text('''#!/bin/zsh
code=${@[-1]}
case $code in
  *':resolveTTY('* ) print RESOLVE >> "$GIM_TEST_LOG"; print terminal-A ;;
  *':setState('* )
    [[ $code == *'"agent"'* ]] && print AGENT >> "$GIM_TEST_LOG" || print TERMINAL >> "$GIM_TEST_LOG"
    [[ ${GIM_TEST_IPC_FAIL:-0} == 1 ]] && { print false; exit 0; }
    print true ;;
  *) print STATUS ;;
esac
''')
        hs.chmod(0o700)
        agent = fake / 'codex'
        agent.write_text('#!/bin/zsh\nfor a in "$@"; do print -r -- "$a"; done > "$GIM_TEST_ARGS"\nexit 37\n')
        agent.chmod(0o700)
        self.env = dict(os.environ, GHOSTTY_RESOURCES_DIR='/fake/ghostty', GHOSTTY_IM_HS=str(hs),
                        GIM_TEST_LOG=str(self.base / 'calls'), GIM_TEST_ARGS=str(self.base / 'args'),
                        PATH=str(fake) + ':' + os.environ['PATH'], SSH_CONNECTION='', TMUX='',
                        GHOSTTY_IM_DISABLED='0', GIM_TEST_RC=str(self.rc))

    def shell(self, script, extra=None):
        env = dict(self.env)
        env.update(extra or {})
        return subprocess.run(['/bin/zsh', '-dfi', '-c', script], capture_output=True, text=True,
                              env=env, timeout=10)

    def test_shell_quoting_exit_status_and_identity_cache(self):
        self.setup_shell()
        result = self.shell('''TTY=/dev/ttys999
source "$GIM_TEST_RC"
_gim_prompt
_gim_prompt
codex -c 'space argument' '$(do-not-execute)'
result=$?
_gim_prompt
_gim_prompt
print -- "RESULT=$result"
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('RESULT=37', result.stdout)
        self.assertEqual((self.base / 'args').read_text(), '-c\nspace argument\n$(do-not-execute)\n')
        self.assertEqual((self.base / 'calls').read_text().splitlines(), ['RESOLVE','TERMINAL','AGENT','TERMINAL'])

    def test_shell_ipc_failure_does_not_block_agent(self):
        self.setup_shell()
        result = self.shell('TTY=/dev/ttys999; source "$GIM_TEST_RC"; codex -c; print RESULT=$?',
                            {'GIM_TEST_IPC_FAIL':'1'})
        self.assertIn('RESULT=37', result.stdout)
        self.assertEqual((self.base / 'args').read_text(), '-c\n')

    def test_existing_function_and_alias_preserved(self):
        self.setup_shell()
        result = self.shell('''codex() { print ORIGINAL; }
alias claude='print ALIAS'
source "$GIM_TEST_RC"
source "$GIM_TEST_RC"
codex
print -r -- $aliases[claude]
print -- "HOOKS=${#precmd_functions}"
''')
        self.assertIn('ORIGINAL', result.stdout)
        self.assertIn('print ALIAS', result.stdout)
        self.assertIn('HOOKS=1', result.stdout)

    def test_remote_tmux_and_disabled_skip_integration(self):
        self.setup_shell()
        for extra in ({'SSH_CONNECTION':'remote'}, {'TMUX':'session'}, {'GHOSTTY_IM_DISABLED':'1'}):
            result = self.shell('source "$GIM_TEST_RC"; print "DEFINED=${+functions[ghostty_im_run]}"', extra)
            self.assertIn('DEFINED=0', result.stdout)

    def test_cli_rejects_injection(self):
        self.setup_shell()
        cli = self.hs / 'GhosttyInputMethod/ghostty-im'
        for args in [('set','id";bad','agent'), ('resolve','/dev/ttys001"bad'), ('set','id','unknown')]:
            result = subprocess.run([str(cli), *args], env=self.env, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 2)
        self.assertFalse((self.base / 'calls').exists())

if __name__ == '__main__':
    unittest.main(verbosity=2)
