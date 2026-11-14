"""Run the native Godot checks and reject engine errors even when Godot exits with 0."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / 'game'
FATAL = re.compile(r'(?m)^(SCRIPT ERROR:|ERROR:|FAIL[: ]|FAIL VISUAL:)|WARNING: \d+ ObjectDB instances were leaked')


def find_engine(explicit: str | None) -> Path:
    if explicit:
        path = Path(explicit).expanduser().resolve()
        if path.is_file():
            return path
        raise SystemExit('Godot executable not found: ' + str(path))
    for name in ('godot_console.exe', 'godot.exe', 'godot'):
        found = shutil.which(name)
        if found:
            return Path(found)
    local = Path(os.environ.get('LOCALAPPDATA', ''))
    choices = sorted((local / 'Microsoft/WinGet/Packages').glob('GodotEngine.GodotEngine_*/Godot_v4.7.2*console.exe'))
    if choices:
        return choices[0]
    raise SystemExit('Install Godot 4.7.2 or pass --engine /path/to/godot.')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine')
    parser.add_argument('--quick', action='store_true')
    parser.add_argument('--visual', action='store_true', help='Also open a graphics window and capture biome/animation fixtures.')
    args = parser.parse_args()
    engine = find_engine(args.engine)
    result_dir = ROOT / 'test-results'
    result_dir.mkdir(exist_ok=True)
    commands = [('import', ['--headless', '--editor', '--quit'])]
    scripts = ['test_rules.gd', 'test_story.gd', 'test_journey.gd', 'test_edges.gd', 'test_ui.gd', 'test_relics.gd', 'test_squads.gd', 'test_squad_markers.gd', 'test_squad_retreat.gd', 'test_nodes.gd', 'test_equipment_system.gd']
    if (GAME / 'tests/test_battle_ui.gd').exists():
        scripts.extend(['test_battle_ui.gd', 'test_chess_loadout.gd'])
    for script in scripts:
        command = ['--headless', '--script', 'res://tests/' + script]
        if args.quick and script == 'test_rules.gd':
            command += ['--', '--quick']
        commands.append((script, command))
    if args.visual:
        commands.append(('visual_capture.gd', ['--script', 'res://tests/visual_capture.gd']))
        for script in ['test_animation_samples.gd', 'test_actor_assets.gd', 'test_map_motion.gd', 'test_map_landmarks.gd',
                       'test_native_session.gd']:
            commands.append((script, ['--script', 'res://tests/' + script]))
    results = []
    for name, command in commands:
        started = time.monotonic()
        try:
            process = subprocess.run([str(engine), '--path', str(GAME), *command], cwd=ROOT,
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     encoding='utf-8', errors='replace', timeout=180)
            output = process.stdout
            returncode = process.returncode
        except subprocess.TimeoutExpired as error:
            raw = error.stdout or b''
            output = (raw.decode('utf-8', 'replace') if isinstance(raw, bytes) else raw) + '\nERROR: check timed out\n'
            returncode = 124
        (result_dir / (name + '.log')).write_text(output, encoding='utf-8')
        passed = returncode == 0 and FATAL.search(output) is None
        summaries = [line for line in output.splitlines() if re.search(r'checks|JOURNEY COMPLETE|FIXTURES:', line)]
        entry = dict(name=name, passed=passed, returncode=returncode,
                     seconds=round(time.monotonic() - started, 2), summaries=summaries)
        results.append(entry)
        print(('PASS ' if passed else 'FAIL ') + name + ': ' + ' | '.join(summaries), flush=True)
        if not passed:
            print(output[-8000:], flush=True)
    report = dict(quick=args.quick, visual=args.visual, passed=all(item['passed'] for item in results), results=results)
    (result_dir / 'summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
