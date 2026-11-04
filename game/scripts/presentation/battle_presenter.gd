extends Node
## Sequential visual replay of immutable settled events. Never calls battle/domain methods.
signal finished
signal feedback_changed
signal started
var view: Node3D
var queue: Array = []
var seen: Dictionary = {}
var playing = false
var generation = 0
var contact_records: Array = []
var event_order: Array = []
var tweens: Array[Tween] = []
var visible_ids: Dictionary = {}
var active_event: Dictionary = {}

func enqueue(events: Array) -> void:
	for event in events:
		var id = str(event.get("event_id",""))
		if id!="" and seen.has(id): continue
		if id!="": seen[id] = true
		visible_ids[str(event.get("actor",""))] = true
		for target in event.get("targets",[]): visible_ids[str(target)] = true
		queue.append(event.duplicate(true))
	if not queue.is_empty() and not playing:
		playing = true
		active_event = queue[0]
		call_deferred("_play_queue",generation)

func cancel() -> void:
	generation += 1
	queue.clear()
	visible_ids.clear()
	seen.clear()
	playing = false
	for tween in tweens:
		if tween!=null and tween.is_valid(): tween.kill()
	tweens.clear()
	contact_records.clear()
	event_order.clear()
	active_event.clear()

func _wait(seconds: float, token: int) -> bool:
	await get_tree().create_timer(maxf(0.01,seconds)).timeout
	return token==generation and view.battle_mode

func _play_queue(token: int) -> void:
	while token==generation and not queue.is_empty():
		var event = queue.pop_front()
		active_event = event
		started.emit()
		event_order.append(event.get("event_id",event.get("skill_id","")))
		await _play_event(event,token)
	if token!=generation: return
	playing = false
	active_event = {}
	tweens.clear()
	visible_ids.clear()
	view.sync_battle_states()
	finished.emit()

func _point(id: String) -> Vector3:
	if not view.battle_dolls.has(id): return Vector3.ZERO
	var doll = view.battle_dolls[id]
	var height = 0.55 if doll.family=="spider" else 0.7 if doll.family=="quadruped" else 1.0
	return doll.body.global_position + Vector3.UP*height

