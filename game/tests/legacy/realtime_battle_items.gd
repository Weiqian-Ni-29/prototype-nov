extends RefCounted

const Gear = preload("res://scripts/domain/gear_catalog.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const FIELD_ORDER = ["frozen", "charged", "root_cover", "wind_barrier", "wet"]


var index = 0
var fields: Dictionary = {}
var frozen_seen: Dictionary = {}
var marks: Dictionary = {}
var shields: Dictionary = {}
var hp_losses: Dictionary = {}
var attacks: Dictionary = {}
var last_own: Dictionary = {}
var damaged_by: Dictionary = {}
var post_delay: Dictionary = {}

static func ranged(battle, actor: String, skill_id: String) -> bool:
	var unit: Dictionary = battle.unit(actor)
	if battle.enemies.has(actor) or skill_id == "attack":
		return unit.get("attack_delivery") == "ranged" or (battle.enemies.has(actor) and skill_id in ["ignite", "wet"])
	return Catalog.SKILLS[skill_id].delivery == "ranged"

func present(field: String) -> bool:
	return fields.has(field)

func view() -> Dictionary:
	var remaining: Dictionary = {}
	for key in fields:
		remaining[key] = maxi(0, int(fields[key]) - index)
	return remaining

func _keys(battle, actor: String, effect: String, equipment: String = "", daily: bool = false, team: bool = false) -> Array:
	var period = "day:%d" % battle.run.data.day if daily else str(battle.pending.get("battle_uid", "battle:" + battle.position))
	var base = period + ":" + effect + ":"
	var keys = [base + ("team" if team else actor)]
	if not equipment.is_empty():
		var wearer: Dictionary = battle.unit(actor)
		for slot in Gear.SLOTS:
			var id: String = battle.run.equipped_definition(actor, slot)
			if id == equipment or Gear.DATA.get(id, {}).get("set_id") == equipment:
				keys.append(base + "uid:" + str(wearer.equipment[slot]))
	return keys

func _ready(battle, keys: Array, limit: int) -> bool:
	return keys.all(func(key): return int(battle.run.data.item_effect_counts.get(key, 0)) < limit)

func _count(battle, keys: Array) -> void:
	for key in keys:
		battle.run.data.item_effect_counts[key] = int(battle.run.data.item_effect_counts.get(key, 0)) + 1

func _item(battle, actor: String, slot: String, id: String) -> bool:
	return not battle.enemies.has(actor) and battle.run.equipped_definition(actor, slot) == id

func has_set(battle, actor: String, id: String, count: int = 2) -> bool:
	return not battle.enemies.has(actor) and battle.run.set_count(actor, id) >= count

func _mark(actor: String, key: String, value: Variant = true) -> void:
	if not marks.has(actor):
		marks[actor] = {}
	marks[actor][key] = value

func _read_mark(actor: String, key: String, fallback: Variant = null) -> Variant:
	return marks.get(actor, {}).get(key, fallback)

func _erase(actor: String, key: String) -> void:
	if marks.has(actor):
		marks[actor].erase(key)

func snapshot(battle, actor: String, targets: Array) -> Dictionary:
	var units: Dictionary = {}
	for id in [actor] + targets:
		var unit: Dictionary = battle.unit(id)
		units[id] = {"hp": unit.hp, "hp_max": unit.hp_max, "shield": unit.shield,
			"mp": unit.get("mp", 0), "slow": unit.slow, "guard": unit.guard}
	return {"actor": actor, "units": units, "terrain": battle.run.data.tiles[battle.position].terrain,
		"rain": battle.run.data.weather == "rain", "burning": battle.burning, "wet": battle.wet,
		"river": battle.river, "fields": fields.duplicate(), "claims": {}, "heals": []}

func damage(battle, source: String, target: String, skill: String, element: String, amount: float, snap: Dictionary, landed: bool = false) -> float:
	var a: Dictionary = battle.unit(source)
	var b: Dictionary = battle.unit(target)
	var attacker: Dictionary = snap.units[source]
	var defender: Dictionary = snap.units[target]
	var distance = ranged(battle, source, skill)
	var bonus = 0
	var reduction = 0
	var debuff = int(_read_mark(source, "wariness", 0))
	if snap.fields.has("wind_barrier") and distance:
		amount *= 0.90
	if snap.fields.has("root_cover"):
		amount *= 0.95
	if not battle.enemies.has(source):
		var set_id = {"fire": "ember_warden", "water": "tide_weaver", "ice": "rime_path",
			"lightning": "storm_conductor", "wind": "gale_runner"}.get(element, "")
		if not str(set_id).is_empty() and has_set(battle, source, set_id):
			bonus += 10 if element == "fire" else 8
		match element:
			"fire":
				if snap.burning and _item(battle, source, "weapon", "ember_warden_weapon"):
					bonus += 8
			"water":
				if snap.wet and _item(battle, source, "weapon", "tide_weaver_weapon"):
					bonus += 8
				if snap.terrain == "desert":
					bonus += 8 * (int(_item(battle, source, "weapon", "dune_keeper_weapon")) + int(has_set(battle, source, "dune_keeper")))
			"ice":
				if snap.fields.has("frozen"):
					bonus += 8 * int(_item(battle, source, "weapon", "rime_path_weapon"))
					bonus += 10 * int(has_set(battle, source, "rime_path", 3))
			"lightning":
				if snap.wet and _item(battle, source, "weapon", "storm_conductor_weapon"):
					bonus += 8
				if snap.fields.has("charged") and has_set(battle, source, "storm_conductor", 3):
					bonus += _damage_claim(battle, snap, source, "storm:three", "storm_conductor", 2, 10, landed)
			"wind":
				if int(_read_mark(source, "gale:weapon", 0)) > index:
					bonus += 10
				if int(_read_mark(source, "gale:three", 0)) > index:
					bonus += 12
			"earth":
				if snap.terrain == "mountain" and _item(battle, source, "weapon", "stone_vow_weapon"):
					bonus += 10
			"gravity":
				if _item(battle, source, "weapon", "grave_wayfarer_weapon"):
					bonus += 8
		if skill == "attack" and attacker.shield > 0 and _item(battle, source, "weapon", "frontier_guard_weapon"):
			bonus += 8
		if defender.hp == defender.hp_max and _item(battle, source, "weapon", "road_surveyor_weapon"):
			bonus += _damage_claim(battle, snap, source, "road:weapon", "road_surveyor_weapon", 1, 10, landed, target)
		for id in battle.run.data.relic_attunement:
			var entry = Relics.DATA[id]
			if entry.hook != "combat_damage_bonus":
				continue
			var active = false
			match entry.params.when:
				"ranged_attack": active = skill == "attack" and distance
				"first_positive_basic_attack": active = skill == "attack"
				"next_basic_attack_within_two_own_actions": active = skill == "attack" and int(_read_mark(source, "patient", 0)) > 0
				"self_mp_ratio_lte_25_basic_attack": active = skill == "attack" and attacker.mp * 4 <= a.mp_max
				"target_hp_full": active = b.hp == b.hp_max
				"target_hp_ratio_lte_30": active = b.hp * 100 <= b.hp_max * 30
				"target_has_shield": active = b.shield > 0
				"immediately_next_own_action_is_damaging_skill": active = skill == a.skill and last_own.get(source) == "attack"
				"only_one_living_allied_participant": active = battle.alive_allies().size() == 1
				"next_own_action_hits_marked_enemy": active = _read_mark(source, "witness") == target
				"consecutive_basic_attack_same_recorded_target": active = skill == "attack" and last_own.get(source) == "attack" and _read_mark(source, "track") == target
			if active:
				var limit = str(entry.params.limit)
				bonus += entry.params.bonus_pp if limit == "none" else _damage_claim(battle, snap, source, id, "", int(limit.get_slice(":", 1)), entry.params.bonus_pp, landed)
	elif not battle.enemies.has(target):
		if _item(battle, target, "armor", "tide_weaver_armor") and element == "fire" and snap.wet:
			reduction += 10
		if _item(battle, target, "armor", "storm_conductor_armor") and element == "lightning" and snap.fields.has("charged"):
			reduction += 20
		if _item(battle, target, "armor", "gale_runner_armor") and distance and snap.fields.has("wind_barrier"):
			reduction += 8
		if _item(battle, target, "armor", "stone_vow_armor") and defender.guard:
			reduction += 8
		if _item(battle, target, "armor", "dune_keeper_armor") and element == "fire" and snap.terrain == "desert":
			reduction += 10
		if element == "gravity" and _item(battle, target, "armor", "grave_wayfarer_armor") and (snap.terrain == "ruins" or defender.guard):
			reduction += 12
		if skill == "attack" and snap.terrain == "ruins" and has_set(battle, target, "grave_wayfarer"):
			reduction += 8
		if defender.hp * 2 < defender.hp_max and _item(battle, target, "armor", "frontier_guard_armor"):
			reduction += _damage_claim(battle, snap, target, "frontier:armor", "frontier_guard_armor", 3, 12, landed, target)
		if _item(battle, target, "armor", "road_surveyor_armor"):
			reduction += _damage_claim(battle, snap, target, "road:armor", "road_surveyor_armor", 1, 15, landed, target)
		if defender.slow > 0 and _item(battle, target, "armor", "oath_witness_armor"):
			reduction += _damage_claim(battle, snap, target, "oath:armor", "oath_witness_armor", 3, 8, landed, target)
		if _read_mark(target, "aid") != null:
			reduction += 12
		for id in battle.run.data.relic_attunement:
			var entry = Relics.DATA[id]
			if entry.hook != "combat_damage_reduction" or entry.params.scope != "direct":
				continue
			var active = false
			match entry.params.when:
				"self_hp_ratio_lte_50": active = b.hp * 2 <= b.hp_max
				"self_shield_positive": active = b.shield > 0
				"same_enemy_as_previous_damaging_action_before_self_action": active = damaged_by.get(target) == source
				"field_charged_and_incoming_lightning": active = snap.fields.has("charged") and element == "lightning"
			if active:
				reduction += entry.params.reduce_pp
	return amount * (1.0 + mini(50, bonus) / 100.0 - mini(30, debuff) / 100.0) * (1.0 - mini(50, reduction) / 100.0)

func _damage_claim(battle, snap: Dictionary, id: String, effect: String, gear: String, limit: int, points: int, landed: bool, unique_target: String = "") -> int:
	var token = id + ":" + effect
	if snap.claims.has(token):
		return points if unique_target.is_empty() else 0
	var keys = _keys(battle, id, effect, gear)
	if not _ready(battle, keys, limit):
		return 0
	if landed:
		snap.claims[token] = keys
	return points

func cost(battle, id: String, skill_id: String, commit: bool = false) -> int:
	var skill = Catalog.SKILLS[skill_id]
	var base: int = skill.mp
	if base <= 0:
		return base
	var pp = 0
	var flat = 0
	var claims: Array = []
	var a: Dictionary = battle.unit(id)
	for relic in battle.run.data.relic_attunement:
		var entry = Relics.DATA[relic]
		if entry.hook != "combat_cost":
			continue
		match entry.params.when:
			"all_normal_skills": pp += entry.params.reduce_pp
			"self_hp_ratio_lte_25":
				if a.hp * 4 <= a.hp_max:
					pp += entry.params.reduce_pp
			"lightning_skill_in_wet":
				var keys = _keys(battle, id, relic)
				if skill.element == "lightning" and battle.wet and _ready(battle, keys, 1):
					flat += entry.params.reduce_flat
					claims.append_array(keys)
	var equipment = ""
	if skill.element == "water" and battle.run.data.tiles[battle.position].terrain == "desert" and _item(battle, id, "accessory", "dune_keeper_accessory"):
		equipment = "dune_keeper_accessory"
	elif skill.element == "gravity" and has_set(battle, id, "grave_wayfarer"):
		equipment = "grave_wayfarer"
	if not equipment.is_empty():
		var keys = _keys(battle, id, equipment + ":cost", equipment)
		if _ready(battle, keys, 2):
			flat += 1
			claims.append_array(keys)
	var total = maxi(1, ceili(base * (1.0 - pp / 100.0) - flat))
	if commit and total < base:
		_count(battle, claims)
	return total

func stat(battle, id: String, field: String) -> float:
	var a: Dictionary = battle.unit(id)
	if battle.enemies.has(id):
		var penalty = 0
		if field == "attack" and int(_read_mark(id, "dented", 0)) > index:
			penalty = 10
		return float(a[field]) * (1.0 - penalty / 100.0)
	var base: int = battle.run.stat(id, field)
	var percent = 0
	if field == "speed":
		if battle.run.has_relic("unburdened_clasp") and a.shield == 0:
			percent += 8
		if int(_read_mark(id, "relay", 0)) > 0:
			percent += 10
		if battle.run.has_relic("ice_anchor_button") and present("frozen"):
			percent -= 5
	elif field == "defense":
		if battle.run.has_relic("last_drop_cup") and a.mp * 4 <= a.mp_max:
			percent += 12
		if battle.run.has_relic("ice_anchor_button") and present("frozen"):
			percent += 20
		if battle.river and _read_mark(id, "river_brace") != null:
			percent += 15
	return float(base) * (1.0 + mini(30 if field == "speed" else 50, percent) / 100.0)

func heal_amount(battle, id: String, target: String, base: int, snap: Dictionary) -> int:
	var recipient: Dictionary = battle.unit(target)
	if recipient.hp <= 0:
		return base
	var pp = 0
	if _item(battle, id, "weapon", "grove_mender_weapon"):
		pp += 8
	if has_set(battle, id, "grove_mender"):
		pp += 10
	if snap.terrain == "forest" and _item(battle, target, "armor", "grove_mender_armor"):
		pp += 8
	if battle.run.has_relic("tender_gauze") and recipient.hp * 100 <= recipient.hp_max * 30:
		pp += 20
	return floori(base * (1.0 + mini(50, pp) / 100.0))

func shield_gain(battle, id: String, base: float, temporary: bool = false) -> int:
	var a: Dictionary = battle.unit(id)
	if a.hp <= 0:
		return 0
	var pp = 10 * (int(has_set(battle, id, "stone_vow")) + int(has_set(battle, id, "frontier_guard")))
	var amount = floori(base * (1.0 + mini(30, pp) / 100.0))
	if amount <= 0:
		return 0
	a.shield += amount
	if temporary:
		if not shields.has(id):
			shields[id] = []
		shields[id].append({"amount": amount, "expires": index + 5})
	return amount

func absorb(id: String, shield_before: int, absorbed: int) -> void:
	if not shields.has(id):
		return
	var shares: Array = shields[id]
	var temporary = 0
	for share in shares:
		temporary += int(share.amount)
	var remaining = maxi(0, absorbed - maxi(0, shield_before - temporary))
	while remaining > 0 and not shares.is_empty():
		var share: Dictionary = shares[0]
		var loss = mini(remaining, int(share.amount))
		remaining -= loss
		share.amount -= loss
		if share.amount <= 0:
			shares.pop_front()

func reduce_fire(battle, id: String, base: int) -> int:
	if battle.enemies.has(id):
		return base
	var pp = 25 * int(battle.run.has_relic("ash_filter_patch"))
	pp += 15 * int(_item(battle, id, "armor", "ember_warden_armor"))
	pp += 10 * int(has_set(battle, id, "ember_warden"))
	return ceili(base * (1.0 - mini(50, pp) / 100.0))

func reduce_slow(battle, id: String, duration: int) -> int:
	if duration < 2 or not _item(battle, id, "armor", "rime_path_armor"):
		return duration
	var keys = _keys(battle, id, "rime:armor", "rime_path_armor")
	if not _ready(battle, keys, 2):
		return duration
	if duration - 1 > int(battle.unit(id).slow):
		_count(battle, keys)
	return duration - 1


func _apply_resource(battle, target: String, params: Dictionary) -> bool:
	var a: Dictionary = battle.unit(target)
	if a.hp <= 0:
		return false
	var changed = false
	for resource in ["hp", "mp", "energy"]:
		var maximum = 100 if resource == "energy" else int(a.get(resource + "_max", 0))
		var amount = int(params.get(resource + "_flat", 0)) + floori(maximum * int(params.get(resource + "_max_pp", 0)) / 100.0)
		var gain = mini(amount, maximum - int(a.get(resource, 0)))
		if gain > 0:
			a[resource] += gain
			changed = true
	return changed

func _resource(battle, id: String, effect: String, limit: int, amounts: Dictionary, gear: String = "") -> void:
	var keys = _keys(battle, id, effect, gear)
	if _ready(battle, keys, limit) and _apply_resource(battle, id, amounts):
		_count(battle, keys)

func _grant_shield(battle, target: String, pp: int, temporary: bool) -> bool:
	return shield_gain(battle, target, battle.unit(target).hp_max * pp / 100.0, temporary) > 0

func _gear_shield(battle, id: String, target: String, effect: String, gear: String, limit: int, pp: int) -> void:
	var keys = _keys(battle, id, effect, gear)
	if _ready(battle, keys, limit) and _grant_shield(battle, target, pp, true):
		_count(battle, keys)

func _weakest(battle, id: String, wounded: bool = false) -> String:
	var options: Array = battle.alive_allies()
	options.erase(id)
	if wounded:
		options = options.filter(func(other): return battle.unit(other).hp < battle.unit(other).hp_max)
	options.sort_custom(func(a, b):
		var left: Dictionary = battle.unit(a)
		var right: Dictionary = battle.unit(b)
		return a < b if left.hp * right.hp_max == right.hp * left.hp_max else left.hp * right.hp_max < right.hp * left.hp_max)
	return "" if options.is_empty() else str(options[0])

func action_start(battle, id: String) -> void:
	if _read_mark(id, "sheltered_ready", false):
		_erase(id, "sheltered_ready")
		if battle.run.has_relic("sheltered_stitch"):
			_resource(battle, id, "sheltered_stitch", 1, {"hp_max_pp": 5})

func end_action(battle, id: String, started_frozen: bool, started_slow: bool) -> void:
	index += 1
	if started_frozen and present("frozen") and not frozen_seen.has(id):
		frozen_seen[id] = true
		if not started_slow and battle.unit(id).slow == 0:
			battle.unit(id).slow = 1
	_erase(id, "wariness")
	_erase(id, "aid")
	if int(_read_mark(id, "river_brace", -1)) < index - 1:
		_erase(id, "river_brace")
	damaged_by.erase(id)
	var relay = int(_read_mark(id, "relay", 0))
	if relay > 0:
		_mark(id, "relay", relay - 1)
	for key in fields.keys():
		if key == "wet":
			continue
		if int(fields[key]) <= index:
			fields.erase(key)
			if key == "frozen":
				frozen_seen.clear()
	if fields.has("wet") and int(fields.wet) <= index and not (present("charged") or present("frozen")):
		fields.erase("wet")
		battle.wet = false
	for actor in shields:
		var shares: Array = shields[actor]
		for share in shares.duplicate():
			if share.expires <= index:
				var a: Dictionary = battle.unit(actor)
				a.shield = maxi(0, int(a.shield) - int(share.amount))
				shares.erase(share)

func deployment(battle, id: String) -> float:
	if battle.run.has_relic("uphill_kneepad") and battle.run.data.item_effect_counts.has("uphill_ready:" + id):
		var key = "uphill_kneepad:day:%d:%s" % [battle.run.data.day, id]
		if not battle.run.data.item_effect_counts.has(key) and _grant_shield(battle, id, 8, false):
			battle.run.data.item_effect_counts[key] = 1
	if battle.run.has_relic("ready_sandal_loop"):
		return 0.85
	return 1.0

func guard(battle, id: String, snap: Dictionary) -> void:
	_fields_after(battle, id, "guard", snap, false, false, [])
	if battle.run.has_relic("patient_knot"):
		_mark(id, "patient", 2)
	if battle.run.has_relic("guard_candle_cap"):
		var keys = _keys(battle, id, "guard_candle_cap")
		if _ready(battle, keys, 1) and _grant_shield(battle, id, 8, false):
			_count(battle, keys)
	if battle.run.has_relic("quiet_abacus"):
		_resource(battle, id, "quiet_abacus", 1, {"mp_max_pp": 10})
	if battle.run.has_relic("breath_reserve") and _read_mark(id, "breath", false):
		_resource(battle, id, "breath_reserve", 1, {"energy_flat": 5})
		_erase(id, "breath")
	if battle.run.has_relic("sheltered_stitch"):
		_mark(id, "sheltered_guard")
	if battle.river and battle.run.has_relic("river_brace"):
		_mark(id, "river_brace", index)
	if _item(battle, id, "accessory", "tide_weaver_accessory") and snap.wet:
		_resource(battle, id, "tide:accessory", 2, {"hp_max_pp": 3}, "tide_weaver_accessory")
	if _item(battle, id, "weapon", "gale_runner_weapon") and int(_read_mark(id, "gale:weapon", 0)) <= index:
		var keys = _keys(battle, id, "gale:weapon", "gale_runner_weapon")
		if _ready(battle, keys, 2):
			_mark(id, "gale:weapon", index + 5)
			_count(battle, keys)
	if has_set(battle, id, "gale_runner", 3) and snap.fields.has("wind_barrier") and int(_read_mark(id, "gale:three", 0)) <= index:
		var keys = _keys(battle, id, "gale:three", "gale_runner")
		if _ready(battle, keys, 2):
			fields.erase("wind_barrier")
			_grant_shield(battle, id, 6, true)
			_mark(id, "gale:three", index + 5)
			_count(battle, keys)
	if has_set(battle, id, "stone_vow", 3) and snap.fields.has("root_cover"):
		_gear_shield(battle, id, id, "stone:three", "stone_vow", 2, 8)
	if has_set(battle, id, "dune_keeper", 3) and snap.terrain == "desert" and snap.wet:
		_resource(battle, id, "dune:guard", 2, {"hp_max_pp": 5}, "dune_keeper")
	if _item(battle, id, "accessory", "grave_wayfarer_accessory") and snap.units[id].slow >= 2:
		var keys = _keys(battle, id, "grave:accessory", "grave_wayfarer_accessory")
		if _ready(battle, keys, 2):
			battle.unit(id).slow -= 1
			_count(battle, keys)
	if has_set(battle, id, "grave_wayfarer", 3) and not snap.river:
		_gear_shield(battle, id, id, "grave:guard", "grave_wayfarer", 2, 6)
	if _item(battle, id, "accessory", "frontier_guard_accessory"):
		_resource(battle, id, "frontier:accessory", 2, {"energy_flat": 5}, "frontier_guard_accessory")
	if has_set(battle, id, "frontier_guard"):
		_gear_shield(battle, id, id, "frontier:two", "frontier_guard", 3, 4)
	if int(_read_mark(id, "frontier:repair", 0)) > index:
		_grant_shield(battle, id, 8, true)
		_erase(id, "frontier:repair")
	var other = _weakest(battle, id)
	if not other.is_empty():
		if _item(battle, id, "accessory", "oath_witness_accessory"):
			_gear_shield(battle, id, other, "oath:accessory", "oath_witness_accessory", 2, 3)
		if has_set(battle, id, "oath_witness") and _read_mark(other, "aid") == null:
			var keys = _keys(battle, id, "oath:two", "oath_witness")
			var already_active = marks.values().any(func(entries): return entries.get("aid") == id)
			if not already_active and _ready(battle, keys, 2):
				_mark(other, "aid", id)
				_count(battle, keys)
				var shorten_keys = _keys(battle, id, "oath:three:slow", "oath_witness")
				if has_set(battle, id, "oath_witness", 3) and battle.unit(other).slow >= 2 and _ready(battle, shorten_keys, 2):
					battle.unit(other).slow -= 1
					_count(battle, shorten_keys)
	_after_any(battle, id, "guard", snap)

func _after_any(battle, id: String, skill: String, snap: Dictionary) -> void:
	if snap.units[id].shield > 0 and _item(battle, id, "accessory", "stone_vow_accessory"):
		_resource(battle, id, "stone:accessory", 2, {"mp_flat": 2}, "stone_vow_accessory")
	if skill != "guard":
		_mark(id, "patient", maxi(0, int(_read_mark(id, "patient", 0)) - 1))
		_erase(id, "witness")
	last_own[id] = skill

func _fields_after(battle, id: String, element: String, snap: Dictionary, hit: bool, healed: bool, hits: Array) -> void:
	var thawed = false
	var new_wet: bool = battle.wet and not snap.wet and hit and element == "water"
	if element == "fire" and hit:
		thawed = fields.erase("frozen")
		if thawed:
			frozen_seen.clear()
		fields.erase("root_cover")
		if not battle.enemies.has(id) and thawed and battle.run.has_relic("thaw_water_vial"):
			_resource(battle, id, "thaw_water_vial", 1, {"energy_flat": 8})
	if battle.enemies.has(id) or snap.river:
		return
	var broke_ice = false
	if hit and element == "ice" and snap.fields.has("frozen") and has_set(battle, id, "rime_path", 3):
		var keys = _keys(battle, id, "rime:three", "rime_path")
		if present("frozen") and _ready(battle, keys, 2):
			fields.erase("frozen")
			frozen_seen.clear()
			broke_ice = true
			for target in hits:
				if battle.unit(target).hp > 0:
					battle.unit(target).slow = maxi(int(battle.unit(target).slow), reduce_slow(battle, target, 2))
					break
			_count(battle, keys)
	if hit and element == "fire" and snap.terrain == "forest" and not snap.rain and snap.wet \
			and not snap.fields.has("frozen") and not snap.fields.has("charged") and has_set(battle, id, "ember_warden", 3):
		var keys = _keys(battle, id, "ember:three", "ember_warden")
		if battle.wet and _ready(battle, keys, 2):
			battle.wet = false
			fields.erase("wet")
			_count(battle, keys)
	var proposals: Array = []
	if hit and element == "ice" and snap.wet and not snap.burning and not broke_ice and has_set(battle, id, "rime_path"):
		proposals.append(["frozen", "rime:two", "rime_path", 3, false])
	if hit and element == "lightning" and snap.wet and not snap.burning and has_set(battle, id, "storm_conductor"):
		proposals.append(["charged", "storm:two", "storm_conductor", 3, false])
	if hit and element == "earth" and snap.terrain in ["forest", "mountain", "swamp"] and not snap.burning and has_set(battle, id, "stone_vow"):
		proposals.append(["root_cover", "stone:two", "stone_vow", 3, false])
	if healed and snap.terrain == "forest" and not snap.burning and has_set(battle, id, "grove_mender"):
		proposals.append(["root_cover", "grove:two", "grove_mender", 3, false])
	if hit and element == "wind" and has_set(battle, id, "gale_runner"):
		proposals.append(["wind_barrier", "gale:two", "gale_runner", 3, false])
	var empty: bool = not snap.burning and not snap.wet and snap.fields.is_empty()
	if hit and element == "ice" and snap.wet and not snap.burning and not broke_ice and battle.run.has_relic("rime_thimble"):
		proposals.append(["frozen", "rime_thimble", "", 1, true])
	if hit and element == "lightning" and snap.wet and not snap.burning and battle.run.has_relic("copper_rain_comb"):
		proposals.append(["charged", "copper_rain_comb", "", 1, true])
	if hit and element == "wind" and (empty or snap.wet) and battle.run.has_relic("crossed_wind_chimes"):
		proposals.append(["wind_barrier", "crossed_wind_chimes", "", 1, true])
	if element == "guard" and (empty or snap.wet) and not snap.burning and battle.run.has_relic("rootbound_bracelet"):
		proposals.append(["root_cover", "rootbound_bracelet", "", 1, true])
	if new_wet and snap.burning and fields.has("wet") and battle.run.has_relic("field_water_sponge"):
		proposals.append(["wet", "field_water_sponge", "", 1, true])
	proposals.sort_custom(func(a, b): return a[1] < b[1] if a[0] == b[0] else FIELD_ORDER.find(a[0]) < FIELD_ORDER.find(b[0]))
	for proposal in proposals:
		var field: String = proposal[0]
		if field in ["frozen", "charged", "root_cover"] and battle.burning:
			continue
		if field in ["frozen", "charged"] and not battle.wet:
			continue
		var keys = _keys(battle, id, proposal[1], proposal[2], false, proposal[4])
		var expiry = index + (7 if field == "wet" else 5)
		if expiry <= int(fields.get(field, 0)) or not _ready(battle, keys, proposal[3]):
			continue
		if field == "frozen" and not present(field):
			frozen_seen.clear()
		fields[field] = expiry
		_count(battle, keys)
		battle.run.note("战场状态 · " + {"wet": "湿润延长", "frozen": "冰面", "charged": "导电", "root_cover": "根掩", "wind_barrier": "风障"}[field])
		break

func cast_done(battle, id: String, skill_id: String, ultimate: bool, price: int, snap: Dictionary, results: Array) -> void:
	var skill = Catalog.SKILLS[skill_id]
	var element: String = skill.element
	var hits: Array = []
	var killed = false
	var healed = false
	for result in results:
		if result.damage + result.absorbed > 0:
			hits.append(result.target)
			killed = killed or result.hp_after == 0
		if result.healing > 0 and result.hp_before > 0:
			healed = true
	var hit = not hits.is_empty()
	if hit:
		for keys in snap.claims.values():
			_count(battle, keys)
	_fields_after(battle, id, element, snap, hit, healed, hits)
	if hit:
		_after_hits(battle, id, skill_id, element, ultimate, snap, hits, killed)
	if price > 0 and not ultimate:
		if battle.run.has_relic("spent_rune_clip"):
			_resource(battle, id, "spent_rune_clip", 2, {"energy_flat": 5})
		if battle.run.has_relic("breath_reserve"):
			_mark(id, "breath")
	if healed:
		_after_heal(battle, id, snap)
	_after_any(battle, id, skill_id if hit or skill_id != "attack" else "", snap)

func _after_hits(battle, id: String, skill_id: String, element: String, ultimate: bool, snap: Dictionary, hits: Array, killed: bool) -> void:
	var first: String = hits[0]
	var starting_slow: bool = snap.units[first].slow > 0
	if starting_slow and _item(battle, id, "accessory", "rime_path_accessory"):
		_resource(battle, id, "rime:accessory", 2, {"mp_flat": 2}, "rime_path_accessory")
	if killed and element == "fire" and _item(battle, id, "accessory", "ember_warden_accessory"):
		_resource(battle, id, "ember:accessory", 2, {"mp_flat": 3}, "ember_warden_accessory")
	if element == "lightning" and _item(battle, id, "accessory", "storm_conductor_accessory"):
		_resource(battle, id, "storm:accessory", 2, {"energy_flat": 5}, "storm_conductor_accessory")
	if element == "wind":
		_erase(id, "gale:weapon")
		_erase(id, "gale:three")
	if element == "water":
		if not snap.wet and battle.wet:
			if battle.run.has_relic("dripping_spool"):
				var keys = _keys(battle, id, "dripping_spool")
				if _ready(battle, keys, 1) and _grant_shield(battle, id, 5, false):
					_count(battle, keys)
			if snap.burning and has_set(battle, id, "tide_weaver", 3):
				var keys = _keys(battle, id, "tide:three", "tide_weaver")
				var daily = _keys(battle, id, "tide:three", "tide_weaver", true)
				keys.append_array(daily)
				if _ready(battle, keys, 2):
					var gained = _grant_shield(battle, id, 4, true)
					var other = _weakest(battle, id)
					if not other.is_empty():
						gained = _grant_shield(battle, other, 4, true) or gained
					if gained:
						_count(battle, keys)
		if snap.terrain == "desert" and has_set(battle, id, "dune_keeper", 3):
			_gear_shield(battle, id, id, "dune:three", "dune_keeper", 1, 3)
		if snap.wet and battle.run.has_relic("waterline_thread"):
			_resource(battle, id, "waterline_thread", 2, {"hp_max_pp": 3})
	if starting_slow and battle.unit(first).hp > 0:
		var gear = ""
		var pp = 0
		if has_set(battle, id, "oath_witness", 3) and _ready(battle, _keys(battle, id, "oath:three", "oath_witness"), 2):
			gear = "oath_witness"
			pp = 15
		elif _item(battle, id, "weapon", "oath_witness_weapon"):
			gear = "oath_witness_weapon"
			pp = 10
		var keys = _keys(battle, id, "oath:three" if pp == 15 else "oath:weapon", gear)
		if pp > int(_read_mark(first, "wariness", 0)) and _ready(battle, keys, 2):
			_mark(first, "wariness", pp)
			_count(battle, keys)
	if skill_id == "attack":
		attacks[id] = int(attacks.get(id, 0)) + 1
		var sorted = hits.duplicate()
		sorted.sort()
		_mark(id, "track", sorted[0])
		if battle.run.has_relic("rain_listening_pin") and snap.rain:
			_resource(battle, id, "rain_listening_pin", 1, {"mp_max_pp": 3})
		if int(attacks[id]) % 3 == 0 and battle.run.has_relic("third_stitch"):
			var keys = _keys(battle, id, "third_stitch")
			if _ready(battle, keys, 2) and _grant_shield(battle, id, 6, false):
				_count(battle, keys)
		_erase(id, "patient")
	elif not ultimate and not snap.rain and battle.run.has_relic("clear_air_reed"):
		var keys = _keys(battle, id, "clear_air_reed")
		if _ready(battle, keys, 1):
			post_delay[id] = 0.85
			_count(battle, keys)
	if ultimate and battle.run.has_relic("aftersong_shell"):
		_resource(battle, id, "aftersong_shell", 1, {"mp_max_pp": 8})
	if element == "fire" and snap.burning and battle.run.has_relic("banked_ember_box"):
		_resource(battle, id, "banked_ember_box", 1, {"mp_flat": 3})
	if killed and battle.run.has_relic("closing_chime"):
		_resource(battle, id, "closing_chime", 1, {"mp_max_pp": 6})

func after_nonrelic_heal(battle, id: String, heals: Array) -> void:
	for heal in heals:
		var target: String = heal.target
		if heal.over > 0 and battle.run.has_relic("surplus_cotton"):
			var keys = _keys(battle, target, "surplus_cotton")
			var cap = floori(battle.unit(target).hp_max * 0.08)
			if _ready(battle, keys, 1) and shield_gain(battle, target, mini(cap, heal.over)) > 0:
				_count(battle, keys)
	if not battle.run.has_relic("relay_sash"):
		return
	var candidates = heals.filter(func(heal): return heal.target != id)
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a, b): return a.target < b.target if a.gain == b.gain else a.gain > b.gain)
	var recipient: String = candidates[0].target
	var keys = _keys(battle, id, "relay_sash")
	if int(_read_mark(recipient, "relay", 0)) == 0 and _ready(battle, keys, 1):
		_mark(recipient, "relay", 2)
		_count(battle, keys)

