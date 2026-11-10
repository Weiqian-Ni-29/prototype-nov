class_name Battle
extends RefCounted
const Catalog = preload("res://scripts/domain/catalog.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
const Nodes = preload("res://scripts/domain/map_nodes.gd")
const ItemEffects = preload("res://scripts/domain/battle_items.gd")
var items = ItemEffects.new()
var run: RefCounted
var position = ""
var active: Array[String] = []
var enemies: Dictionary = {}
var deployed: Dictionary = {}
var haste_turns: Dictionary = {}
var next_time: Dictionary = {}
var queue: Array = []
var clock = 0.0
var fire_tick = 10.0
var war_boss = ""
var reveal_pending = false
var river = false
var madness = {}
var madness_recovering = false
var burning = false
var wet = false
var current = ""
var outcome = ""
var auto_mode = false
var pending: Dictionary = {}
var events: Array = []
var event_serial = 0

func begin(expedition: RefCounted, encounter: Dictionary, formation: Array) -> Dictionary:
	if expedition.data.status != "exploring" or formation.is_empty() or formation.size() > 4:
		return {"ok": false, "message": "请选择一至四名同格角色。"}
	position = encounter.position
	if position == expedition.data.boss and expedition.data.tiles[position].enemies.has("war_god") and "hero" not in formation:
		return {"ok": false, "message": "旅人必须亲自迎战战神。"}
	var unique = {}
	for id in formation:
		var a = expedition.actor(id)
		if unique.has(id) or a.is_empty() or not a.joined or a.position != position or a.hp <= 0:
			return {"ok": false, "message": "只能选同一地块的健康队员出战，每人选一次。"}
		unique[id] = true
	run = expedition
	pending = encounter.duplicate(true)
	var npc_id = str(pending.get("npc", ""))
	var reward_tier: String = "elite" if run.node_at(position).get("kind") == "elite" or pending.get("reward_tier") == "elite" else "ordinary"
	var reward_source = "battle:%s:%s" % [position, npc_id]
	if not run.data.battle_offers.has(reward_source):
		run.data.battle_offers[reward_source] = run.relic_offer(reward_source, Relics.DATA.keys(), 1.0 if reward_tier == "elite" else 0.30)
	pending["battle_uid"] = reward_source
	pending["reward_tier"] = reward_tier
	pending["relic_offer"] = run.data.battle_offers[reward_source]
	run.data.pending_battle = pending.duplicate(true)
	# Save the encounter before initializing combat state.
	var saved = run.save_game()
	if not saved.ok:
		return saved
	active.clear()
	enemies.clear()
	deployed.clear()
	haste_turns.clear()
	next_time.clear()
	queue.clear()
	events.clear()
	event_serial = 0
	clock = 0.0
	items = ItemEffects.new()
	war_boss = ""
	reveal_pending = false
	river = false
	madness.clear()
	madness_recovering = false
	fire_tick = 10.0
	burning = false
	wet = false
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
			e["role"] = "交战中 · 重伤后需要救治"
			e["skill"] = "ignite" if npc == "ember" else "attack"
		else:
			e = run.war_god_stats() if type == "war_god" else Catalog.ENEMIES[type].duplicate(true)
			e["hp_max"] = e.hp
		if not e.has("attack_delivery"):
			e["attack_delivery"] = Catalog.ENEMIES[type].attack_delivery
		e["id"] = "enemy_%d" % i
		if type == "war_god":
			war_boss = e.id
		e["type"] = type
		e["shield"] = 0
		e["slow"] = 0
		e["guard"] = false
		e["charged"] = false
		enemies[e.id] = e
		next_time[e.id] = _delay(e.id) * (0.45 if encounter.get("ambush", false) else 1.0)
	run.data.status = "battle"
	run.data.battles += 1
	run.note("战斗开始。")
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
		if id not in active:
			result.append(id)
	return result

func _deploy(id: String) -> void:
	var a = unit(id)
	var first = not deployed.has(id)
	if first:
		a.shield = 0
		if run.has_relic("lamp_badge"):
			items.shield_gain(self, id, roundi(a.hp_max * 0.12))
		a.slow = 0
		a.guard = false
		deployed[id] = true
	# An incoming character always waits a personal interval; no swap loop grants turns.
	_schedule_action(id)
	if first:
		next_time[id] = clock + (next_time[id] - clock) * items.deployment(self, id)

func _schedule_action(id: String) -> void:
	var remaining = int(haste_turns.get(id, 0))
	next_time[id] = clock + _delay(id, remaining > 0) * float(items.post_delay.get(id, 1.0))
	items.post_delay.erase(id)
	if remaining > 1:
		haste_turns[id] = remaining - 1
	else:
		haste_turns.erase(id)

func _delay(id: String, hastened: bool = false) -> float:
	var speed: float = items.stat(self, id, "speed")
	if unit(id).get("slow", 0) > 0:
		speed *= 0.7
	if hastened:
		speed *= 1.25
	return 1000.0 / maxf(1.0, speed)

func timeline(limit: int = 7) -> Array:
	var simulated = next_time.duplicate()
	var future_haste = haste_turns.duplicate()
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
		var remaining = int(future_haste.get(best, 0))
		simulated[best] += _delay(best, remaining > 0)
		if remaining > 0:
			future_haste[best] = remaining - 1
	return result

func seek_next() -> void:
	if not outcome.is_empty():
		return
	if check_end():
		return
	var order = timeline(1)
	clock = maxf(clock, float(order[0].time))
	_settle_fire(false)
	if check_end():
		return
	order = timeline(1)
	current = str(order[0].id)
	clock = maxf(clock, float(order[0].time))
	unit(current).guard = false
	items.action_start(self, current)

func act(skill_id: String, target_id: String = "") -> Dictionary:
	if reveal_pending or not outcome.is_empty() or current.is_empty() or enemies.has(current):
		return _fail("现在不是己方正常行动。")
	var id = current
	if madness.has(id):
		_mad_action(id)
		return {"ok": true}
	var allowed = ["attack", "guard", str(unit(id).skill)]
	if skill_id not in allowed:
		return _fail("该角色没有这个普通指令。")
	var started_frozen: bool = items.present("frozen")
	if skill_id == "guard":
		var snap = items.snapshot(self, id, [])
		unit(id).guard = true
		unit(id).energy = mini(100, int(unit(id).energy) + 10)
		_log("%s 防守，下次正常行动前减伤。" % unit(id).name)
		items.guard(self, id, snap)
		_emit_event({"actor":id,"targets":[id],"kind":"guard","skill_id":"guard","element":"normal","results":[]})
	else:
		var result = _cast(id, skill_id, target_id)
		if not result.ok:
			return result
	_complete_action(id, started_frozen)
	return {"ok": true}

func _cast(id: String, skill_id: String, target_id: String, ultimate: bool = false) -> Dictionary:
	var skill = Catalog.SKILLS[skill_id]
	var environment_before = field_view()
	var results: Array = []
	var effects: Array = []
	if skill.get("healing",false): effects.append("heal")
	if skill.has("shield"): effects.append("shield")
	if skill.has("haste"): effects.append("haste")
	if skill.has("power") and not skill.get("healing",false): effects.append("damage")
	var caster = unit(id)
	var price = skill_cost(id, skill_id)
	if caster.hp <= 0 or int(caster.mp) < price:
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
	var snap = items.snapshot(self, id, targets)
	caster.mp -= items.cost(self, id, skill_id, true)
	if ultimate:
		caster.energy = 0
	else:
		caster.energy = mini(100, int(caster.energy) + int(skill.get("energy", 0)))
	for target in targets:
		var t = unit(target)
		var before = _unit_view(t)
		if skill.get("healing", false):
			var was_down = t.hp <= 0
			var amount: int = items.heal_amount(self, id, target, int(skill.power), snap)
			t.hp = mini(int(t.hp_max), int(t.hp) + amount)
			if not was_down and t.hp > before.hp:
				snap.heals.append({"target": target, "over": amount - int(t.hp - before.hp), "gain": int(t.hp - before.hp)})
			if was_down and t.hp > 0:
				_schedule_action(target)
			_log("%s → %s：恢复 %d HP。" % [caster.name, t.name, int(t.hp - before.hp)])
		elif skill.has("power") and t.hp > 0:
			var damage = _direct_damage(id, target, skill_id, snap, true)
			_hurt(target, damage)
			if skill.has("slow") and t.hp > 0:
				var duration = int(skill.slow) + int(skill.element == "ice" and wet)
				var keys = items._keys(self, id, "grave:slow", "grave_wayfarer")
				if skill.element == "gravity" and not river and duration < 3 and items.has_set(self, id, "grave_wayfarer", 3) \
						and not snap.has("gravity_slow") and items._ready(self, keys, 2) and t.slow < duration + 1:
					duration += 1
					items._count(self, keys)
					snap.gravity_slow = true
				t.slow = maxi(int(t.slow), items.reduce_slow(self, target, duration))
			_log("%s · %s → %s：%d 伤害。" % [caster.name, skill.name, t.name, damage])
		if skill.has("shield") and t.hp > 0:
			items.shield_gain(self, target, int(skill.shield))
			_log("%s 获得护盾。" % t.name)
		var result = _visual_result(target, before)
		if skill.element == "ice" and skill.has("slow") and t.hp > 0:
			result["slow"] = t.slow
		if skill.has("haste") and t.hp > 0:
			haste_turns[target] = maxi(int(haste_turns.get(target, 0)), int(skill.haste))
			result["haste"] = haste_turns[target]
			_log("%s 获得提速。" % t.name)
		results.append(result)
	if skill.has("environment") and results.any(func(result):
			return result.damage + result.absorbed + result.healing + result.shield_gain > 0):
		_apply_field_effect(skill.environment)
	items.cast_done(self, id, skill_id, ultimate, price, snap, results)
	_emit_event({"actor": id, "targets": targets, "kind": "ultimate" if ultimate else "cast" if skill_id != "attack" else "attack", "element": skill.element, "skill": skill.name, "skill_id":skill_id,"effects":effects,"results":results,"environment_before":environment_before,"environment_after":field_view()})
	return {"ok": true}

func skill_cost(id: String, skill_id: String) -> int:
	return items.cost(self, id, skill_id)

func damage_preview(source: String, target: String, skill_id: String) -> int:
	return _direct_damage(source, target, skill_id, items.snapshot(self, source, [target]))

func _direct_damage(source: String, target: String, skill_id: String, snap: Dictionary, landed: bool = false) -> int:
	var skill = Catalog.SKILLS[skill_id]
	var attack_value: float = items.stat(self, source, "attack")
	if river and source == "hero":
		attack_value *= 3
	var defense_value: float = items.stat(self, target, "defense")
	var multiplier = environment_multiplier(str(skill.element), str(unit(target).get("element", "normal")))
	var base = (attack_value * float(skill.get("power", 1.0)) - defense_value * 0.6) * multiplier
	return maxi(1, floori(items.damage(self, source, target, skill_id, skill.element, base, snap, landed)))

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
	if burning and element == "fire":
		multiplier *= 1.1
	if wet and element == "fire":
		multiplier *= 0.8
	if wet and element == "lightning":
		multiplier *= 1.25
	if items.present("charged") and element == "lightning":
		multiplier += 0.10
	return clampf(multiplier, 0.5, 1.5)

func use_item(item: String, target_id: String) -> Dictionary:
	if outcome != "" or enemies.has(current) or current.is_empty() or madness.has(current) or target_id not in active:
		return _fail("只在我方本人正常行动窗口使用道具，目标须在场。")
	var before = _unit_view(unit(target_id))
	var received_pp = 20 if before.hp > 0 and run.has_relic("tender_gauze") and before.hp * 100 <= unit(target_id).hp_max * 30 else 0
	var result = run.use_item(current, target_id, item, true, received_pp)
	if result.ok:
		if result.hp_gain > 0 and before.hp > 0:
			var healing = [{"target": target_id, "over": result.hp_over, "gain": result.hp_gain}]
			items.after_nonrelic_heal(self, current, healing)
		if unit(target_id).hp > 0 and float(next_time.get(target_id, 0.0)) < clock:
			_schedule_action(target_id)
		_emit_event({"actor": current, "targets": [target_id], "kind": "heal", "skill_id":"item:"+item,"element": "normal","results":[_visual_result(target_id,before)]})
	return result

func swap(incoming: String) -> Dictionary:
	if outcome != "" or enemies.has(current) or current.is_empty() or madness.has(current) or incoming not in reserves():
		return _fail("等轮到己方行动时，才能换上同一地块可以出战的候补。")
	var outgoing = current
	var index = active.find(outgoing)
	active[index] = incoming
	_deploy(incoming)
	next_time.erase(outgoing)
	_log("%s 换下，%s 上场。换人用掉了这次正常行动。" % [unit(outgoing).name, unit(incoming).name])
	current = ""
	_settle_fire()
	resolve_queued()
	seek_next()
	return {"ok": true}

func request_ultimate(id: String, target: String = "") -> Dictionary:
	if outcome != "" or id not in active or madness.has(id) or unit(id).hp <= 0 or unit(id).energy < Catalog.ENERGY_MAX:
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
	while not reveal_pending and not queue.is_empty() and outcome == "":
		var request = queue.pop_front()
		if request.id in active and unit(request.id).hp > 0 and not madness.has(request.id) and unit(request.id).energy >= 100:
			var starting_ice: bool = items.present("frozen")
			var starting_slow: bool = unit(request.id).slow > 0
			var cast = _cast(request.id, unit(request.id).ultimate, request.target, true)
			if cast.ok:
				items.end_action(self, request.id, starting_ice, starting_slow)
			check_end()

func step_auto() -> void:
	if reveal_pending or outcome != "":
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
	elif madness.has(current):
		_mad_action(current)
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
		if caster.mp < skill_cost(current, caster.skill) or (skill.get("healing", false) and lowest_ratio > 0.65):
			choice = "attack"
		if Catalog.SKILLS[choice].target == "enemy":
			target = _weakest(alive_enemies())
		act(choice, target)

func _enemy_action(id: String) -> void:
	var a = enemies[id]
	var target = _weakest(alive_allies())
	match a.skill:
		"madness":
			if not river and not madness.has(target) and not madness_recovering:
				madness[target] = true
				_log("%s陷入疯狂，接下来可能攻击任何在场的人。" % unit(target).name)
			madness_recovering = not madness_recovering
			_enemy_hit(id, target, 0.8 if not river else 0.5)
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
			unit(target).slow = maxi(int(unit(target).slow), items.reduce_slow(self, target, 2))
		"ignite", "wet":
			var environment_before = field_view()
			var snap = items.snapshot(self, id, [target])
			var element = "fire" if a.skill == "ignite" else "water"
			var hit = _enemy_hit(id, target, 1.15, element, a.skill)
			if hit:
				_apply_field_effect(a.skill)
				items._fields_after(self, id, element, snap, true, false, [target])
			events[-1].environment_before = environment_before
			events[-1].environment_after = field_view()
		_:
			_enemy_hit(id, target, 1.0)
	_complete_action(id)

func _enemy_hit(id: String, target: String, power: float, element: String = "normal", delivery: String = "attack") -> bool:
	var before = _unit_view(unit(target))
	var snap = items.snapshot(self, id, [target])
	var base: float = (items.stat(self, id, "attack") * power - items.stat(self, target, "defense") * 0.6) * environment_multiplier(element, unit(target).element)
	var damage = maxi(1, floori(items.damage(self, id, target, delivery, element, base, snap, true)))
	_hurt(target, damage)
	var result = _visual_result(target, before)
	items.enemy_damage(self, id, target, result, snap)
	_log("%s → %s：%d 伤害。" % [unit(id).name, unit(target).name, damage])
	_emit_event({"actor": id, "targets": [target], "kind": "attack", "skill_id":"enemy_attack","element": element,"results":[result]})
	if run.has_relic("witness_slate"):
		if not run.data.map_intel.has("observed_enemy_actions"):
			run.data.map_intel.observed_enemy_actions = []
		var observed: Array = run.data.map_intel.observed_enemy_actions
		observed.append({"name": unit(id).name, "element": element, "target": unit(target).name,
			"damage": result.damage, "absorbed": result.absorbed, "field": field_view()})
		if observed.size() > 100:
			observed.pop_front()
	return result.damage + result.absorbed > 0

func _unit_view(a: Dictionary) -> Dictionary:
	return {"hp":int(a.hp),"shield":int(a.get("shield",0)),"mp":int(a.get("mp",0))}

func _visual_result(id: String, before: Dictionary) -> Dictionary:
	var after = _unit_view(unit(id))
	return {"target":id,"hp_before":before.hp,"hp_after":after.hp,"shield_before":before.shield,"shield_after":after.shield,"damage":maxi(0,before.hp-after.hp),"healing":maxi(0,after.hp-before.hp),"shield_gain":maxi(0,after.shield-before.shield),"absorbed":maxi(0,before.shield-after.shield),"mp_gain":maxi(0,after.mp-before.mp)}

func field_view() -> Dictionary:
	return {"terrain": run.data.tiles[position].terrain, "burning": burning, "wet": wet, "river": river, "fields": items.view()}

func _apply_field_effect(effect: String) -> void:
	match effect:
		"ignite":
			if run.data.tiles[position].terrain == "forest" and run.data.weather != "rain" and not wet:
				burning = true
		"wet":
			wet = true
			items.fields.wet = maxi(int(items.fields.get("wet", 0)), items.index + 5)

func _emit_event(event: Dictionary) -> void:
	event_serial += 1
	event["event_id"] = "%d:%d" % [run.data.battles,event_serial]
	events.append(event)

func _hurt(id: String, damage: int) -> void:
	if river and id == "hero":
		return
	var target = unit(id)
	if not enemies.has(id) and id != "grit" and "grit" in active and unit("grit").hp > 0 and target.hp < target.hp_max * 0.35:
		damage = ceili(damage * 0.8)
	if target.get("guard", false):
		damage = ceili(damage * 0.55)
	var shield_before = int(target.get("shield", 0))
	var absorbed = mini(shield_before, damage)
	target.shield = shield_before - absorbed
	items.absorb(id, shield_before, absorbed)
	var minimum = ceili(target.hp_max * 0.55) if id == war_boss and not river else 0
	target.hp = maxi(minimum, int(target.hp) - damage + absorbed)

func _complete_action(id: String, started_frozen: bool = true) -> void:
	var started_slow: bool = unit(id).slow > 0
	if started_slow:
		unit(id).slow -= 1
	current = ""
	if river and not war_boss.is_empty() and unit(war_boss).hp > 0:
		var boss = unit(war_boss)
		var before = _unit_view(boss)
		boss.attack = maxi(0, int(boss.attack) - 6)
		boss.defense = maxi(0, int(boss.defense) - 4)
		boss.speed = maxi(36, int(boss.speed) - 12)
		boss.shield = 0
		boss.hp = maxi(0, int(boss.hp) - 9)
		_emit_event({"actor": "", "kind": "environment", "targets": [war_boss], "skill_id": "river", "element": "normal", "results": [_visual_result(war_boss, before)]})
	_settle_fire()
	items.end_action(self, id, started_frozen, started_slow)
	_schedule_action(id)
	if check_end():
		return
	resolve_queued()
	seek_next()

func _settle_fire(include_current: bool = true) -> void:
	while fire_tick < clock or (include_current and fire_tick == clock):
		fire_tick += 10.0
		if not burning:
			continue
		# Simultaneous environmental damage; do not check victory between victims.
		var results: Array = []
		var victims = alive_allies() + alive_enemies()
		for id in victims:
			var before = _unit_view(unit(id))
			_hurt(id, items.reduce_fire(self, id, ceili(unit(id).hp_max * 0.08)))
			results.append(_visual_result(id,before))
		_emit_event({"actor":"","targets":victims,"kind":"environment","skill_id":"fire_tick","element":"fire","results":results})
		_log("火场灼伤在场双方。")

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
			_log("场上的队员倒下了，同一地块的候补 %s 接着上场。" % unit(incoming).name)
		else:
			# User-confirmed: a simultaneous wipe is a defeat, never a free victory revive.
			_finish("defeat")
			return true
	if not war_boss.is_empty() and not river and unit(war_boss).hp <= ceili(unit(war_boss).hp_max * 0.55):
		if not reveal_pending:
			reveal_pending = true
			_emit_event({"actor": war_boss, "kind": "cast", "targets": ["hero"], "skill_id": "old_strike", "element": "fire", "results": []})
		return true
	if alive_enemies().is_empty():
		_finish("victory")
		return true
	return false

func awaken_death_power() -> void:
	if not reveal_pending:
		return
	reveal_pending = false
	river = true
	madness.clear()
	if "hero" not in active:
		var replaced = active[0]
		active[0] = "hero"
		next_time.erase(replaced)
	unit("hero").name = "伊文洛"
	run.data.flags["hero_identity_revealed"] = true
	unit("hero").hp = unit("hero").hp_max
	unit("hero").mp = unit("hero").mp_max
	unit("hero").energy = 100
	next_time["hero"] = clock
	seek_next()

func _mad_action(id: String) -> void:
	madness.erase(id)
	var targets = alive_allies() + alive_enemies()
	targets.erase(id)
	if targets.is_empty():
		return
	var target = targets[run.rng.randi_range(0, targets.size() - 1)]
	var before = _unit_view(unit(target))
	_hurt(target, run.stat(id, "attack") * 2)
	_emit_event({"actor": id, "kind": "attack", "targets": [target], "skill_id": "mad_attack", "element": "normal", "results": [_visual_result(target, before)]})
	_complete_action(id)

func retreat() -> Dictionary:
	if river or reveal_pending:
		return _fail("决战正在进行。")
	if outcome != "":
		return _fail("战斗已经结束。")
	for id in deployed:
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
		items.victory(self)
		var revived: Array[String] = []
		var receiver = ""
		var relic = ""
		var duplicate = false
		var coins = 0
		for id in deployed:
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
			receiver = str(deployed.keys()[0])
			run.actor(receiver).inventory.salve = int(run.actor(receiver).inventory.get("salve", 0)) + 1
			run.data.rewards[reward_key] = true
			if npc.is_empty():
				var types = enemies.values().map(func(enemy): return enemy.type)
				var elite = Nodes.is_elite(types)
				coins = run.reward_coins("battle", Nodes.battle_coins(int(run.data.seed), position, elite))
				run.data.lamp_coins += coins
			duplicate = run.data.relic_seen.has(pending.relic_offer)
			relic = run.claim_relic_reward(pending.battle_uid, pending.relic_offer, receiver, position)
			run.data.item_revision += 1
		run.data.pending_victory = {"enemies": enemies.size(), "members": deployed.keys(), "revived": revived,
			"salve_receiver": receiver, "relic": relic, "relic_duplicate": duplicate, "coins": coins}
		_log("战斗胜利。" + ("本战倒下的队员恢复至 1 HP。" if not revived.is_empty() else "")
			+ ("获得一份疗伤药。" if not receiver.is_empty() else "")
			+ ("获得 %d 灯铢。" % coins if coins > 0 else ""))
	elif result == "retreat":
		run.retreat_party(pending.get("origin", position))
		_log("队伍撤退了。这场没有胜利奖励。")
	else:
		_log("战败。重伤者留在遭遇地点。")
	run.data.pending_battle = {}
	for key in run.data.item_effect_counts.keys():
		if str(key).begins_with("uphill_ready:"):
			run.data.item_effect_counts.erase(key)
	run.data.status = "won" if result == "victory" and not war_boss.is_empty() else "exploring"
	if result != "victory" or run.data.status == "won":
		run.data.erase("pending_arrival")
	if result == "defeat" and deployed.has("hero"):
		run.data.status = "failed"
		run.data.flags["failure_reason"] = "旅人所在的队伍已经无人能继续战斗，同一地块也没有能上场的候补。"
	run.check_global_failure()
	for id in deployed:
		unit(id).shield = 0
		unit(id).slow = 0
		unit(id).guard = false
	burning = false
	wet = false
	items.fields.clear()
	var saved = run.save_game()
	if not saved.ok:
		_log("战斗已结束，游戏没能保存。 " + str(saved.message))
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
