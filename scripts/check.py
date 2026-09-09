#!/usr/bin/env python3
"""Run local checks without modifying installed apps or user configuration."""
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def run(*command):
    subprocess.run(command, cwd=ROOT, check=True)

def main():
    if sys.platform != 'darwin':
        raise SystemExit('The integration checks require macOS.')
    scripts = [*ROOT.glob('*.sh'), *ROOT.glob('scripts/*.zsh'), *ROOT.glob('shell/*.zsh'), ROOT / 'shell/ghostty-im']
    for script in sorted(scripts):
        run('/bin/zsh', '-n', str(script))
    print('PASS: shell syntax', flush=True)
    for test in ('test_distribution.py', 'test_dependency.py', 'test_build.py'):
        run(sys.executable, str(ROOT / 'tests' / test))
    lua = shutil.which('lua')
    if lua:
        run(lua, 'tests/test_state.lua', 'GhosttyInputMethod.spoon/init.lua')
    else:
        candidates = [os.environ.get('GIM_TEST_LUA_LIBRARY'),
                      '/Applications/Hammerspoon.app/Contents/Frameworks/LuaSkin.framework/Versions/A/LuaSkin',
                      str(Path.home() / 'Applications/Hammerspoon.app/Contents/Frameworks/LuaSkin.framework/Versions/A/LuaSkin')]
        library = next((path for path in candidates if path and Path(path).is_file()), None)
        if not library:
            raise SystemExit('Install Lua, or set GIM_TEST_LUA_LIBRARY to the LuaSkin library bundled with Hammerspoon.')
        environment = dict(os.environ, GIM_TEST_LUA_LIBRARY=library)
        subprocess.run([sys.executable, 'tests/run_lua.py'], cwd=ROOT, env=environment, check=True)
    print('PASS: all local checks')

if __name__ == '__main__':
    main()
