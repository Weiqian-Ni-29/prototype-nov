"""Blender 4.5 script: adapt crownjoshua's CC0 wolf and author complete FK clips.
Run blender --background --factory-startup --disable-autoexec --python this.py -- --assets DIR.
Only data is read from the downloaded .blend; embedded scripts/drivers are not executed.
"""
import bpy, math, sys, argparse, hashlib
from pathlib import Path
from mathutils import Vector, Matrix

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'game/assets/characters'

def material(name,color,metallic=0.0):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    shader=m.node_tree.nodes.get('Principled BSDF');shader.inputs['Base Color'].default_value=(*color,1)
    shader.inputs['Roughness'].default_value=.83;shader.inputs['Metallic'].default_value=metallic
    return m

def attach_mesh(obj,arm,bone):
    # Skinned rigid detail, rather than an external pose driver.
    group=obj.vertex_groups.new(name=bone);group.add(list(range(len(obj.data.vertices))),1.0,'REPLACE')
    mod=obj.modifiers.new('Skin','ARMATURE');mod.object=arm
    obj.parent=arm;obj.matrix_parent_inverse=arm.matrix_world.inverted()

def pose_segment(arm,name,start,end):
    bone=arm.data.bones[name]
    original=bone.tail_local-bone.head_local
    rotation=original.rotation_difference(end-start).to_matrix()@bone.matrix_local.to_3x3()
    transform=rotation.to_4x4();transform.translation=start
    arm.pose.bones[name].matrix=transform

def planted_leg(arm,chain,goal):
    bpy.context.view_layer.update()
    points=[arm.pose.bones[chain[0]].head.copy()]
    points.extend(arm.data.bones[name].tail_local.copy() for name in chain)
    lengths=[arm.data.bones[name].length for name in chain]
    anchor=points[0].copy()
    reach=sum(lengths)*.998
    if (goal-anchor).length>reach:goal=anchor+(goal-anchor).normalized()*reach
    for _ in range(16):
        points[-1]=goal.copy()
        for i in range(len(chain)-1,-1,-1):points[i]=points[i+1]+(points[i]-points[i+1]).normalized()*lengths[i]
        points[0]=anchor.copy()
        for i in range(len(chain)):points[i+1]=points[i]+(points[i+1]-points[i]).normalized()*lengths[i]
    for i,name in enumerate(chain):pose_segment(arm,name,points[i],points[i+1])
    for child in arm.data.bones[chain[-1]].children:
        if 'paw' in child.name.lower():
            pose_segment(arm,child.name,points[-1],points[-1]+child.tail_local-child.head_local)
    bpy.context.view_layer.update()

def foot_cycle(rest,phase,stride,lift):
    t=phase%1.0;goal=rest.copy()
    if t<.6:goal.y+=stride*(t-.3)
    else:
        swing=(t-.6)/.4;goal.y+=stride*(.3-.6*swing);goal.z+=math.sin(swing*math.pi)*lift
    return goal

