extends SceneTree
const Run = preload("res://scripts/domain/expedition.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Chess = preload("res://scripts/domain/chess_battle.gd")

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
	var stages: Array[int] = []
	var steps = 0
	for cell in r.data.tiles:
		if r.boss_known():
			break
		if r.has_visited(cell) or not Hex.is_land(r.data.tiles, cell):
			continue
		var path = Hex.path(r.data.tiles, hero.position, cell)
		for next in path.slice(1):
			var result = r.move(next)
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
		var result = r.move(next)
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
	var battle := Chess.new()
	if not battle.begin(r, r.data.pending_battle, r.card_deck()).ok:
		return false
	# Keep campaign tests deterministic while playing legal turns on the real board.
	var commander := battle.commanders[Chess.PLAYER]
	commander.attack = 40
	commander.armor = 100
	for turn in range(40):
		if not battle.outcome.is_empty():
			if battle.outcome != "victory":
				return false
			r.close_battle_shop()
			r.data.erase("pending_victory")
			return true
		if battle.reveal_pending:
			battle.awaken_death_power()
		if battle.turn == Chess.ENEMY:
			battle.enemy_turn()
			continue
		var source := battle.board.find(commander)
		var target := battle.board.find(battle.commanders[Chess.ENEMY])
		var choices := battle.moves(source)
		if choices.has(target):
			battle.move(source, target)
		elif not choices.is_empty():
			var ranked := choices.keys()
			ranked.sort_custom(func(a: int, b: int):
				if choices[a] != choices[b]:
					return choices[a] == "attack"
				return Chess._distance(a, target) < Chess._distance(b, target))
			battle.move(source, ranked[0])
		else:
			for index in battle.hands[Chess.PLAYER].size():
				var targets := battle.card_targets(Chess.PLAYER, index)
				if not targets.is_empty():
					battle.play(index, targets[0])
					break
		if battle.can_act():
			battle.end_turn()
	return false
