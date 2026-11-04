"""Build compact GLBs from the licensed free KayKit downloads, without paid tools.

Inputs are locally acquired archives extracted by the developer; never fetch arbitrary URLs here.
Bone rest values are verified before sharing clips. No model/animation source binaries are executed.
"""
from __future__ import annotations
import argparse, copy, hashlib, json, shutil, struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/assets/characters'
CLIPS = {
 'idle':'Idle_A', 'walk':'Walking_A', 'run':'Running_A',
 'attack_melee':'Melee_1H_Attack_Slice_Diagonal', 'attack_heavy':'Melee_1H_Attack_Chop',
 'bow_draw':'Ranged_Bow_Draw', 'attack_bow':'Ranged_Bow_Release',
 'cast':'Ranged_Magic_Shoot', 'support':'Ranged_Magic_Raise',
 'channel':'Ranged_Magic_Spellcasting', 'guard':'Melee_Block',
 'hit':'Hit_A', 'down':'Death_A', 'item':'Use_Item', 'rally':'Waving',
 'crossbow_aim':'Ranged_2H_Aiming', 'crossbow_shoot':'Ranged_2H_Shoot',
 'bow_draw_up':'Ranged_Bow_Draw_Up', 'bow_release_up':'Ranged_Bow_Release_Up',
}
BONES = dict(zip(
 ['root','hips','spine','chest','head','upperarm.l','lowerarm.l','wrist.l','hand.l','handslot.l','upperarm.r','lowerarm.r','wrist.r','hand.r','handslot.r','upperleg.l','lowerleg.l','foot.l','toes.l','upperleg.r','lowerleg.r','foot.r','toes.r'],
 ['Root','Hips','Spine','Chest','Head','LeftUpperArm','LeftLowerArm','LeftWrist','LeftHand','LeftHandSocket','RightUpperArm','RightLowerArm','RightWrist','RightHand','RightHandSocket','LeftUpperLeg','LeftLowerLeg','LeftFoot','LeftToes','RightUpperLeg','RightLowerLeg','RightFoot','RightToes']))

def read_glb(path: Path) -> tuple[dict,bytes]:
    data = path.read_bytes()
    if data[:4] != b'glTF': raise ValueError('Not a GLB: '+str(path))
    count = struct.unpack_from('<I',data,12)[0]
    document = json.loads(data[20:20+count])
    binary_size = struct.unpack_from('<I',data,20+count)[0]
    return document,data[28+count:28+count+binary_size]

def write_glb(path: Path, document: dict, binary: bytes) -> None:
    document['buffers'] = [{'byteLength':len(binary)}]
    js = json.dumps(document,separators=(',',':')).encode()
    js += b' ' * (-len(js)%4)
    binary += b'\0' * (-len(binary)%4)
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(js)+len(binary))+
                     struct.pack('<I4s',len(js),b'JSON')+js+struct.pack('<I4s',len(binary),b'BIN\0')+binary)