def wolf(asset_root):
    source=asset_root/'wolf-1/Wolf/Rigged/Wolf.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False,use_scripts=False)
    old_arm=bpy.data.objects['Armature'];mesh=bpy.data.objects['Wolf']
    bpy.context.view_layer.update()
    # Rebind in world space: the legacy Blender 2.x parent inverse is unsuitable for glTF skins.
    rest={b.name:((old_arm.matrix_world@b.head_local)*.32,(old_arm.matrix_world@b.tail_local)*.32,b.parent.name if b.parent else None,b.matrix_local.to_3x3().col[2].copy()) for b in old_arm.data.bones}
    matrix=mesh.matrix_world.copy();mesh.parent=None;mesh.matrix_world=matrix
    for modifier in list(mesh.modifiers):
        if modifier.type=='ARMATURE':mesh.modifiers.remove(modifier)
    bpy.context.view_layer.objects.active=mesh
    bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True)
    for modifier in list(mesh.modifiers):bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    for vertex in mesh.data.vertices:vertex.co*=.32
    for vertex in mesh.data.vertices:
        influences=sorted([(g.group,max(0.0,min(1.0,g.weight))) for g in vertex.groups],key=lambda pair:pair[1],reverse=True)
        for group,_ in influences:mesh.vertex_groups[group].remove([vertex.index])
        total=sum(weight for _,weight in influences[:4])
        for group,weight in influences[:4]:
            if total>0:mesh.vertex_groups[group].add([vertex.index],weight/total,'REPLACE')
    mesh.data.validate(verbose=True,clean_customdata=True)
    for o in list(bpy.data.objects):
        if o!=mesh:bpy.data.objects.remove(o,do_unlink=True)
    data=bpy.data.armatures.new('WolfRig');arm=bpy.data.objects.new('WolfRig',data);bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active=arm;mesh.select_set(False);arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for name,(head,tail,parent,z_axis) in rest.items():
        bone=data.edit_bones.new(name);bone.head=head;bone.tail=tail;bone.align_roll(z_axis)
    for name,(_,_,parent,_) in rest.items():
        if parent:data.edit_bones[name].parent=data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    for bone in arm.pose.bones:bone.rotation_mode='XYZ'
    modifier=mesh.modifiers.new('Skin','ARMATURE');modifier.object=arm
    mesh.parent=arm
    bpy.context.view_layer.update()
    for driver in list(arm.animation_data.drivers) if arm.animation_data else []:arm.driver_remove(driver.data_path)
    mesh.data.materials.clear();mesh.data.materials.append(material('Wolf silver fur',(.45,.49,.47)))
    for polygon in mesh.data.polygons:polygon.use_smooth=False
    # Add eyes, nose, a physical collar and the story's engraved ring.
    head=arm.data.bones['Head'];center=arm.matrix_world@head.head_local
    for side in [-1,1]:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=10,ring_count=6,radius=.027,location=center+Vector((side*.109,-.096,.038)))
        obj=bpy.context.object;obj.name='AmberEye';obj.data.materials.append(material('Amber',(.9,.53,.12)))
        attach_mesh(obj,arm,'Head')
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10,ring_count=6,radius=.051,location=center+Vector((0,-.285,-.109)))
    nose=bpy.context.object;nose.name='Nose';nose.scale=(1,.8,.7);nose.data.materials.append(material('Nose charcoal',(.045,.055,.05)));attach_mesh(nose,arm,'Head')
    bpy.ops.mesh.primitive_torus_add(major_segments=16,minor_segments=5,location=center+Vector((0,.18,-.1)),rotation=(math.pi/2,0,0),major_radius=.17,minor_radius=.022)
    collar=bpy.context.object;collar.name='Engraved collar';collar.data.materials.append(material('Old brass',(.51,.36,.14),.4));attach_mesh(collar,arm,'neck Top')
    # Export all objects under a common normalization node, keeping skin inverse binds intact.
    model=bpy.data.objects.new('Model',None);bpy.context.collection.objects.link(model)
    for obj in list(bpy.context.scene.objects):
        if obj!=model and obj.parent is None:obj.parent=model
    model.scale=(1,1,1)
    bpy.context.scene.render.fps=24
    for action in list(bpy.data.actions):bpy.data.actions.remove(action)
    bones=arm.pose.bones
    names=['idle','walk','run','attack_melee','attack_heavy','cast','support','channel','guard','hit','down','item','rally']
    for name in names:
        action=bpy.data.actions.new(name);action.use_fake_user=True
        arm.animation_data_create();arm.animation_data.action=action
        frames=32 if name in ['idle','walk','run','channel'] else 30
        for step in range(17):
            t=step/16;frame=1+round(t*frames);phase=t*math.tau
            bpy.context.scene.frame_set(frame)
            for bone in bones:bone.location=(0,0,0);bone.rotation_euler=(0,0,0)
            pulse=math.sin(math.pi*t)
            if name in ['idle','channel']:
                bones['thoracic'].rotation_euler.x=math.sin(phase)*.018
                bones['Head'].rotation_euler.z=math.sin(phase)*.035
            if name in ['walk','run']:
                strength=.38 if name=='walk' else .65
                for index,side in enumerate(['L','R']):
                    offset=index*math.pi
                    stride=math.sin(phase+offset)
                    bones['front humerus.'+side].rotation_euler.x=stride*strength
                    bones['front metacarpals.'+side].rotation_euler.x=max(0,-stride)*.55
                    bones['femur.'+side].rotation_euler.x=-stride*strength
                    bones['tarsals.'+side].rotation_euler.x=max(0,stride)*.65
                    bones['back metacarpals.'+side].rotation_euler.x=-max(0,stride)*.35
                bones['Root'].location.z=(-.03 if name=='walk' else -.075)+abs(math.sin(phase*2))*.018
                bones['neck base'].rotation_euler.x=math.sin(phase*2)*.035
            elif name in ['attack_melee','attack_heavy']:
                bones['Root'].location.y=pulse*(.16 if name=='attack_heavy' else .096)
                bones['thoracic'].rotation_euler.x=-pulse*.15
                bones['Head'].rotation_euler.x=pulse*.32
                for side in ['L','R']:
                    bones['front humerus.'+side].rotation_euler.x=-pulse*.35
                    bones['front metacarpals.'+side].rotation_euler.x=pulse*.3
            elif name in ['cast','support','rally']:
                bones['neck base'].rotation_euler.x=-pulse*.3
                bones['neck Top'].rotation_euler.x=-pulse*.3
                bones['Head'].rotation_euler.x=-pulse*.35
                bones['thoracic'].rotation_euler.x=-pulse*.08
            elif name=='guard':
                bones['thoracic'].location.z=-pulse*.07
                bones['Head'].rotation_euler.x=pulse*.12
                for side in ['L','R']:
                    bones['front humerus.'+side].rotation_euler.x=-pulse*.2
                    bones['front metacarpals.'+side].rotation_euler.x=pulse*.4
            elif name=='hit':
                bones['Root'].location.y=-pulse*.048
                bones['Head'].rotation_euler.z=pulse*.2
            elif name=='down':
                ease=t*t*(3-2*t)
                bones['Root'].rotation_euler.y=ease*1.4
                bones['Root'].location.z=ease*.14
                bones['Head'].rotation_euler.x=ease*.25
                for side in ['L','R']:
                    bones['front humerus.'+side].rotation_euler.x=-ease*.4
                    bones['front metacarpals.'+side].rotation_euler.x=ease*.9
                    bones['femur.'+side].rotation_euler.x=ease*.6
            elif name=='item':bones['Head'].rotation_euler.x=pulse*.35
            for index,tail in enumerate(['Tail Base','Tail Middle 1','Tail middle 2','Tail tip']):
                bones[tail].rotation_euler.z=math.sin(phase+index*.4)*(.03 if name=='down' else .09)
            if name in ['walk','run']:
                chains=[(['front humerus.L','front metacarpals.L'],0.0),(['front humerus.R','front metacarpals.R'],.5),(['femur.L','tarsals.L','back metacarpals.L'],.75),(['femur.R','tarsals.R','back metacarpals.R'],.25)]
                for chain,offset in chains:
                    rest=arm.data.bones[chain[-1]].tail_local
                    planted_leg(arm,chain,foot_cycle(rest,t+offset,.5 if name=='walk' else .85,.08 if name=='walk' else .13))
            for bone in bones:
                bone.keyframe_insert('location',frame=frame,group=bone.name)
                bone.keyframe_insert('rotation_euler',frame=frame,group=bone.name)
        action['source']='Original animation adaptation for the CC0 crownjoshua wolf; project contribution.'
    arm.animation_data.action=None
    # Keep only mesh + skeleton; no external IK curves, drivers, camera or code enters the GLB.
    bpy.ops.object.select_all(action='SELECT')
    OUT.mkdir(parents=True,exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/'wolf.glb'),export_format='GLB',use_selection=True,
                             export_animations=True,export_animation_mode='ACTIONS',
                             export_force_sampling=True,export_anim_single_armature=True,
                             export_frame_range=False,export_skins=True)
    print('CREATURE BUILT',OUT/'wolf.glb')