func _after_heal(battle, id: String, snap: Dictionary) -> void:
	after_nonrelic_heal(battle, id, snap.heals)
	if _item(battle, id, "accessory", "grove_mender_accessory"):
		var keys = _keys(battle, id, "grove:accessory", "grove_mender_accessory")
		for heal in snap.heals:
			if heal.over <= 0 or not _ready(battle, keys, 2):
				continue
			var amount = minf(heal.over * 0.5, battle.unit(heal.target).hp_max * 0.03)
			if shield_gain(battle, heal.target, amount, true) > 0:
				_count(battle, keys)
			break
	if snap.fields.has("root_cover") and has_set(battle, id, "grove_mender", 3):
		var other = _weakest(battle, id, true)
		var keys = _keys(battle, id, "grove:three", "grove_mender")
		if not other.is_empty() and _ready(battle, keys, 2) and _apply_resource(battle, other, {"hp_max_pp": 3}):
			_count(battle, keys)

func enemy_damage(battle, enemy: String, target: String, result: Dictionary, snap: Dictionary) -> void:
	if result.damage + result.absorbed <= 0:
		return
	for keys in snap.claims.values():
		_count(battle, keys)
	damaged_by[target] = enemy
	_erase(target, "aid")
	if result.hp_before > result.hp_after:
		hp_losses[target] = true
		if _read_mark(target, "sheltered_guard", false):
			_mark(target, "sheltered_ready")
			_erase(target, "sheltered_guard")
		var keys = _keys(battle, target, "dented_whistle")
		if battle.run.has_relic("dented_whistle") and int(_read_mark(enemy, "dented", 0)) <= index and _ready(battle, keys, 1):
			_mark(enemy, "dented", index + 3)
			_count(battle, keys)
		for other in battle.alive_allies():
			if other != target and battle.run.has_relic("witness_ribbon"):
				_mark(other, "witness", enemy)
		if result.damage * 5 > battle.unit(target).hp_max and battle.run.has_relic("impact_pad"):
			var pad = _keys(battle, target, "impact_pad")
			if _ready(battle, pad, 1) and _grant_shield(battle, target, 6, false):
				_count(battle, pad)
	if result.hp_after <= 0:
		if battle.run.has_relic("fallen_standard_tassel"):
			var keys = _keys(battle, target, "fallen_standard_tassel", "", false, true)
			if _ready(battle, keys, 1):
				var gained = false
				for other in battle.alive_allies():
					gained = _grant_shield(battle, other, 6, false) or gained
				if gained:
					_count(battle, keys)
		return
	if result.shield_before > 0 and result.shield_after == 0:
		if battle.run.has_relic("broken_ring"):
			_resource(battle, target, "broken_ring", 1, {"energy_flat": 6})
		if has_set(battle, target, "frontier_guard", 3) and int(_read_mark(target, "frontier:repair", 0)) <= index:
			var keys = _keys(battle, target, "frontier:three", "frontier_guard")
			if _ready(battle, keys, 2):
				_mark(target, "frontier:repair", index + 5)
				_count(battle, keys)

func victory(battle) -> void:
	if battle.run.has_relic("return_seam"):
		for id in battle.deployed:
			if hp_losses.has(id):
				_resource(battle, id, "return_seam", 1, {"hp_max_pp": 5})
