"""Copy the pinned CC0 Forest Nature Free 1.0 subset and its exact dependencies."""
from pathlib import Path
import argparse, hashlib, json, shutil

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = '2ee83e63bb7695f2d884ec27ddf6fce020789a452e7d5c5b0bbdfc4f6ea1fc8c'
NAMES = ['Tree_1_A', 'Tree_1_C', 'Tree_2_B', 'Tree_3_A', 'Tree_Bare_1_A',
         'Bush_1_B', 'Bush_2_C', 'Grass_1_A', 'Grass_2_B',
         'Rock_1_A', 'Rock_1_F', 'Rock_2_C', 'Rock_3_B']

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', type=Path, required=True)
    args = parser.parse_args()
    archive = args.assets / 'kaykit-forest.zip'
    if hashlib.sha256(archive.read_bytes()).hexdigest() != EXPECTED:
        raise SystemExit('Forest archive differs from the reviewed Free 1.0 input')
    source = args.assets / 'kaykit-forest/KayKit_Forest_Nature_Pack_1.0_FREE'
    target = ROOT / 'game/assets/nature'
    target.mkdir(exist_ok=True)
    bounds = {}
    for name in NAMES:
        path = source / 'Assets/gltf' / (name+'_Color1.gltf')
        doc = json.loads(path.read_text())
        for ref in [path.name] + [v['uri'] for group in ('buffers','images') for v in doc.get(group,[])]:
            shutil.copy2(path.parent/ref, target/ref)
        pos = doc['accessors'][doc['meshes'][0]['primitives'][0]['attributes']['POSITION']]
        bounds[name] = dict(min=pos['min'], max=pos['max'])
    (target/'bounds.json').write_text(json.dumps(bounds, indent=2)+'\n', encoding='utf-8')
    license_path = next(source.rglob('*License*'))
    shutil.copy2(license_path, ROOT/'game/assets/licenses/KAYKIT-FOREST-1.0.txt')
    manifest = dict(author='Kay Lousberg', version='Forest Nature Pack Free 1.0', license='CC0-1.0',
        source='https://kaylousberg.itch.io/kaykit-forest', obtained='2026-11-05', archive_sha256=EXPECTED,
        changes='Subset only; original models and atlas unchanged. Runtime transforms normalize props.',
        files={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(target.iterdir())
               if p.is_file() and not p.name.endswith(('.import','.json','.uid'))})
    (target/'sources.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    print('Prepared',len(NAMES),'CC0 nature models')

if __name__=='__main__': main()