def creature(kind):
    """Original faceted meshes, full animal/insect skeletons and baked clips; no external mesh."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    data=bpy.data.armatures.new(kind+'Rig');arm=bpy.data.objects.new('Rig',data);bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active=arm;arm.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
    definitions=[];parts=[];chains=[]
    def bone(name,head,tail,parent='Root'):
        b=data.edit_bones.new(name);b.head=head;b.tail=tail
        if parent and parent in data.edit_bones:b.parent=data.edit_bones[parent]
        definitions.append(name)
    bone('Root',(0,0,0),(0,-.1,0),None)
    body_color=(.36,.29,.17) if kind=='boar' else (.18,.38,.32) if kind=='lurker' else (.19,.32,.16) if kind=='spider' else (.77,.48,.08)
    base=material(kind+' shell',body_color);dark=material('Dark',(.06,.085,.065));ivory=material('Bone',(.8,.72,.46));eye=material('Amber eyes',(.94,.47,.08));wing=material('Wing',(.58,.7,.65))
    def ellipsoid(name,point,scale,bone_name,mat=base,subdivision=2):
        parts.append(('sphere',name,point,scale,bone_name,mat,subdivision))
    def segment(name,start,end,radius1,radius2,bone_name,mat=base):
        parts.append(('segment',name,start,end,bone_name,mat,(radius1,radius2)))
    if kind in ['boar','lurker']:
        height=.82 if kind=='boar' else .48
        bone('Spine',(0,.35,height),(0,-.22,height+.06))
        bone('Chest',(0,-.22,height+.06),(0,-.55,height+.1),'Spine')
        bone('Head',(0,-.55,height+.1),(0,-1.0,height),'Chest')
        bone('Jaw',(0,-.72,height-.12),(0,-1.02,height-.13),'Head')
        bone('Tail',(0,.53,height),(0,.94,height+.1),'Spine')
        ellipsoid('Ribcage',(0,.02,height),(.39,.72,.42 if kind=='boar' else .26),'Spine')
        ellipsoid('Shoulders',(0,-.35,height),(.38,.36,.43 if kind=='boar' else .27),'Chest')
        ellipsoid('Skull',(0,-.7,height+.04),(.27,.37,.29),'Head')
        ellipsoid('Muzzle',(0,-.98,height-.06),(.21,.22,.16),'Head',dark if kind=='boar' else base)
        ellipsoid('LowerJaw',(0,-.91,height-.2),(.19,.22,.055),'Jaw')
        segment('Tail',(0,.58,height),(0,.98,height+.09),.085,.025,'Tail')
        for side in [-1,1]:
            ellipsoid('Eye',(side*.23,-.87,height+.16),(.045,.055,.045),'Head',eye,1)
            if kind=='boar':segment('Ear',(side*.2,-.61,height+.18),(side*.31,-.57,height+.47),.12,.01,'Head')
            if kind=='boar':
                segment('Tusk',(side*.19,-1.02,height-.18),(side*.3,-1.08,height+.05),.045,.005,'Jaw',ivory)
            else:
                for i in range(3):segment('Gill',(side*.34,-.22+i*.13,height),(side*.52,-.19+i*.13,height+.08),.075,.008,'Chest',ivory)
        for i in range(5):segment('Crest',(0,-.34+i*.18,height+.3),(0,-.34+i*.18,height+.53),.08,.006,'Spine',ivory)
        for index,(side,y) in enumerate([(-1,-.43),(1,-.43),(-1,.43),(1,.43)]):
            hip=(side*.29,y,height-.12)
            knee=(side*.32,y+(.08 if y<0 else .12),.35 if kind=='boar' else .24)
            foot=(side*.34,y-.02,.08)
            suffix=str(index);upper='Upper'+suffix;lower='Lower'+suffix;paw='Paw'+suffix
            bone(upper,hip,knee,'Chest' if y<0 else 'Spine');bone(lower,knee,foot,upper);bone(paw,foot,(foot[0],foot[1]-.16,.055),lower)
            segment('Haunch',hip,knee,.13,.1,upper);segment('Shin',knee,foot,.085,.065,lower)
            ellipsoid('Knee',knee,(.1,.11,.11),lower)
            ellipsoid('Hoof',foot,(.105,.15,.08),paw,dark,1)
            chains.append(([upper,lower],index*.25))
    elif kind=='spider':
        bone('Thorax',(0,0,.54),(0,-.3,.54));bone('Abdomen',(0,.08,.55),(0,.62,.67),'Thorax');bone('Head',(0,-.29,.54),(0,-.58,.52),'Thorax')
        ellipsoid('Faceted Abdomen',(0,.45,.65),(.4,.51,.33),'Abdomen')
        ellipsoid('Thorax',(0,-.02,.53),(.28,.33,.23),'Thorax',dark)
        ellipsoid('Face',(0,-.42,.53),(.22,.23,.18),'Head')
        for side in [-1,1]:
            for i in range(3):ellipsoid('Eye',(side*(.06+i*.052),-.57,.59+(i%2)*.045),(.027,.04,.034),'Head',eye,1)
            name='Fang'+str(side);bone(name,(side*.09,-.54,.44),(side*.13,-.72,.29),'Head')
            segment('Fang',(side*.09,-.54,.44),(side*.13,-.72,.29),.045,.008,name,ivory)
            for i in range(4):
                root=(side*.22,-.3+i*.2,.53)
                knee=(side*(.58+(.08 if i in [1,2] else 0)),(i-1.5)*.37,.7)
                ankle=(side*(.79+(.07 if i in [1,2] else 0)),(i-1.5)*.48,.065)
                upper='Upper%d_%d'%(side,i);lower='Lower%d_%d'%(side,i);paw='Paw%d_%d'%(side,i)
                toe=(ankle[0]+side*.08,ankle[1],-.015)
                bone(upper,root,knee,'Thorax');bone(lower,knee,ankle,upper);bone(paw,ankle,toe,lower)
                segment('Femur',root,knee,.066,.046,upper);segment('Tibia',knee,ankle,.046,.015,lower)
                segment('Toe',ankle,toe,.016,.005,paw)
                ellipsoid('Joint',knee,(.063,.069,.065),lower,base,1)
                chains.append(([upper,lower],(i%2)*.5+(0 if side==1 else .5)))
        for i in range(3):segment('Abdomen Mark',(0,.24+i*.17,.9),(0,.24+i*.17,.99),.065,.01,'Abdomen',ivory)
    else:
        bone('Swarm',(0,0,.75),(0,-.15,.75))
        for index in range(3):
            x=(index-1)*.37;y=(index%2)*.33;z=.82+(index%2)*.24
            name='Bee'+str(index);bone(name,(x,y,z),(x,y-.32,z),'Swarm')
            bone('Head'+str(index),(x,y-.2,z),(x,y-.34,z),name)
            ellipsoid('Bee Body',(x,y,z),(.15,.27,.15),name)
            ellipsoid('Bee Head',(x,y-.27,z),(.13,.13,.13),'Head'+str(index),dark)
            for offset in [-.08,.07]:ellipsoid('Stripe',(x,y+offset,z),(.153,.04,.153),name,dark,1)
            for side in [-1,1]:
                w='Wing%d_%d'%(index,side);bone(w,(x+side*.08,y,z+.08),(x+side*.38,y+.04,z+.15),name)
                ellipsoid('Wing',(x+side*.27,y+.05,z+.11),(.27,.1,.018),w,wing,1)
                ellipsoid('Eye',(x+side*.07,y-.37,z+.025),(.027,.027,.027),'Head'+str(index),eye,1)
            segment('Stinger',(x,y+.21,z),(x,y+.42,z-.04),.045,.002,name,ivory)
    bpy.ops.object.mode_set(mode='OBJECT')
    for entry in parts:
        shape,name,a,b,bone_name,mat,extra=entry
        if shape=='sphere':
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=extra,radius=1,location=a)
            obj=bpy.context.object;obj.scale=b
        else:
            start,end=Vector(a),Vector(b);delta=end-start
            bpy.ops.mesh.primitive_cone_add(vertices=8,radius1=extra[0],radius2=extra[1],depth=delta.length,location=(start+end)/2)
            obj=bpy.context.object;obj.rotation_euler=delta.to_track_quat('Z','Y').to_euler()
        obj.name=name;obj.data.materials.append(mat)
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        attach_mesh(obj,arm,bone_name)
    bpy.context.scene.render.fps=24
    arm.animation_data_create()
    for clip in ['idle','walk','run','attack_melee','attack_heavy','cast','support','channel','guard','hit','down','item','rally']:
        action=bpy.data.actions.new(clip);action.use_fake_user=True;arm.animation_data.action=action
        for step in range(25):
            t=step/24;phase=t*math.tau;pulse=math.sin(math.pi*t);frame=1+step
            bpy.context.scene.frame_set(frame)
            for b in arm.pose.bones:b.rotation_mode='XYZ';b.rotation_euler=(0,0,0);b.location=(0,0,0)
            body_bone='Spine' if kind in ['boar','lurker'] else 'Thorax' if kind=='spider' else 'Swarm'
            arm.pose.bones[body_bone].location.z=math.sin(phase)*.012
            if kind=='swarm':
                for index in range(3):
                    arm.pose.bones['Bee'+str(index)].location.z=math.sin(phase+index*1.2)*.07
                    for side in [-1,1]:arm.pose.bones['Wing%d_%d'%(index,side)].rotation_euler.y=math.sin(phase*6)*.65*side
            if clip in ['walk','run']:
                arm.pose.bones['Root'].location.z=-.035+abs(math.sin(phase*2))*.012
                for chain,offset in chains:
                    rest=data.bones[chain[-1]].tail_local
                    planted_leg(arm,chain,foot_cycle(rest,t+offset,.32 if kind=='spider' else .42,.08))
            elif clip.startswith('attack'):
                arm.pose.bones[body_bone].rotation_euler.x=-pulse*.2
                if 'Head' in arm.pose.bones:arm.pose.bones['Head'].rotation_euler.x=pulse*.3
                if 'Jaw' in arm.pose.bones:arm.pose.bones['Jaw'].rotation_euler.x=pulse*.35
                if kind=='spider':
                    for side in [-1,1]:arm.pose.bones['Fang'+str(side)].rotation_euler.x=pulse*.45
                if kind=='swarm':arm.pose.bones['Swarm'].rotation_euler.x=-pulse*.35
            elif clip in ['cast','support','rally','channel']:
                arm.pose.bones[body_bone].location.z=pulse*.07
                arm.pose.bones[body_bone].rotation_euler.x=-pulse*.15
            elif clip=='guard':arm.pose.bones[body_bone].location.z=-pulse*.09
            elif clip=='hit':arm.pose.bones[body_bone].rotation_euler.z=pulse*.18
            elif clip=='down':
                ease=t*t*(3-2*t);arm.pose.bones['Root'].rotation_euler.y=ease*1.1;arm.pose.bones['Root'].location.z=ease*.12
                if kind=='spider':
                    arm.pose.bones['Root'].rotation_euler.y=ease*math.pi;arm.pose.bones['Root'].location.z=ease*.96
                if kind=='swarm':
                    arm.pose.bones['Root'].rotation_euler.y=0
                    for index in range(3):
                        arm.pose.bones['Bee'+str(index)].location.z=-ease*(.82+(index%2)*.24-.15)
                        arm.pose.bones['Bee'+str(index)].rotation_euler.y=ease*(1.0+index*.2)
                for name in definitions:
                    if name.startswith('Lower'):arm.pose.bones[name].rotation_euler.x=ease*.7
            for b in arm.pose.bones:
                b.keyframe_insert('location',frame=frame,group=b.name);b.keyframe_insert('rotation_euler',frame=frame,group=b.name)
    arm.animation_data.action=None
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(OUT/(kind+'.glb')),export_format='GLB',use_selection=True,
                             export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,
                             export_anim_single_armature=True,export_frame_range=False,export_skins=True)
    print('ORIGINAL CREATURE BUILT',kind)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--assets',type=Path,required=True);parser.add_argument('--all',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    if hashlib.sha256((args.assets/'wolf-1.zip').read_bytes()).hexdigest()!='6cc13fea5f2a84956dd213c4ae9bc3550ee3f0aed3776968cc70132302c06798':
        raise SystemExit('Wolf input differs from the reviewed author upload')
    wolf(args.assets.resolve())
    if args.all:
        for kind in ['boar','lurker','spider','swarm']:creature(kind)
