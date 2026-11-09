extends SceneTree
const Run = preload("res://scripts/domain/expedition.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const BattleRules = preload("res://scripts/domain/battle.gd")

func _initialize() -> void:
	call_deferred("execute")

func execute() -> void:
	var failures = 0
	for seed_value in [41, 918, 20261104]:
		if not journey(seed_value):
			failures += 1
			printerr("FAIL: Journey seed ", seed_value)
	print("FULL JOURNEYS: 3 checks, %d failures" % failures)
	quit(1 if failures else 0)

func journey(seed_value: int) -> bool:
	var r = Run.new()
	r.save_path = "user://veylodan-journey.json"
	r.new_run(seed_value, "wayfarer")
	var hero = r.actor("hero")
	hero.attack = 160
	hero.speed = 200
	hero.defense = 120
	var stages: Array[int] = []
	var steps = 0
	for cell in r.data.tiles:
		if r.boss_known():
			break
		if r.has_visited(cell) or not Hex.is_land(r.data.tiles, cell):
			continue
		var path = Hex.path(r.data.tiles, hero.position, cell)
		for next in path.slice(1):
			if hero.ap < 4 and not r.end_day().ok:
				return false
			var result = r.move(["hero"], next)
			if not result.ok:
				return false
			steps += 1
			if result.battle and not fight(r):
				return false
			while r.pending_chapter() > 0:
				var stage = r.pending_chapter()
				stages.append(stage)
				r.finish_chapter(stage)
		if r.boss_known():
			break
	if stages != [1, 2, 3, 4] or hero.name != "旅人":
		return false
	var route = Hex.path(r.data.tiles, hero.position, r.data.boss)
	for next in route.slice(1):
		if hero.ap < 4 and not r.end_day().ok:
			return false
		var result = r.move(["hero"], next)
		if not result.ok or (result.battle and not fight(r)):
			return false
		steps += 1
	if r.data.status == "exploring" and hero.position == r.data.boss:
		r.data.pending_battle = {"position": r.data.boss, "origin": r.data.boss, "movers": [], "npc": "", "ambush": false}
		if not fight(r):
			return false
	if r.data.status != "won":
		return false
	print("JOURNEY COMPLETE seed=%d steps=%d explored=%d" % [seed_value, steps, r.data.explored.size()])
	return true

func fight(r: RefCounted) -> bool:
	var b = BattleRules.new()
	if not b.begin(r, r.data.pending_battle, ["hero"]).ok:
		return false
	b.auto_mode = true
	for turn in range(30):
		if b.reveal_pending:
			b.awaken_death_power()
		b.step_auto()
		if not b.outcome.is_empty():
			break
	return b.outcome == "victory"
