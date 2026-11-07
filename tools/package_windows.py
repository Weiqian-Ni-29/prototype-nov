"""Export a portable Windows build, its notices, guide and integrity manifest."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

from run_checks import ROOT, GAME, FATAL, find_engine


def sha256(path: Path) -> str:
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def run_engine(engine: Path, arguments: list[str], log: Path) -> None:
    result = subprocess.run([str(engine), '--headless', '--path', str(GAME), *arguments],
                            cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            encoding='utf-8', errors='replace', timeout=240)
    log.write_text(result.stdout, encoding='utf-8')
    if result.returncode != 0 or FATAL.search(result.stdout):
        raise SystemExit(result.stdout[-10000:])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine')
    parser.add_argument('--output', type=Path, default=GAME / 'builds/ReturnToTheLamps-MVP-0.2.0-Windows-x64')
    args = parser.parse_args()
    engine = find_engine(args.engine)
    build = GAME / 'builds'
    build.mkdir(exist_ok=True)
    run_engine(engine, ['--editor', '--quit'], build / 'import.log')
    run_engine(engine, ['--export-release', 'Windows x64', str(build / 'ReturnToTheLamps.exe')], build / 'export.log')
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(build / 'ReturnToTheLamps.exe', destination / 'ReturnToTheLamps.exe')
    shutil.copy2(ROOT / 'docs/player-guide.md', destination / '开始游玩.txt')
    shutil.copytree(GAME / 'assets/licenses', destination / 'licenses', dirs_exist_ok=True)
    shutil.copy2(GAME / 'assets/fonts/OFL.txt', destination / 'licenses/NOTO-OFL.txt')
    shutil.copy2(GAME / 'assets/README.md', destination / 'licenses/ASSET-SOURCES.md')
    shutil.copy2(GAME / 'assets/characters/sources.json', destination / 'licenses/CHARACTER-SOURCES.json')
    shutil.copy2(GAME / 'assets/nature/sources.json', destination / 'licenses/NATURE-SOURCES.json')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip())
    files = {str(path.relative_to(destination)).replace('\\', '/'): sha256(path)
             for path in destination.rglob('*') if path.is_file() and path.name != 'build-info.json'}
    metadata = dict(version='0.2.0', target='Windows x64', source_commit=commit, source_dirty=dirty,
                    engine=subprocess.check_output([str(engine), '--version'], text=True).strip(),
                    created_utc=datetime.now(timezone.utc).isoformat(), files_sha256=files)
    (destination / 'build-info.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
    archive = destination.parent / (destination.name + '.zip')
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as package:
        for path in sorted(destination.rglob('*')):
            if path.is_file():
                package.write(path, destination.name + '/' + path.relative_to(destination).as_posix())
    archive.with_suffix('.zip.sha256').write_text(sha256(archive) + '  ' + archive.name + '\n', encoding='utf-8')
    print(json.dumps(dict(folder=str(destination), archive=str(archive), executable_sha256=files['ReturnToTheLamps.exe'],
                          source_commit=commit, source_dirty=dirty), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
