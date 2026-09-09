#!/usr/bin/env python3
"""Build AgentType archives without Git, network access, or third-party packages."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ENTRIES = (
    '.github', '.gitignore', '.gitattributes', 'VERSION', 'project.json',
    'README.md', 'README.en.md', 'LICENSE', 'CHANGELOG.md', 'CONTRIBUTING.md',
    'install.sh', 'uninstall.sh', 'GhosttyInputMethod.spoon', 'shell', 'scripts', 'tests', 'docs',
)

def source_files():
    result = []
    for entry in SOURCE_ENTRIES:
        path = ROOT / entry
        if not path.exists():
            raise ValueError('Required release path is missing: ' + entry)
        candidates = sorted(path.rglob('*')) if path.is_dir() else [path]
        for file in candidates:
            relative = file.relative_to(ROOT)
            if any(part == '__pycache__' or part.startswith('.') for part in relative.parts[1:]):
                continue
            if file.suffix in ('.pyc', '.pyo', '.log', '.zip') or file.name.endswith('~'):
                continue
            if file.is_symlink():
                raise ValueError('Unexpected source symlink: ' + str(relative))
            if file.is_file():
                result.append(file)
    return sorted(result)

def add_file(archive, file, destination):
    # Stable metadata and explicit permissions also support GitHub web uploads.
    info = zipfile.ZipInfo(str(destination), (2026, 1, 1, 0, 0, 0))
    info.create_system = 3
    executable = file.name in ('install.sh', 'uninstall.sh', 'ghostty-im')
    info.external_attr = ((0o100755 if executable else 0o100644) << 16)
    info.compress_type = zipfile.ZIP_DEFLATED
    archive.writestr(info, file.read_bytes())

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    project = json.loads((ROOT / 'project.json').read_text())
    name, spoon = project['name'], project['spoon']
    version = (ROOT / 'VERSION').read_text().strip()
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*', name) or not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*', spoon):
        raise ValueError('Invalid project or Spoon name')
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('VERSION must be a numeric major.minor.patch version')
    implementation = ROOT / (spoon + '.spoon')
    if 'obj.version = "' + version + '"' not in (implementation / 'init.lua').read_text():
        raise ValueError('VERSION and Spoon version do not match')
    if name + '/' + version not in (ROOT / 'scripts/ensure-hammerspoon.zsh').read_text():
        raise ValueError('Dependency User-Agent version does not match VERSION')
    files = source_files()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    basename = name + '-' + version
    full = output / (basename + '.zip')
    standalone = output / (basename + '.spoon.zip')
    with zipfile.ZipFile(full, 'w') as archive:
        for file in files:
            add_file(archive, file, Path(basename) / file.relative_to(ROOT))
    with zipfile.ZipFile(standalone, 'w') as archive:
        for file in files:
            relative = file.relative_to(ROOT)
            if relative.parts[0] == spoon + '.spoon':
                add_file(archive, file, relative)
            elif relative.parts[0] == 'shell':
                add_file(archive, file, Path(spoon + '.spoon') / relative)
    checksums = []
    for file in (full, standalone):
        with zipfile.ZipFile(file) as archive:
            if archive.testzip() is not None:
                raise ValueError('Archive integrity check failed: ' + file.name)
        checksums.append(hashlib.sha256(file.read_bytes()).hexdigest() + '  ' + file.name)
        print(str(file))
    (output / (basename + '-SHA256SUMS.txt')).write_text('\n'.join(checksums) + '\n')

if __name__ == '__main__':
    main()
