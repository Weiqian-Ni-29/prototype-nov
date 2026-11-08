class_name Battle
extends RefCounted
const Catalog = preload("res://scripts/domain/catalog.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
const Nodes = preload("res://scripts/domain/map_nodes.gd")
var run: RefCounted
var position = ""
var active: Array[String] = []
var enemies: Dictionary = {}
var paid: Dictionary = {}
var next_time: Dictionary = {}
var queue: Array = []
var clock = 0.0
var fire_tick = 10.0
var current = ""
var outcome = ""
var auto_mode = false
var pending: Dictionary = {}
var events: Array = []
var event_serial = 0

static func can_deploy(actor: Dictionary, encounter: Dictionary) -> bool:
	return actor.ap >= Catalog.BATTLE_AP or encounter.get("ambush", false) or encounter.get("surprise", false)

func begin(expedition: RefCounted, encounter: Dictionary, formation: Array) -> Dictionary:
	if expedition.data.status != "exploring" or formation.is_empty() or formation.size() > 4:
		return {"ok": false, "message": "请选择一至四名同格角色。"}
	position = encounter.position
	var unique = {}
	for id in formation:
		var a = expedition.actor(id)
		if unique.has(id) or a.is_empty() or not a.joined or a.position != position or a.hp <= 0:
			return {"ok": false, "message": "出战角色须健康、同地且不重复。"}
		if not can_deploy(a, encounter):
			return {"ok": false, "message": "%s 参战精力不足。" % a.name}
		unique[id] = true
	run = expedition
	pending = encounter.duplicate(true)
	run.data.pending_battle = pending.duplicate(true)
	# The stable checkpoint precedes the one-time deployment charges.
	var saved = run.save_game()
	if not saved.ok:
		return saved
	active.clear()
	enemies.clear()
	paid.clear()
	next_time.clear()
	queue.clear()
	events.clear()
	event_serial = 0
	clock = 0.0
	fire_tick = 10.0
	outcome = ""
	current = ""
	auto_mode = false
	for id in formation:
		active.append(id)
		_deploy(id)
	var npc = str(encounter.get("npc", ""))
	var definitions = run.data.tiles[position].enemies.duplicate()
	if not npc.is_empty():
		definitions = ["npc:" + npc]
	for i in range(definitions.size()):
		var type = definitions[i]
		var e: Dictionary
		if type.begins_with("npc:"):
			e = run.actor(npc).duplicate(true)
			e["hp_max"] = e.hp_max
			e["role"] = "误会中的普通交战 · 需要实际救援"
			e["skill"] = "ignite" if npc == "ember" else "attack"
		else:
			e = Catalog.ENEMIES[type].duplicate(true)
			e["hp_max"] = e.hp
		e["id"] = "enemy_%d" % i
		e["type"] = type
		e["shield"] = 0
		e["slow"] = 0
		e["guard"] = false
		e["charged"] = false
		enemies[e.id] = e
		next_time[e.id] = _delay(e.id) * (0.45 if encounter.get("ambush", false) else 1.0)
	run.data.status = "battle"
	run.data.battles += 1
	run.note("战斗开始；每人仅在本场首次上场支付 %d 精力。" % Catalog.BATTLE_AP)
	seek_next()
	return {"ok": true}

func unit(id: String) -> Dictionary:
	return enemies[id] if enemies.has(id) else run.actor(id)

func alive_allies() -> Array[String]:
	var result: Array[String] = []
	for id in active:
		if unit(id).hp > 0:
			result.append(id)
	return result

func alive_enemies() -> Array[String]:
	var result: Array[String] = []
	for id in enemies:
		if enemies[id].hp > 0:
			result.append(id)
	return result

func reserves() -> Array[String]:
	var result: Array[String] = []
	for id in run.same_cell(position, true):
		if id not in active and (paid.has(id) or can_deploy(run.actor(id), pending)):
			result.append(id)
	return result

func _deploy(id: String) -> void:
	var a = unit(id)
	if not paid.has(id):
		a.ap = maxi(0, int(a.ap) - Catalog.BATTLE_AP)
		a.shield = roundi(a.hp_max * 0.12) if run.has_relic("lamp_badge") else 0
		a.slow = 0
		a.guard = false
		paid[id] = true
	# An incoming character always waits a full personal interval; no swap loop grants turns.
	next_time[id] = clock + _delay(id)

func _delay(id: String) -> float:
	var speed = float(unit(id).speed) if enemies.has(id) else float(run.stat(id, "speed"))
	if unit(id).get("slow", 0) > 0:
		speed *= 0.7
	return 1000.0 / maxf(1.0, speed)

func timeline(limit: int = 7) -> Array:
	var simulated = next_time.duplicate()
	var result: Array = []
	var eligible: Array = alive_allies() + alive_enemies()
	for i in range(limit):
		if eligible.is_empty():
			break
		var best = str(eligible[0])
		for id in eligible:
			if float(simulated[id]) < float(simulated[best]) or (is_equal_approx(simulated[id], simulated[best]) and str(id) < best):
				best = id
		result.append({"id": best, "time": simulated[best]})
		simulated[best] += _delay(best)
	return result

func seek_next() -> void:
	if not outcome.is_empty():
		return
	if check_end():
		return
	var order = timeline(1)
	current = str(order[0].id)
	clock = maxf(clock, float(order[0].time))
	unit(current).guard = false

func act(skill_id: String, target_id: String = "") -> Dictionary:
	if not outcome.is_empty() or current.is_empty() or enemies.has(current):
		return _fail("现在不是己方正常行动。")
	var id = current
	var allowed = ["attack", "guard", str(unit(id).skill)]
	if skill_id not in allowed:
		return _fail("该角色没有这个普通指令。")
	if skill_id == "guard":
		unit(id).guard = true
		unit(id).energy = mini(100, int(unit(id).energy) + 10)
		_log("%s 防守，下次正常行动前减伤。" % unit(id).name)
		_emit_event({"actor":id,"targets":[id],"kind":"guard","skill_id":"guard","element":"normal","results":[]})
	else:
		var result = _cast(id, skill_id, target_id)
		if not result.ok:
			return result
	_complete_action(id)
	return {"ok": true}

func _cast(id: String, skill_id: String, target_id: String, ultimate: bool = false) -> Dictionary:
	var skill = Catalog.SKILLS[skill_id]
	var environment_before = _environment_view()
	var results: Array = []
	var effects: Array = []
	if skill.get("healing",false): effects.append("heal")
	if skill.has("shield"): effects.append("shield")
	if skill.has("power") and not skill.get("healing",false): effects.append("damage")
	var caster = unit(id)
	if caster.hp <= 0 or int(caster.mp) < int(skill.get("mp", 0)):
		return _fail("无法施放：重伤或魔力不足。")
	var targets: Array = []
	match skill.target:
		"enemy":
			if target_id not in alive_enemies():
				return _fail("请选择存活敌人。")
			targets = [target_id]
		"ally":
			if target_id not in active:
				return _fail("请选择当前出战的己方角色。")
			targets = [target_id]
		"all_enemies":
			targets = alive_enemies()
		"all_allies":
			targets = active.duplicate()
	caster.mp -= int(skill.get("mp", 0))
	if ultimate:
		caster.energy = 0
	else:
		caster.energy = mini(100, int(caster.energy) + int(skill.get("energy", 0)))
	for target in targets:
		var t = unit(target)
		var before = _unit_view(t)
		if skill.get("healing", false):
			var was_down = t.hp <= 0
			t.hp = mini(int(t.hp_max), int(t.hp) + int(skill.power))
			if was_down and t.hp > 0:
				next_time[target] = clock + _delay(target)
			_log("%s → %s：恢复 %d HP。" % [caster.name, t.name, skill.power])
		elif skill.has("power") and t.hp > 0:
			var damage = damage_preview(id, target, skill_id)
			_hurt(target, damage)
			if skill.has("slow") and t.hp > 0:
				t.slow = skill.slow
			_log("%s · %s → %s：%d 伤害。" % [caster.name, skill.name, t.name, damage])
		if skill.has("shield") and t.hp > 0:
			t.shield = mini(60, int(t.get("shield", 0)) + int(skill.shield))
			_log("%s 获得护盾。" % t.name)
		results.append(_visual_result(target,before))
	if skill.has("environment"):
		if run.apply_environment(position, skill.environment) and skill.environment == "ignite":
			run.record_ignition(id, position)
	_emit_event({"actor": id, "targets": targets, "kind": "ultimate" if ultimate else "cast" if skill_id != "attack" else "attack", "element": skill.element, "skill": skill.name, "skill_id":skill_id,"effects":effects,"results":results,"environment_before":environment_before,"environment_after":_environment_view()})
	return {"ok": true}

func damage_preview(source: String, target: String, skill_id: String) -> int:
	var skill = Catalog.SKILLS[skill_id]
	var attack_value = run.stat(source, "attack")
	var defense_value = int(unit(target).defense) if enemies.has(target) else run.stat(target, "defense")
	var multiplier = environment_multiplier(str(skill.element), str(unit(target).get("element", "normal")))
	return maxi(1, floori((attack_value * float(skill.get("power", 1.0)) - defense_value * 0.6) * multiplier))

func environment_multiplier(element: String, target_element: String) -> float:
	var multiplier = 1.0
	if element == "water" and target_element == "fire":
		multiplier *= 1.25
	if element == "fire" and target_element == "water":
		multiplier *= 0.8
	var t = run.data.tiles[position]
	if element == "water" and t.terrain == "desert":
		multiplier *= 0.8
	if run.data.weather == "rain":
		if element == "water":
			multiplier *= 1.1
		elif element == "fire":
			multiplier *= 0.8
	if t.burning and element == "fire":
		multiplier *= 1.1
	if t.wet_until > run.data.day and element == "fire":
		multiplier *= 0.8
	return clampf(multiplier, 0.5, 1.5)

func use_item(item: String, target_id: String) -> Dictionary:
	if outcome != "" or enemies.has(current) or current.is_empty() or target_id not in active:
		return _fail("只在我方本人正常行动窗口使用道具，目标须在场。")
	var before = _unit_view(unit(target_id))
	var result = run.use_item(current, target_id, item, true)
	if result.ok:
		if unit(target_id).hp > 0 and float(next_time.get(target_id, 0.0)) < clock:
			next_time[target_id] = clock + _delay(target_id)
		_emit_event({"actor": current, "targets": [target_id], "kind": "heal", "skill_id":"item:"+item,"element": "normal","results":[_visual_result(target_id,before)]})
	return result

func swap(incoming: String) -> Dictionary:
	if outcome != "" or enemies.has(current) or current.is_empty() or incoming not in reserves():
		return _fail("只能在己方正常行动时换入合格同地候补。")
	var outgoing = current
	var index = active.find(outgoing)
	active[index] = incoming
	_deploy(incoming)
	next_time.erase(outgoing)
	_log("%s 换下，%s 上场；换人消耗本次正常行动。" % [unit(outgoing).name, unit(incoming).name])
	current = ""
	_settle_fire()
	resolve_queued()
	seek_next()
	return {"ok": true}

func request_ultimate(id: String, target: String = "") -> Dictionary:
	if outcome != "" or id not in active or unit(id).hp <= 0 or unit(id).energy < Catalog.ENERGY_MAX:
		return _fail("仅在场、存活且满能量的角色能释放终结技。")
	for request in queue:
		if request.id == id:
			return _fail("该终结技已在队列中。")
	var skill = Catalog.SKILLS[unit(id).ultimate]
	if skill.target == "enemy" and target not in alive_enemies():
		return _fail("请选择敌人。")
	if skill.target == "ally" and target not in active:
		return _fail("请选择场上队友。")
	queue.append({"id": id, "target": target})
	return {"ok": true}

func resolve_queued() -> void:
	while not queue.is_empty() and outcome == "":
		var request = queue.pop_front()
		if request.id in active and unit(request.id).hp > 0 and unit(request.id).energy >= 100:
			_cast(request.id, unit(request.id).ultimate, request.target, true)
			check_end()

func step_auto() -> void:
	if outcome != "":
		return
	resolve_queued()
	if outcome != "":
		return
	if current.is_empty():
		seek_next()
	if outcome != "":
		return
	if enemies.has(current):
		_enemy_action(current)
	elif auto_mode:
		for id in active:
			if unit(id).hp > 0 and unit(id).energy >= 100:
				request_ultimate(id)
		resolve_queued()
		if outcome != "":
			return
		var caster = unit(current)
		var skill = Catalog.SKILLS[caster.skill]
		var target = ""
		var lowest_ratio = 2.0
		for id in active:
			var ratio = float(unit(id).hp) / unit(id).hp_max
			if ratio < lowest_ratio:
				lowest_ratio = ratio
				target = id
		var choice = str(caster.skill)
		if caster.mp < skill.mp or (skill.get("healing", false) and lowest_ratio > 0.65):
			choice = "attack"
		if Catalog.SKILLS[choice].target == "enemy":
			target = _weakest(alive_enemies())
		act(choice, target)

func _enemy_action(id: String) -> void:
	var a = enemies[id]
	var target = _weakest(alive_allies())
	match a.skill:
		"heal":
			var patient = _weakest(alive_enemies())
			if unit(patient).hp < unit(patient).hp_max * 0.75:
				var before = _unit_view(unit(patient))
				unit(patient).hp = mini(int(unit(patient).hp_max), int(unit(patient).hp) + 28)
				_log("%s 为 %s 恢复生命。" % [a.name, unit(patient).name])
				_emit_event({"actor":id,"targets":[patient],"kind":"cast","skill_id":"enemy_heal","element":"normal","effects":["heal"],"results":[_visual_result(patient,before)]})
			else:
				_enemy_hit(id, target, 1.0)
		"guard":
			var results: Array = []
			for e in alive_enemies():
				var before = _unit_view(unit(e))
				unit(e).shield = mini(40, int(unit(e).shield) + 10)
				results.append(_visual_result(e,before))
			_emit_event({"actor":id,"targets":alive_enemies(),"kind":"cast","skill_id":"enemy_shield","element":"normal","effects":["shield"],"results":results})
			_enemy_hit(id, target, 0.8)
		"charge":
			if a.charged:
				_enemy_hit(id, target, 2.0)
				a.charged = false
			else:
				a.charged = true
				_log("%s 正在蓄力，下次行动重弩射击！" % a.name)
				_emit_event({"actor":id,"targets":[id],"kind":"cast","skill_id":"enemy_charge","element":"normal","results":[]})
		"slow":
			_enemy_hit(id, target, 1.0)
			unit(target).slow = 2
		"ignite", "wet":
			var environment_before = _environment_view()
			_enemy_hit(id, target, 1.15, "fire" if a.skill == "ignite" else "water")
			run.apply_environment(position, a.skill)
			events[-1].environment_before = environment_before
			events[-1].environment_after = _environment_view()
		_:
			_enemy_hit(id, target, 1.0)
	_complete_action(id)

func _enemy_hit(id: String, target: String, power: float, element: String = "normal") -> void:
	var before = _unit_view(unit(target))
	var damage = maxi(1, floori((unit(id).attack * power - run.stat(target, "defense") * 0.6) * environment_multiplier(element, unit(target).element)))
	_hurt(target, damage)
	_log("%s → %s：%d 伤害。" % [unit(id).name, unit(target).name, damage])
	_emit_event({"actor": id, "targets": [target], "kind": "attack", "skill_id":"enemy_attack","element": element,"results":[_visual_result(target,before)]})

func _unit_view(a: Dictionary) -> Dictionary:
	return {"hp":int(a.hp),"shield":int(a.get("shield",0)),"mp":int(a.get("mp",0))}

func _visual_result(id: String, before: Dictionary) -> Dictionary:
	var after = _unit_view(unit(id))
	return {"target":id,"hp_before":before.hp,"hp_after":after.hp,"shield_before":before.shield,"shield_after":after.shield,"damage":maxi(0,before.hp-after.hp),"healing":maxi(0,after.hp-before.hp),"shield_gain":maxi(0,after.shield-before.shield),"absorbed":maxi(0,before.shield-after.shield),"mp_gain":maxi(0,after.mp-before.mp)}

func _environment_view() -> Dictionary:
	var tile = run.data.tiles[position]
	return {"terrain":tile.terrain,"burning":tile.burning,"wet_until":tile.wet_until}

func _emit_event(event: Dictionary) -> void:
	event_serial += 1
	event["event_id"] = "%d:%d" % [run.data.battles,event_serial]
	events.append(event)

func _hurt(id: String, damage: int) -> void:
	var target = unit(id)
	if not enemies.has(id) and id != "grit" and "grit" in active and unit("grit").hp > 0 and target.hp < target.hp_max * 0.35:
		damage = ceili(damage * 0.8)
	if target.get("guard", false):
		damage = ceili(damage * 0.55)
	var absorbed = mini(int(target.get("shield", 0)), damage)
	target.shield = int(target.get("shield", 0)) - absorbed
	target.hp = maxi(0, int(target.hp) - damage + absorbed)

func _complete_action(id: String) -> void:
	if unit(id).get("slow", 0) > 0:
		unit(id).slow -= 1
	next_time[id] = clock + _delay(id)
	current = ""
	_settle_fire()
	if check_end():
		return
	resolve_queued()
	seek_next()

func _settle_fire() -> void:
	while clock >= fire_tick:
		fire_tick += 10.0
		if not run.data.tiles[position].burning:
			continue
		# Simultaneous environmental damage; do not check victory between victims.
		var results: Array = []
		var victims = alive_allies() + alive_enemies()
		for id in victims:
			var before = _unit_view(unit(id))
			_hurt(id, ceili(unit(id).hp_max * 0.08))
			results.append(_visual_result(id,before))
		_emit_event({"actor":"","targets":victims,"kind":"environment","skill_id":"fire_tick","element":"fire","results":results})
		_log("火场灼伤在场双方；森林燃料仍按天消耗。")

func check_end() -> bool:
	if outcome != "":
		return true
	if alive_allies().is_empty():
		var available = reserves()
		if not available.is_empty():
			var incoming = available[0]
			var replaced = active[0]
			active[0] = incoming
			next_time.erase(replaced)
			_deploy(incoming)
			_log("场上倒下；同地候补 %s 接替继续。" % unit(incoming).name)
		else:
			# User-confirmed: a simultaneous wipe is a defeat, never a free victory revive.
			_finish("defeat")
			return true
	if alive_enemies().is_empty():
		_finish("victory")
		return true
	return false

func retreat() -> Dictionary:
	if outcome != "":
		return _fail("战斗已经结束。")
	for id in paid:
		if unit(id).hp > 0:
			unit(id).hp = maxi(0, int(unit(id).hp) - ceili(unit(id).hp_max * 0.1))
	_finish("retreat")
	return {"ok": true}

func _finish(result: String) -> void:
	outcome = result
	current = ""
	queue.clear()
	var npc = str(pending.get("npc", ""))
	if npc != "":
		var opponent = enemies.values()[0]
		run.actor(npc).hp = 0 if opponent.hp <= 0 else run.actor(npc).hp_max
		if result == "victory":
			run.data.flags["duel_won_" + npc] = true
	var reward_key = position + ":" + npc
	if result == "victory":
		var revived: Array[String] = []
		var receiver = ""
		var relic = ""
		var coins = 0
		for id in paid:
			if unit(id).hp <= 0:
				unit(id).hp = 1
				revived.append(id)
			if not run.data.knowledge.has(id):
				run.data.knowledge[id] = {}
			if not run.data.knowledge[id].has("victories"):
				run.data.knowledge[id].victories = []
			if position not in run.data.knowledge[id].victories:
				run.data.knowledge[id].victories.append(position)
		if npc == "":
			run.data.tiles[position].enemies = []
		if not run.data.rewards.has(reward_key):
			receiver = str(paid.keys()[0])
			run.actor(receiver).inventory.salve = int(run.actor(receiver).inventory.get("salve", 0)) + 1
			run.data.rewards[reward_key] = true
			if npc.is_empty():
				var types = enemies.values().map(func(enemy): return enemy.type)
				var elite = Nodes.is_elite(types)
				coins = Nodes.battle_coins(int(run.data.seed), position, elite)
				run.data.lamp_coins += coins
				var candidates = Relics.battle_rewards(types)
				if not candidates.is_empty():
					relic = run.roll_relic("battle:" + reward_key, candidates, 0.40 if elite else 0.20, receiver, position)
		run.data.pending_victory = {"enemies": enemies.size(), "members": paid.keys(), "revived": revived,
			"salve_receiver": receiver, "relic": relic, "coins": coins}
		_log("战斗胜利。" + ("本战倒下的队员恢复至 1 HP。" if not revived.is_empty() else "")
			+ ("获得一份疗伤药。" if not receiver.is_empty() else "")
			+ ("获得 %d 灯铢。" % coins if coins > 0 else ""))
	elif result == "retreat":
		run.retreat_squad(pending.get("movers", []), pending.get("origin", position))
		_log("撤退，不返还精力、不发胜利奖励；未出战异地角色不受影响。")
	else:
		_log("战败。重伤者留在遭遇地点。")
	run.data.pending_battle = {}
	run.data.status = "exploring"
	if result == "defeat" and paid.has("hero"):
		run.data.status = "failed"
		run.data.flags["failure_reason"] = "主角参与的战斗中，友方与合格同地候补均无法继续。"
	run.check_global_failure()
	for id in paid:
		unit(id).shield = 0
		unit(id).slow = 0
		unit(id).guard = false
	run.save_game()
	run.changed.emit()

func _weakest(ids: Array) -> String:
	if ids.is_empty():
		return ""
	var result = str(ids[0])
	for id in ids:
		if unit(id).hp < unit(result).hp:
			result = id
	return result

func _log(message: String) -> void:
	run.note(message)

func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}