def build_model(source: Path, libraries: list[Path], target: Path) -> dict:
    doc,raw = read_glb(source)
    binary=bytearray(raw)
    names={node.get('name'):i for i,node in enumerate(doc['nodes'])}
    doc['animations']=[]
    found=set()
    max_rest_difference=0.0
    for library in libraries:
        lib,blob=read_glb(library)
        joints=set(i for skin in lib.get('skins',[]) for i in skin['joints'])
        # Meshless libraries may use all named armature descendants without a skin.
        if not joints: joints=set(range(len(lib['nodes'])))
        mapping={i:names[node.get('name')] for i,node in enumerate(lib['nodes']) if node.get('name') in names}
        for i,j in mapping.items():
            if lib['nodes'][i].get('name') not in BONES: continue
            for key,default in [('translation',[0,0,0]),('rotation',[0,0,0,1]),('scale',[1,1,1])]:
                a=lib['nodes'][i].get(key,default); b=doc['nodes'][j].get(key,default)
                delta=min(max(abs(x-y) for x,y in zip(a,b)),max(abs(x+y) for x,y in zip(a,b))) if key=='rotation' else max(abs(x-y) for x,y in zip(a,b))
                max_rest_difference=max(max_rest_difference,delta)
                if delta>0.0002: raise ValueError(f'Incompatible rest {source.name}/{library.name}/{key}/{lib["nodes"][i]["name"]}: {delta}')
        accessor_cache={}
        def copy_accessor(index: int, root_translation: bool=False) -> int:
            cache_key=(index,root_translation)
            if cache_key in accessor_cache: return accessor_cache[cache_key]
            accessor=copy.deepcopy(lib['accessors'][index]); view=copy.deepcopy(lib['bufferViews'][accessor['bufferView']])
            start=view.get('byteOffset',0); chunk=bytearray(blob[start:start+view['byteLength']])
            if root_translation:
                stride=view.get('byteStride',12); offset=accessor.get('byteOffset',0)
                for sample in range(accessor['count']):
                    struct.pack_into('<f',chunk,offset+sample*stride,0.0)
                    struct.pack_into('<f',chunk,offset+sample*stride+8,0.0)
                accessor.pop('min',None);accessor.pop('max',None)
            binary.extend(b'\0'*(-len(binary)%4))
            view['byteOffset']=len(binary);view['buffer']=0
            binary.extend(chunk)
            accessor['bufferView']=len(doc['bufferViews']);doc['bufferViews'].append(view)
            result=len(doc['accessors']);doc['accessors'].append(accessor);accessor_cache[cache_key]=result
            return result
        for original in lib.get('animations',[]):
            keys=[key for key,value in CLIPS.items() if value==original['name']]
            if not keys: continue
            key=keys[0]
            if key in found: continue
            animation={'name':key,'samplers':[],'channels':[]}
            for channel in original['channels']:
                source_node=channel['target']['node']
                if source_node not in mapping or lib['nodes'][source_node].get('name') not in BONES: continue
                sampler=copy.deepcopy(original['samplers'][channel['sampler']])
                sampler['input']=copy_accessor(sampler['input'])
                root_translation=lib['nodes'][source_node].get('name')=='root' and channel['target']['path']=='translation'
                sampler['output']=copy_accessor(sampler['output'],root_translation)
                new_channel=copy.deepcopy(channel);new_channel['target']['node']=mapping[source_node];new_channel['sampler']=len(animation['samplers'])
                animation['samplers'].append(sampler);animation['channels'].append(new_channel)
            doc['animations'].append(animation);found.add(key)
    if found!=set(CLIPS): raise ValueError('Missing clips '+str(set(CLIPS)-found))
    for node in doc['nodes']:
        if node.get('name') in BONES: node['name']=BONES[node['name']]
    doc['asset']['extras']={'source':'Kay Lousberg, Adventurers 2.0 FREE + Character Animations 1.1 FREE; CC0',
                          'adaptation':f'Selected {len(found)} clips, matched rests, standard bone names, horizontal root motion removed.'}
    write_glb(target,doc,bytes(binary))
    return dict(file=target.name,source=source.name,clips=sorted(found),rest_max_error=max_rest_difference,
                bytes=target.stat().st_size,sha256=hashlib.sha256(target.read_bytes()).hexdigest())

def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets',type=Path,required=True)
    parser.add_argument('--samples',action='store_true')
    args=parser.parse_args()
    for name, expected in {'kaykit2.zip':'abe48f4763fba0896bab486ee9e6d08ca6b5b3884b9601f235c8847ae94dc479','kaykit-animations1.1.zip':'65882f31f905ad2e953819648a59287cdeab8f623908d5ef701971d3758be20f'}.items():
        if hashlib.sha256((args.assets/name).read_bytes()).hexdigest()!=expected:
            raise SystemExit('Input differs from reviewed free version: '+name)
    model_root=next((args.assets/'kaykit2').glob('*/Characters/gltf'))
    anim_root=next((args.assets/'kaykit-animations1.1').glob('*/Animations/gltf/Rig_Medium'))
    libs=[anim_root/('Rig_Medium_'+category+'.glb') for category in ['General','MovementBasic','CombatMelee','CombatRanged','Simulation']]
    models=['Knight','Ranger','Mage'] if args.samples else ['Knight','Ranger','Mage','Rogue','Rogue_Hooded','Barbarian']
    records=[build_model(model_root/(name+'.glb'),libs,OUT/(name.lower()+'.glb')) for name in models]
    print(json.dumps(records,indent=2))
    (OUT/'build-manifest.json').write_text(json.dumps(records,indent=2)+'\n',encoding='utf-8')
    weapons=model_root.parent.parent/'Assets/gltf'
    for name in ['sword_1handed','shield_round','staff','bow_withString','arrow_bow','crossbow_2handed','arrow_crossbow']:
        source=weapons/(name+'.gltf')
        document=json.loads(source.read_text())
        for data in document.get('buffers',[])+document.get('images',[]):
            if 'uri' in data: shutil.copy2(weapons/data['uri'],OUT/data['uri'])
        shutil.copy2(source,OUT/source.name)
if __name__=='__main__': main()