func _play_event(event: Dictionary, token: int) -> void:
	var actor_id = str(event.get("actor",""))
	var actor = view.battle_dolls.get(actor_id)
	var skill = str(event.get("skill_id",""))
	var results: Array = event.get("results",[])
	var positive = "heal" in event.get("effects",[]) or "shield" in event.get("effects",[]) or event.kind=="heal"
	for result in results:
		if result.get("healing",0)>0 or result.get("shield_gain",0)>0 or result.get("mp_gain",0)>0: positive = true
	if event.kind=="guard":
		view.sound_cue.emit("shield")
		if actor:
			actor.play_action("guard",0.55)
			view.effects.number(_point(actor_id)+Vector3.UP*0.5,"防守",Color("d9d7ae"))
		await _wait(0.55,token)
		return
	if skill=="enemy_charge":
		view.sound_cue.emit("bow")
		if actor: actor.play_action("aim",0.6)
		await _wait(0.6,token)
		return
	var primary = ""
	for id in event.get("targets",[]):
		if view.battle_dolls.has(id): primary = str(id); break
	var role = actor.rigged.role if actor and actor.rigged else "melee"
	var melee = actor!=null and primary!="" and not positive and role in ["melee","wolf","beast","spider","swarm"] and event.get("element","normal")=="normal" and event.kind!="environment"
	var home = actor.body.global_position if actor else Vector3.ZERO
	var facing = actor.rotation.y if actor else 0.0
	var total_duration = 1.5 if event.kind=="ultimate" else 0.85
	var impact_time = 0.65 if event.kind=="ultimate" else 0.42
	if not positive and event.kind!="ultimate" and role in ["bow","crossbow","magic"]: impact_time=0.52
	var contact_time = 0.0
	var clip_length = 0.0
	var contact_clip = "attack_heavy" if skill=="dawn_strike" else "attack_melee"
	if melee:
		var direction = (_point(primary)-actor.global_position)
		direction.y = 0
		direction = direction.normalized()
		actor.rotation.y = atan2(direction.x,direction.z)
		var destination = _point(primary)-direction*0.15
		if actor.rigged:
			var target = view.battle_dolls[primary]
			var ceiling = target.body.global_position.y + (1.8 if target.family=="humanoid" else 0.85 if target.family=="spider" else 1.25)
			var sample = actor.rigged.sample_melee_contact(contact_clip,ceiling)
			contact_time = sample.time
			clip_length = sample.length
			var offset = actor.body.global_basis*sample.tip
			destination -= offset
			actor.rigged.animator.play(sample.clip,0.04,contact_time/impact_time)
			actor.rigged.action = "attack"
		else:
			destination -= direction*0.55
			actor.play_action("attack",0.75)
		destination.y = home.y
		var approach = actor.body.create_tween()
		tweens.append(approach)
		approach.tween_property(actor.body,"global_position",destination,impact_time*0.72).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	elif actor:
		actor.play_action("rally" if skill=="rally" else "ultimate" if event.kind=="ultimate" else "heal" if positive else "attack" if event.kind=="attack" else "cast",total_duration*0.8)
	if not await _wait(impact_time-0.22 if not melee else impact_time,token): return
	if event.kind=="ultimate":
		view.sound_cue.emit({"rally":"shield","dawn_strike":"impact","arrow_rain":"bow","warmth":"heal","wolf_howl":"howl","sunfall":"fire","tide_shelter":"water"}.get(skill,"cast"))
		var points: Array = []
		for id in event.get("targets",[]): points.append(_point(str(id)))
		view.effects.ultimate_start(skill,_point(actor_id),points)
	if not melee:
		if not positive and event.kind!="ultimate" and event.kind!="environment":
			for id in event.get("targets",[]):
				var start = actor.rigged.emission_point_global() if actor and actor.rigged else _point(actor_id)
				view.effects.projectile(start,_point(str(id)),role,str(event.get("element","normal")),0.22)
			view.sound_cue.emit("bow" if role in ["bow","crossbow"] else str(event.get("element","cast")))
		elif event.kind=="environment":
			for id in event.get("targets",[]): view.effects.burst(_point(str(id))-Vector3.UP*0.5,"flame_01",Color("f39d54"),8,0.4)
		if not await _wait(0.22,token): return
	if melee and actor.rigged:
		actor.rigged.animator.seek(contact_time,true)
		actor.rigged.animator.pause()
		var tip = actor.rigged.weapon_tip_global()
		var target_point = _point(primary)
		var error = Vector2(tip.x-target_point.x,tip.z-target_point.z).length()
		contact_records.append({"actor":actor_id,"target":primary,"clip":contact_clip,"error":error,"tip":tip,"target_point":target_point,"home":home,"contact_body":actor.body.global_position})
	for result in results:
		var id = str(result.target)
		if not view.battle_dolls.has(id): continue
		var target = view.battle_dolls[id]
		view.effects.impact(event,result,_point(id))
		if result.get("damage",0)>0:
			if id!=actor_id: target.play_action("hit",0.3)
			if result.get("hp_after",1)<=0: target.set_down(true)
		elif (result.get("healing",0)>0 or result.get("shield_gain",0)>0) and id!=actor_id:
			if result.get("hp_before",1)<=0 and result.get("hp_after",0)>0: target.set_down(false)
		view.display_results[id] = result.duplicate(true)
	if melee: view.sound_cue.emit("impact")
	elif positive and event.kind!="ultimate": view.sound_cue.emit("heal" if "heal" in event.get("effects",[]) else "shield")
	if not positive and not results.is_empty(): view.impact_camera(0.075 if event.kind=="ultimate" else 0.025)
	view.sync_event_environment(event)
	feedback_changed.emit()
	if melee:
		if actor.rigged:
			if not await _wait(0.055,token): return
			actor.rigged.animator.play(contact_clip,0.0,maxf(0.01,(clip_length-contact_time)/0.25))
			actor.rigged.animator.seek(contact_time,true)
		if not await _wait(0.24,token): return
		var retreat = actor.body.create_tween()
		tweens.append(retreat)
		retreat.tween_property(actor.body,"global_position",home,0.25).set_trans(Tween.TRANS_SINE)
		if not await _wait(0.25,token): return
		actor.body.position = Vector3.ZERO
		actor.rotation.y = facing
		if not actor.down: actor.play_action("idle")
	else:
		if not await _wait(maxf(0.15,total_duration-impact_time),token): return
		if actor and not actor.down: actor.play_action("idle")
