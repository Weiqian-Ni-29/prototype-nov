extends RefCounted

const Journey = preload("res://scripts/domain/journey.gd")

static func battle(run: RefCounted, enemies: Array, ambush: bool = false) -> Dictionary:
	var camp: String = run.actor("hero").position
	return {"position": camp, "origin": camp, "npc": "", "ambush": ambush, "enemies": enemies}

static func stage_battle(run: RefCounted, enemies: Array, ambush: bool = false) -> Dictionary:
	var kind := "boss" if "war_god" in enemies else "elite" if Journey.is_elite(enemies) else "battle"
	var step := Journey.STOPS - 1 if kind == "boss" else int(run.data.journey.step)
	_stage(run, kind, step)
	var encounter := battle(run, enemies, ambush)
	encounter.journey_step = step
	run.data.pending_battle = encounter
	return encounter

static func shop(run: RefCounted, recruit: String = "") -> String:
	_stage(run, "shop", mini(int(run.data.journey.step), Journey.STOPS - 2))
	run.open_battle_shop()
	var camp: String = run.actor("hero").position
	if not recruit.is_empty():
		var seed := int(run.data.journey.seed)
		while recruit not in run.recruit_shop_offers(camp):
			seed += 1
			run.data.journey.seed = str(seed)
	return camp

static func _stage(run: RefCounted, kind: String, step: int) -> void:
	run.close_battle_shop()
	run.data.pending_battle = {}
	run.data.erase("pending_victory")
	var journey: Dictionary = run.data.journey
	journey.step = step
	journey.history.resize(step)
	for index in step:
		if journey.history[index] == null:
			journey.history[index] = {"kind": "rest", "choice": 0, "settled": true, "text": "",
				"hp_before": 95, "coins_before": 8, "hp_change": 0, "coins_change": 0}
	var choice: int = {"battle": 1, "elite": 2}.get(kind, 0)
	journey.history.append({"kind": kind, "choice": choice, "settled": false, "text": "",
		"hp_before": run.actor("hero").hp, "coins_before": run.data.lamp_coins})

static func old_save(data: Dictionary, version: int, keep_journey: bool = false) -> void:
	data.version = version
	data.tiles = {data.start: {"base_terrain": data.village}}
	data.peace = {}
	if not keep_journey:
		data.erase("journey")
