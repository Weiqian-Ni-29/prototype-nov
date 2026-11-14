extends RefCounted

const Cards = preload("res://scripts/domain/card_catalog.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Gear = preload("res://scripts/domain/gear_catalog.gd")
const Nodes = preload("res://scripts/domain/map_nodes.gd")
const RelicRules = preload("res://scripts/domain/chess_relics.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
const COLS = 3
const ROWS = 4
const PLAYER = 0
const ENEMY = 1
const MANA_LIMIT = 10
const ENEMY_DECK_SIZE = 12
const COMMANDER_DEFEAT_SCORE = 1000000
const ENEMY_DECK_SPECIALTIES = {
	"guard": ["ward", "brace"],
	"charge": ["pike", "ember_spell"],
	"slow": ["ice_spell", "ward"],
	"wet": ["ice_spell", "mend_spell"],
	"ignite": ["ember_spell", "ember_spell"],
	"heal": ["mend_spell", "bandage_card"],
	"madness": ["ember_spell", "pike"],
}

var run: RefCounted
var pending: Dictionary
var position: String
var board: Array[Dictionary] = []
var commanders: Array[Dictionary] = []
var hands: Array = [[], []]
var piles: Array = [[], []]
var fatigue: Array[int] = [0, 0]
var draw_count := 0
var round_number := 1
var mana: Array[int] = [1, 1]
var mana_capacity: Array[int] = [1, 1]
var turn := PLAYER
var turns_started: Array[int] = [0, 0]
var board_action_used: Array[bool] = [false, false]
var enemy_turn_started := false
var last_enemy_action := {}
var played_cards: Array[Dictionary] = []
var last_attack := {}
var difficulty := 0
var exploration := 0
var outcome := ""
var reveal_pending := false
var river := false
var final_battle := false
var log_lines: Array[String] = []
var enemy_types: Array = []
var participants: Array[String] = ["hero"]
var initial_hero_hp := 0
var initial_board_hp := 0
var initial_board_hp_max := 0
var uid_serial := 0
var relic_ids: Array = []
var relic_used: Dictionary = {}
var prep := ""
var public_preview := false
var revealed_enemy: Array = []
var deployments := 0
var action_kind := ""
var previous_action := ""
var player_actions := 0
var defense_played := false
var enemy_losses := 0
var ally_losses := 0
var life_seed_active := false

func relic_name(id: String) -> String:
	return Relics.DATA[id].name

func _relic(event: String, context: Dictionary = {}) -> void:
	RelicRules.fire(self, event, context)

func begin(expedition: RefCounted, encounter: Dictionary, deck: Array) -> Dictionary:
	if expedition.data.status != "exploring" or not Cards.valid_deck(deck, expedition.data.actors, true, expedition.data):
		var message := "出战至少需要 %d 张牌。" % Cards.MIN_DECK_SIZE if deck.size() < Cards.MIN_DECK_SIZE else "这套牌组无法出战。"
		return {"ok": false, "message": message}
	var cell: String = encounter.get("position", "")
	var hero: Dictionary = expedition.actor("hero")
	if not expedition.data.tiles.has(cell) or hero.position != cell or hero.hp <= 0:
		return {"ok": false, "message": "旅人需要在遭遇地点，且能行动。"}
	var npc: String = encounter.get("npc", "")
	var types: Array = expedition.data.tiles[cell].enemies.duplicate()
	if not npc.is_empty():
		var opponent: Dictionary = expedition.actor(npc)
		if opponent.is_empty() or opponent.hp <= 0 or opponent.position != cell:
			return {"ok": false, "message": "对手无法出战。"}
		types = ["npc:" + npc]
	if types.is_empty():
		return {"ok": false, "message": "这里没有敌人。"}
	run = expedition
	relic_ids = run.data.relic_attunement.duplicate()
	life_seed_active = run.data.relic_effect_flags.has("life_seed_applied")
	prep = run.prepared_relic if run.prepared_relic in run.preparation_options() else ""
	position = cell
	pending = encounter.duplicate(true)
	enemy_types = types
	final_battle = "war_god" in types
	var source := "battle:%s:%s" % [cell, npc]
	var elite: bool = is_elite_encounter(run, cell, pending)
	exploration = run.exploration_percent()
	difficulty = difficulty_tier(exploration, elite, final_battle)
	if not run.data.battle_offers.has(source):
		run.data.battle_offers[source] = run.relic_offer(source, Relics.DATA.keys(), 1.0 if elite else 0.30)
	pending.merge({"battle_uid": source, "reward_tier": "elite" if elite else "ordinary",
		"relic_offer": run.data.battle_offers[source]}, true)
	run.data.pending_battle = pending.duplicate(true)
	var inventory_before: Dictionary = run.data.relic_inventory.duplicate()
	if prep == "bitter_exchange_vial" and ceili(float((int(commander_definition(run).hp) + int(life_seed_active)) * hero.hp) / hero.hp_max) <= 2:
		return {"ok": false, "message": "主战者生命不足，不能携带苦酿换息瓶。"}
	var revision_before: int = int(run.data.item_revision)
	if not prep.is_empty():
		run.consume_prepared_relic(prep)
	var saved: Dictionary = run.save_game()
	if not saved.ok:
		run.data.relic_inventory = inventory_before
		run.data.item_revision = revision_before
		run.prepared_relic = prep
		return saved

	for square in COLS * ROWS:
		board.append({})
	var boss_type: String = "war_god" if final_battle else str(types[0])
	board[10] = _piece(commander_definition(run), PLAYER, true)
	board[1] = _piece(enemy_definition(run, boss_type, true, difficulty), ENEMY, true)
	commanders.assign([board[10], board[1]])
	initial_hero_hp = int(hero.hp)
	board[10].hp = maxi(1, ceili(float(board[10].hp_max * hero.hp) / hero.hp_max))
	initial_board_hp = int(board[10].hp)
	initial_board_hp_max = int(board[10].hp_max)
	var roller := RandomNumberGenerator.new()
	roller.seed = hash("%d:card-battle:%s:%d" % [int(run.data.seed), source, int(run.data.battles)])
	piles[PLAYER] = deck.duplicate()
	_shuffle(piles[PLAYER], roller)
	if int(run.data.battles) == 0:
		_ensure_opening_attack()
	piles[ENEMY] = _enemy_deck(types, boss_type, roller)
	_draw(PLAYER, Cards.OPENING_HAND)
	_draw(ENEMY, Cards.OPENING_HAND)
	_relic("opening")
	RelicRules.prepare(self, prep)
	# Reveal after all public opening effects have been applied.
	run.data.status = "battle"
	run.data.battles += 1
	run.note("战棋对战开始。")
	turn = ENEMY if pending.get("ambush", false) else PLAYER
	if turn == PLAYER:
		_start_turn(PLAYER)
	return {"ok": true}

func _shuffle(pile: Array, roller: RandomNumberGenerator) -> void:
	for i in range(pile.size() - 1, 0, -1):
		var j := roller.randi_range(0, i)
		var entry: Variant = pile[i]
		pile[i] = pile[j]
		pile[j] = entry

static func is_elite_encounter(expedition: RefCounted, cell: String, encounter: Dictionary = {}) -> bool:
	return expedition.node_at(cell).get("kind") == "elite" or encounter.get("reward_tier") == "elite" \
		or Nodes.is_elite(expedition.data.tiles.get(cell, {}).get("enemies", []))

static func difficulty_tier(progress: int, elite: bool, finale: bool) -> int:
	if finale:
		return 4
	return mini(4, floori(progress / 20.0) + int(elite))

static func difficulty_name(tier: int) -> String:
	return ["入门", "初阶", "进阶", "险峻", "极险"][clampi(tier, 0, 4)]

func _ensure_opening_attack() -> void:
	var deck: Array = piles[PLAYER]
	for i in deck.size():
		var card := definition(deck[i])
		if card.cost <= mana[PLAYER] and (card.has("damage") or card.get("slot") == "weapon"):
			if i >= Cards.OPENING_HAND:
				var replaced: String = deck[Cards.OPENING_HAND - 1]
				deck[Cards.OPENING_HAND - 1] = deck[i]
				deck[i] = replaced
			return

func _enemy_deck(types: Array, lead: String, roller: RandomNumberGenerator) -> Array:
	var support: Array[String] = []
	for id in types + ["boar", "archer", "spider", "apothecary", "swarm"]:
		if id != lead and id not in support:
			support.append(id)
	var deck: Array = []
	for id in support.slice(0, difficulty):
		deck.append("foe:" + id)
	deck.append_array(["blade", "brace", "ward", "mend_spell"])
	var leader: Dictionary = run.actor(lead.trim_prefix("npc:")) if lead.begins_with("npc:") else Catalog.ENEMIES[lead]
	var specialty: String = leader.get("skill", "")
	if lead.begins_with("npc:"):
		specialty = {"fire": "ignite", "water": "wet", "ice": "slow", "earth": "guard"}.get(
			Cards.chess_element(leader), "charge" if leader.get("attack_delivery") == "ranged" else "guard")
	deck.append_array(ENEMY_DECK_SPECIALTIES.get(specialty, ["blade", "brace"]))
	var filler := ["pike", "ward", "ember_spell", "brace", "ice_spell", "mend_spell",
		"blade", "pike", "ember_spell", "ice_spell", "ward", "mend_spell", "brace"]
	for id in filler:
		if deck.size() == ENEMY_DECK_SIZE:
			break
		if deck.count(id) < 2:
			deck.append(id)
	_shuffle(deck, roller)
	return deck

static func commander_definition(expedition: RefCounted) -> Dictionary:
	var hero: Dictionary = expedition.actor("hero")
	var attack := 4
	var armor := 1
	return {"name": hero.name, "portrait": "hero", "element": "ice", "attack": attack, "hp": 13,
		"armor": armor, "move": 1, "range": 1, "diagonal": true, "trait": "横竖斜走一格。"}

static func enemy_definition(expedition: RefCounted, id: String, leader: bool = false, tier: int = -1) -> Dictionary:
	var npc := id.begins_with("npc:")
	var actor_id := id.trim_prefix("npc:")
	var source: Dictionary = expedition.actor(actor_id) if npc else expedition.war_god_stats() if id == "war_god" else Catalog.ENEMIES[id]
	var ranged: bool = source.get("attack_delivery") == "ranged"
	if tier < 0:
		var cell: String = expedition.actor("hero").position
		tier = difficulty_tier(expedition.exploration_percent(), is_elite_encounter(expedition, cell), id == "war_god")
	var hp := maxi(4, roundi(float(source.hp) / (13.0 if leader else 19.0)))
	var attack := maxi(2, roundi(float(source.attack) / 7.0))
	var armor := 1 if leader or not ranged else 0
	var reach := 2 if ranged else 1
	if leader:
		if id == "war_god":
			hp += 3
		else:
			hp = 8 + tier * 2 + int(hp >= 6)
			attack = clampi(attack, 2, 3) + floori(tier / 2.0)
			armor = 1 + int(tier >= 3)
			if tier == 0:
				reach = 1
	else:
		hp = clampi(hp, 3, 6) + floori(tier / 2.0)
		attack = clampi(attack, 2, 4)
	var healer := id == "apothecary"
	var movement := "横竖斜走一格。" if leader else "横竖走一格。"
	if reach == 2:
		movement += "可沿无阻挡的直线攻击两格。"
	if healer:
		movement += "落位时治疗相邻友方。"
	return {"name": source.name, "kind": "partner", "cost": 2, "portrait": actor_id if npc or id == "war_god" else "",
		"enemy_art": "" if npc or id == "war_god" else id, "element": "fire" if id == "war_god" else Cards.chess_element(source),
		"attack_delivery": source.get("attack_delivery", "melee"),
		"attack_projectile": "arrow" if id == "archer" or Cards.is_archer(source) else "energy",
		"attack": attack, "hp": hp, "armor": armor, "move": 1, "range": reach, "heal": 2 if healer else 0,
		"diagonal": leader, "trait": movement}

func definition(id: String) -> Dictionary:
	if id.begins_with("temp:"):
		var entry := Cards.definition(id.trim_prefix("temp:")).duplicate()
		entry.temporary = true
		if entry.kind == "weapon":
			entry.kind = "equipment"
			entry.slot = "weapon"
		return entry
	return enemy_definition(run, id.trim_prefix("foe:"), false, difficulty) if id.begins_with("foe:") else Cards.owned_definition(id, run.data.actors, run.data)

func _piece(entry: Dictionary, side: int, leader: bool = false) -> Dictionary:
	var piece := entry.duplicate()
	uid_serial += 1
	piece.merge({"side": side, "leader": leader, "weapon": "", "gear": {}, "uid": uid_serial}, true)
	if side == PLAYER:
		piece.hp += int(life_seed_active)
		if "lamp_badge" in relic_ids:
			piece.armor += roundi(float(piece.hp) * 0.12)
	piece.hp_max = piece.hp
	return piece

func attack_power(piece: Dictionary) -> int:
	return maxi(0, int(piece.attack) + int(_weapon(piece).get("attack", 0))
		- (1 if river and piece.side == ENEMY else 0))

func _weapon(piece: Dictionary) -> Dictionary:
	return equipment_at(piece, "weapon")

func equipment_at(piece: Dictionary, slot: String) -> Dictionary:
	var item: Dictionary = piece.get("gear", {}).get(slot, {})
	if item.is_empty() and slot == "weapon":
		return Cards.ACTIONS.get(piece.get("weapon", ""), {})
	return item

func _attack_range(piece: Dictionary) -> int:
	return mini(3, maxi(int(piece.get("range", piece.get("move", 1))), int(_weapon(piece).get("range", 0))) + int(piece.get("sight", 0)))

func _open_line(from: int, target: int, reach: int) -> bool:
	var length := _distance(from, target)
	if length == 0 or length > reach or (from % COLS != target % COLS and _row(from) != _row(target)):
		return false
	var step := int(float(target - from) / length)
	for offset in range(1, length):
		if not board[from + step * offset].is_empty():
			return false
	return true

func _spell_in_range(side: int, target: int) -> bool:
	for from in board.size():
		if board[from].get("side", -1) == side and _open_line(from, target, 2):
			return true
	return false

func moves(from: int) -> Dictionary:
	var options := {}
	if from < 0 or from >= board.size() or board[from].is_empty():
		return options
	var actor: Dictionary = board[from]
	var walking := maxi(int(actor.get("move", 1)), int(actor.get("ready_move", 0)))
	var slowed := int(actor.get("slow_until", 0)) >= round_number
	if slowed:
		walking = 1
	var range_attack := _attack_range(actor)
	for target in board.size():
		var other: Dictionary = board[target]
		if target == from or other.get("side", -1) == actor.side:
			continue
		var dx := absi(from % COLS - target % COLS)
		var dy := absi(_row(from) - _row(target))
		var length := dx + dy
		var straight := dx == 0 or dy == 0
		var strike := not other.is_empty()
		var diagonal: bool = actor.get("diagonal", false) or (not strike and actor.get("ready_diagonal", false))
		var bend: bool = not strike and not slowed and actor.get("bend_move", false) and dx == 1 and dy == 1 and ((_row(target) >= 2) == (actor.side == PLAYER)) \
			and (board[_row(from) * COLS + target % COLS].is_empty() or board[_row(target) * COLS + from % COLS].is_empty())
		if not (bend or (diagonal and maxi(dx, dy) == 1) or (straight and length <= (range_attack if strike else walking))):
			continue
		if straight and length > 1:
			var step := floori(float(target - from) / length)
			var blocked := false
			for offset in range(1, length):
				if not board[from + step * offset].is_empty():
					blocked = true
					break
			if blocked:
				continue
		options[target] = "attack" if strike else "move"
	return options

func card_targets(side: int, index: int) -> Array[int]:
	var targets: Array[int] = []
	if index < 0 or index >= hands[side].size():
		return targets
	var card := definition(hands[side][index])
	if card.is_empty() or card.cost > mana[side]:
		return targets
	for square in board.size():
		var piece: Dictionary = board[square]
		if card.kind == "partner":
			if piece.is_empty() and ((_row(square) >= 2) == (side == PLAYER)):
				targets.append(square)
		elif card.has("damage"):
			if not piece.is_empty() and piece.side != side and _spell_in_range(side, square):
				targets.append(square)
		elif piece.get("side", -1) == side:
			match card.kind:
				"defense":
					if not card.get("cup", false) or not piece.leader:
						targets.append(square)
				"weapon", "equipment":
					targets.append(square)
				"spell":
					if card.has("heal") and piece.hp < piece.hp_max:
						targets.append(square)
	return targets

func can_act(side: int = PLAYER) -> bool:
	return turn == side and outcome.is_empty() and not reveal_pending

func can_move_piece(side: int = PLAYER) -> bool:
	return can_act(side) and not board_action_used[side]

func take_attack() -> Dictionary:
	var attack := last_attack
	last_attack = {}
	return attack

func move(from: int, target: int, side: int = PLAYER) -> bool:
	if not can_move_piece(side) or not moves(from).has(target) or board[from].side != side:
		return false
	last_attack = {}
	var kind := "move" if board[target].is_empty() else "attack"
	_move_piece(from, target)
	board_action_used[side] = true
	_complete_action(side, kind)
	return true

func play(index: int, target: int, side: int = PLAYER) -> bool:
	if not can_act(side) or target not in card_targets(side, index):
		return false
	last_attack = {}
	var card := definition(hands[side][index])
	var before := _card_board_snapshot()
	var slot := Cards.equipment_slot(card)
	var replaced: String = equipment_at(board[target], slot).get("name", "") if not slot.is_empty() else ""
	_play_card(side, index, target)
	_complete_action(side, "damage_spell" if card.has("damage") else card.kind)
	var after := _card_board_snapshot()
	played_cards.append({"side": side, "round": round_number, "card": card.duplicate(true),
		"target": target, "slot": slot, "effects": _card_effects(target, before, after, slot, replaced)})
	return true

func _card_board_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for unit in board:
		snapshot.append({} if unit.is_empty() else {"name": unit.name, "hp": unit.hp, "hp_max": unit.hp_max,
			"armor": unit.armor, "attack": attack_power(unit), "slow": int(unit.get("slow_until", 0))})
	return snapshot

func _card_effects(target: int, before: Array[Dictionary], after: Array[Dictionary], slot: String, replaced: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for square in board.size():
		var old := before[square]
		var current := after[square]
		if square != target and old == current:
			continue
		var name: String = current.get("name", old.get("name", square_name(square)))
		var changes: Array[String] = []
		if old.is_empty():
			changes.append("部署到%s" % square_name(square))
		elif current.is_empty():
			changes.append("倒下")
		else:
			for stat in [["hp", "生命"], ["armor", "护甲"], ["attack", "攻击"], ["hp_max", "生命上限"]]:
				var delta := int(current[stat[0]]) - int(old[stat[0]])
				if delta != 0:
					changes.append("%s %+d" % [stat[1], delta])
			if int(current.slow) > int(old.slow):
				changes.append("减速")
		if square == target and not replaced.is_empty():
			changes.append("「%s」回到手牌" % replaced)
		if changes.is_empty():
			changes.append("已装备" if not slot.is_empty() else "选定目标")
		var result := {"square": square, "name": name, "summary": " · ".join(changes)}
		if square == target:
			results.push_front(result)
		else:
			results.append(result)
	return results

func end_turn() -> bool:
	if not can_act():
		return false
	last_attack = {}
	_relic("turn_end")
	turn = ENEMY
	last_enemy_action = {}
	return true

func _complete_action(side: int, kind: String) -> void:
	if side == PLAYER:
		action_kind = kind
		player_actions += 1
		_relic("action_end")
		previous_action = kind
	_check_outcome()

func enemy_turn(hold_for_display: bool = false) -> void:
	while can_act(ENEMY):
		_enemy_step()
		if hold_for_display:
			return

func _enemy_step() -> void:
	last_attack = {}
	if not enemy_turn_started:
		enemy_turn_started = true
		_start_turn(ENEMY)
		if not can_act(ENEMY):
			return
	var action := _choose_enemy_action()
	if action.has("from"):
		var unit: Dictionary = board[action.from]
		var target: Dictionary = board[action.target]
		var message := "%s 移动到%s" % [unit.name, square_name(action.target)] if target.is_empty() else "%s 攻击 %s" % [unit.name, target.name]
		last_enemy_action = {"message": message, "from": action.from, "target": action.target}
		move(action.from, action.target, ENEMY)
	elif action.has("card_index"):
		var card: Dictionary = action.card
		last_enemy_action = {"message": "打出「%s」" % card.name, "target": action.target, "card": card}
		play(action.card_index, action.target, ENEMY)
	else:
		enemy_turn_started = false
		_start_turn(PLAYER)

func _enemy_tempo(option: Dictionary) -> int:
	if option.has("from") and board[option.target].is_empty():
		var hero_square: int = board.find(commanders[PLAYER])
		return 3 * (_distance(option.from, hero_square) - _distance(option.target, hero_square))
	if option.has("card") and option.card.kind == "defense" and board[option.target].armor >= 3:
		return -5
	return 0

func _choose_enemy_action() -> Dictionary:
	var options: Array[Dictionary] = []
	if can_move_piece(ENEMY):
		for square in board.size():
			if board[square].get("side", -1) == ENEMY:
				for target in moves(square):
					options.append({"from": square, "target": target})
	var seen_cards := {}
	for index in hands[ENEMY].size():
		var id: String = hands[ENEMY][index]
		if seen_cards.has(id):
			continue
		seen_cards[id] = true
		var card := definition(id)
		for target in card_targets(ENEMY, index):
			options.append({"card_index": index, "id": id, "card": card, "target": target})

	var best := {}
	var best_reply_score := -COMMANDER_DEFEAT_SCORE - 1
	var best_position_score := -COMMANDER_DEFEAT_SCORE - 1
	var next_player_round := turns_started[PLAYER] > 0
	var player_draws_fatigue: bool = next_player_round and piles[PLAYER].is_empty()
	var current_score := _position_score()
	for option in options:
		var preview := _copy_public_position()
		if option.has("from"):
			preview._move_piece(option.from, option.target)
		else:
			preview._apply_card(ENEMY, option.id, option.card, option.target)
			# Keep the enemy from cycling between sidegrades for no board benefit.
			var slot := Cards.equipment_slot(option.card)
			if not slot.is_empty() and not equipment_at(board[option.target], slot).is_empty() \
					and preview._position_score() <= current_score:
				continue
		if preview.commanders[PLAYER].hp <= 0:
			return option
		if preview.commanders[ENEMY].hp <= 0:
			continue
		if next_player_round:
			preview.round_number += 1
			if player_draws_fatigue:
				preview._fatigue(PLAYER)

		var tempo := _enemy_tempo(option)
		var position_score: int = preview._position_score() + tempo
		# The opponent can only lower this score. Skip a branch once it cannot beat best.
		var minimum_reply_score := best_reply_score + (0 if position_score > best_position_score else 1)
		if position_score < minimum_reply_score:
			continue
		var reply_score: int = preview._score_player_reply(position_score - tempo, minimum_reply_score - tempo) + tempo
		if reply_score > best_reply_score or (reply_score == best_reply_score and position_score > best_position_score):
			best = option
			best_reply_score = reply_score
			best_position_score = position_score
	return best

func _copy_public_position() -> RefCounted:
	# The preview owns its board and has no expedition, hand, or deck data.
	var preview: RefCounted = get_script().new()
	preview.board = board.duplicate(true)
	for commander in commanders:
		preview.commanders.append(preview.board[board.find(commander)])
	preview.fatigue = fatigue.duplicate()
	preview.final_battle = final_battle
	preview.river = river
	preview.uid_serial = uid_serial
	preview.public_preview = true
	preview.relic_ids = relic_ids.duplicate()
	preview.relic_used = relic_used.duplicate(true)
	preview.prep = prep
	preview.round_number = round_number
	preview.turns_started = turns_started.duplicate()
	preview.player_actions = player_actions
	preview.previous_action = previous_action
	preview.ally_losses = ally_losses
	preview.enemy_losses = enemy_losses
	preview.deployments = deployments
	preview.life_seed_active = life_seed_active
	return preview

func _score_player_reply(position_score: int, minimum_score: int) -> int:
	if position_score == COMMANDER_DEFEAT_SCORE:
		return position_score
	# An unknown card play may leave the board intact. Evaluate the visible moves and attacks.
	var worst := position_score
	for square in board.size():
		if board[square].get("side", -1) != PLAYER:
			continue
		for target in moves(square):
			var reply := _copy_public_position()
			reply._move_piece(square, target)
			worst = mini(worst, reply._position_score())
			if worst == -COMMANDER_DEFEAT_SCORE or worst < minimum_score:
				return worst
	return worst

func _position_score() -> int:
	if commanders[PLAYER].hp <= 0:
		return COMMANDER_DEFEAT_SCORE
	if commanders[ENEMY].hp <= 0:
		return -COMMANDER_DEFEAT_SCORE
	var leader_squares := [board.find(commanders[PLAYER]), board.find(commanders[ENEMY])]
	var score := 0
	for square in board.size():
		var piece: Dictionary = board[square]
		if piece.is_empty():
			continue
		var opponent: int = leader_squares[1 - int(piece.side)]
		var distance_to_attack := maxi(0, _distance(square, opponent) - _attack_range(piece))
		var value := attack_power(piece) * 2 + (2 if square % COLS == 1 else 0)
		if piece.leader:
			value += int(piece.hp) * 6 + mini(int(piece.armor), 6) * 3 - distance_to_attack
		else:
			value += 12 + int(piece.hp) * 2 + mini(int(piece.armor), 6) * 2 - distance_to_attack * 2
		score += value if piece.side == ENEMY else -value
	return score

func _start_turn(side: int) -> void:
	turn = side
	board_action_used[side] = false
	turns_started[side] += 1
	if turns_started[side] > 1:
		_grow_mana(side)
		if side == PLAYER:
			round_number += 1
		_draw(side)
	if not _check_outcome() and side == PLAYER:
		_relic("turn_start")

func _grow_mana(side: int) -> void:
	mana_capacity[side] = mini(MANA_LIMIT, mana_capacity[side] + 1)
	mana[side] = mana_capacity[side]

func _draw(side: int, count: int = 1) -> void:
	var drawn := 0
	for i in count:
		if not piles[side].is_empty():
			hands[side].append(piles[side].pop_front())
			drawn += 1
		else:
			_fatigue(side)
			if commanders[side].hp <= 0:
				break
	if side == ENEMY and count == 1 and drawn > 0:
		_relic("enemy_draw", {"card": hands[side][-1]})
	if side == PLAYER:
		draw_count += drawn
		if drawn > 0:
			_log("开局抽 %d 张牌。" % drawn if count > 1 else "抽到「%s」。" % definition(hands[side][-1]).name)

func _fatigue(side: int) -> void:
	fatigue[side] += 1
	var ctx := {"amount": fatigue[side]}
	if side == PLAYER:
		_relic("fatigue", ctx)
	var damage := int(ctx.amount)
	_log("%s牌库已空，所有在场棋子各受 %d 点疲劳伤害。" % ["己方" if side == PLAYER else "敌方", damage])
	for square in board.size():
		var piece: Dictionary = board[square]
		if piece.get("side", -1) == side:
			_damage(piece, damage)
			if piece.hp <= 0:
				_remove_piece(square, {})

	if side == PLAYER and commanders[PLAYER].hp > 0:
		_relic("after_fatigue")

func _remove_piece(square: int, context: Dictionary) -> void:
	var piece: Dictionary = board[square]
	board[square] = {}
	_log("%s倒下。" % piece.name)
	if piece.leader:
		return
	if piece.side == PLAYER:
		ally_losses += 1
		_relic("loss", {"victim": piece})
	elif not context.is_empty():
		enemy_losses += 1
		_relic("kill", context)

func _damage(piece: Dictionary, damage: int, pierce: int = 0) -> int:
	var absorbed := mini(int(piece.armor), maxi(0, damage - pierce))
	piece.armor -= absorbed
	# Spend equipment armor first so a later swap removes only unspent gear armor.
	var remaining := absorbed
	for slot in Gear.SLOTS:
		if remaining == 0:
			break
		var item: Dictionary = piece.get("gear", {}).get(slot, {})
		var used := mini(remaining, int(item.get("armor_remaining", 0)))
		if used > 0:
			item.armor_remaining -= used
			remaining -= used
	var phase_floor := 1 if final_battle and not river and piece.leader and piece.side == ENEMY else 0
	piece.hp = maxi(phase_floor, int(piece.hp) - (damage - absorbed))
	return absorbed

func _move_piece(from: int, target: int) -> void:
	var piece: Dictionary = board[from]
	var opponent: Dictionary = board[target]
	var context := _attack_context(from, target)
	if not opponent.is_empty():
		_exchange_hits(from, target, context)
		if piece.hp <= 0 or opponent.hp > 0:
			return
		_log("%s占据%s。" % [piece.name, square_name(target)])
	else:
		_log("%s走到%s。" % [piece.name, square_name(target)])
		piece.erase("ready_move")
		piece.erase("ready_diagonal")
		piece.erase("bend_move")
	board[from] = {}
	board[target] = piece
	if piece.side == PLAYER:
		_relic("move" if opponent.is_empty() else "occupy", context)
	elif not piece.leader and _row(from) < 2 and _row(target) >= 2:
		_relic("enemy_advance")
	_heal_adjacent(target)

func _attack_context(from: int, target: int) -> Dictionary:
	var unit: Dictionary = board[from]
	var victim: Dictionary = board[target]
	return {"unit": unit, "victim": victim, "from": from, "square": target, "kind": "attack",
		"distance": maxi(absi(from % COLS - target % COLS), absi(_row(from) - _row(target))),
		"element": unit.element, "armor_before": victim.get("armor", 0), "bonus": 0, "pierce": 0, "block": 0}

func _exchange_hits(from: int, target: int, strike: Dictionary) -> void:
	var counter := _attack_context(target, from)
	var attacker: Dictionary = strike.unit
	var defender: Dictionary = strike.victim
	if not public_preview:
		last_attack = {"from": from, "target": target, "attacker": attacker.duplicate(true),
			"defender": defender.duplicate(true), "distance": strike.distance}
	if attacker.side == PLAYER:
		_relic("attack", strike)
	attacker.erase("sight")
	var damage := _hit_damage(attack_power(strike.unit), strike)
	var retaliation := _hit_damage(attack_power(counter.unit), counter)
	# Resolve both hits before either one can trigger healing, extra armor, or removal.
	_apply_hit(damage, strike)
	_apply_hit(retaliation, counter)
	_finish_hit(strike)
	_finish_hit(counter)
	if not public_preview:
		last_attack.merge(_hit_result(strike))
		last_attack.retaliation = _hit_result(counter)

func _hit_damage(base: int, context: Dictionary) -> int:
	if context.victim.side == PLAYER:
		_relic("incoming", context)
	return maxi(0, base + mini(2, int(context.bonus)) - int(context.block))

func _apply_hit(damage: int, context: Dictionary) -> void:
	var victim: Dictionary = context.victim
	var old_hp: int = victim.hp
	var absorbed := _damage(victim, damage, int(context.pierce))
	context.hp_loss = old_hp - int(victim.hp)
	context.armor_loss = absorbed
	context.hp_after = victim.hp
	context.armor_after = victim.armor
	_log("%s受到%d 点%s伤害%s。" % [victim.name, damage,
		Cards.ELEMENTS.get(context.element, ""), "（护甲吸收 %d）" % absorbed if absorbed > 0 else ""])

func _finish_hit(context: Dictionary) -> void:
	var victim: Dictionary = context.victim
	if victim.side == PLAYER and victim.hp > 0:
		_relic("survive", context)
	if victim.side == ENEMY:
		_relic("hit", context)
	if victim.hp <= 0:
		_remove_piece(context.square, context)

func _hit_result(context: Dictionary) -> Dictionary:
	return {"hp_loss": context.hp_loss, "armor_loss": context.armor_loss,
		"hp": context.hp_after, "armor": context.armor_after, "lethal": context.hp_after <= 0}

func _deal_hit(base: int, context: Dictionary) -> void:
	_apply_hit(_hit_damage(base, context), context)
	_finish_hit(context)

func _play_card(side: int, index: int, target: int) -> void:
	var id: String = hands[side].pop_at(index)
	if side == ENEMY:
		revealed_enemy.erase(id)
	var card := definition(id)
	var slot := Cards.equipment_slot(card)
	var previous_id := ""
	var previous: Dictionary = {}
	if not slot.is_empty():
		var piece: Dictionary = board[target]
		previous = equipment_at(piece, slot)
		previous_id = previous.get("card_id", piece.get("weapon", "") if slot == "weapon" else "")
	mana[side] -= int(card.cost)
	if not previous_id.is_empty():
		hands[side].append(previous_id)
		if side == ENEMY:
			revealed_enemy.append(previous_id)
	_apply_card(side, id, card, target)
	if not previous_id.is_empty():
		_log("「%s」已回到%s手牌。" % [previous.name, "敌方" if side == ENEMY else "己方"])
	if side == PLAYER and card.kind == "partner" and run.actor(id).get("joined", false) and id not in participants:
		participants.append(id)

func _apply_card(side: int, id: String, card: Dictionary, target: int) -> void:
	var piece := board[target]
	match card.kind:
		"partner":
			board[target] = _piece(card, side)
			_log("%s部署到%s。" % [card.name, square_name(target)])
			if side == PLAYER:
				deployments += 1
				_relic("deploy", {"unit": board[target], "square": target})
				RelicRules.prepared_deploy(self, board[target])
			_heal_adjacent(target)
		"spell":
			if card.has("damage"):
				var element: String = card.element
				var context := {"unit": {}, "victim": piece, "square": target, "kind": "spell",
					"element": element, "id": id, "bonus": 0, "pierce": 0, "block": 0,
					"armor_before": piece.armor}
				if side == PLAYER:
					_relic("spell", context)
				_deal_hit(int(card.damage), context)
				if card.get("slow", false) and piece.hp > 0:
					piece.slow_until = round_number + int(side == ENEMY and turns_started[PLAYER] > 0)
			elif card.has("heal"):
				_heal(piece, int(card.heal), "spell")
		"weapon", "equipment":
			_equip_card(side, id, card, target)
		"defense":
			for square in board.size():
				if square != target and not (card.get("column", false) and square % COLS == target % COLS) \
						and not (card.get("row", false) and _row(square) == _row(target)):
					continue
				var ally: Dictionary = board[square]
				if ally.get("side", -1) == side:
					ally.armor += int(card.armor)
					_heal(ally, int(card.get("heal", 0)), "defense")
			if card.get("cup", false):
				var leader: Dictionary = commanders[side]
				if _neighbors(target, board.find(leader)):
					_heal(leader, 1, "defense")
			_log("打出「%s」。" % card.name)
			if side == PLAYER:
				defense_played = true
				_relic("defense", {"unit": piece, "square": target, "id": id})

func _equip_card(side: int, id: String, card: Dictionary, target: int) -> void:
	var piece := board[target]
	var slot := Cards.equipment_slot(card)
	var previous := equipment_at(piece, slot)
	var item := card.duplicate()
	item.card_id = id
	var affinity_guard := int(card.get("affinity_guard", 0)) if card.get("element", "") == piece.element else 0
	item.armor_remaining = int(card.get("armor", 0)) + int(card.get("equip_guard", 0)) + affinity_guard
	piece.armor = maxi(0, int(piece.armor) - int(previous.get("armor_remaining", 0))) + item.armor_remaining
	var hp_change := int(card.get("hp_bonus", 0)) - int(previous.get("hp_bonus", 0))
	piece.hp_max += hp_change
	piece.hp = clampi(int(piece.hp) + hp_change, 1, int(piece.hp_max))
	piece.gear[slot] = item
	if slot == "weapon":
		piece.weapon = id
	_heal(piece, int(card.get("heal", 0)), "gear")
	_log("%s装备%s。" % [piece.name, card.name])
	if side == PLAYER:
		_relic("equip", {"unit": piece, "square": target, "slot": slot, "id": id, "icon": card.get("icon", "")})

func _neighbors(a: int, b: int) -> bool:
	return a >= 0 and b >= 0 and maxi(absi(a % COLS - b % COLS), absi(_row(a) - _row(b))) == 1

func _heal(piece: Dictionary, amount: int, source: String) -> void:
	if amount <= 0 or piece.is_empty() or piece.hp <= 0 or piece.hp >= piece.hp_max:
		return
	var old := int(piece.hp)
	var context := {"unit": piece, "source": source, "amount": amount, "old_hp": old}
	if piece.side == PLAYER and source != "relic":
		_relic("heal", context)
	piece.hp = mini(int(piece.hp_max), old + int(context.amount))
	_log("%s回复 %d 点生命。" % [piece.name, int(piece.hp) - old])
	if piece.side == PLAYER and source != "relic":
		_relic("healed", context)

func _heal_adjacent(square: int) -> void:
	var piece: Dictionary = board[square]
	var healing := int(piece.get("heal", 0))
	if healing == 0:
		return
	var patient: Dictionary = {}
	var missing := 0
	for target in board.size():
		var other: Dictionary = board[target]
		if target == square or other.get("side", -1) != piece.side or maxi(absi(square % COLS - target % COLS), absi(_row(square) - _row(target))) != 1:
			continue
		if other.hp_max - other.hp > missing:
			missing = other.hp_max - other.hp
			patient = other
	_heal(patient, healing, "talent")

func _check_outcome() -> bool:
	if commanders[PLAYER].hp <= 0:
		_finish("defeat")
	elif commanders[ENEMY].hp <= 0:
		_finish("victory")
	elif final_battle and not river and commanders[ENEMY].hp <= ceili(commanders[ENEMY].hp_max * 0.55):
		reveal_pending = true
	return not outcome.is_empty() or reveal_pending

func awaken_death_power() -> void:
	if not reveal_pending:
		return
	reveal_pending = false
	river = true
	run.data.flags["hero_identity_revealed"] = true
	commanders[PLAYER].name = "伊文洛"
	run.actor("hero").name = "伊文洛"
	commanders[PLAYER].hp = commanders[PLAYER].hp_max
	_log("冥河显现，伊文洛恢复生命，敌方攻击 −1。")

func retreat() -> bool:
	if not outcome.is_empty() or reveal_pending or river or turn != PLAYER:
		return false
	_finish("retreat")
	return true

func _finish(result: String) -> void:
	if not outcome.is_empty():
		return
	outcome = result
	var hero: Dictionary = run.actor("hero")
	var extra_max := int(commanders[PLAYER].hp_max) - initial_board_hp_max
	var change := int(commanders[PLAYER].hp) - initial_board_hp - extra_max
	var scaled := floori(float(change * hero.hp_max) / maxi(1, initial_board_hp_max))
	hero.hp = 0 if result == "defeat" else clampi(initial_hero_hp + scaled, 1, int(hero.hp_max))
	if result == "victory" and commanders[PLAYER].hp < commanders[PLAYER].hp_max:
		run.data.relic_effect_flags["last_battle_wounded_victory"] = true
	else:
		run.data.relic_effect_flags.erase("last_battle_wounded_victory")
	var npc: String = pending.get("npc", "")
	if result == "victory":
		if npc.is_empty():
			run.data.tiles[position].enemies = []
			if not final_battle:
				run.data.peace[position] = true
		else:
			run.actor(npc).hp = 0
			run.data.flags["duel_won_" + npc] = true
		_grant_victory(npc)
	elif result == "retreat":
		hero.hp = maxi(1, int(hero.hp) - ceili(hero.hp_max * 0.10))
		run.retreat_party(pending.get("origin", position))
	run.data.pending_battle = {}
	if result != "victory" or final_battle:
		run.data.erase("pending_arrival")
	run.data.status = "failed" if result == "defeat" else "won" if result == "victory" and final_battle else "exploring"
	if result == "victory":
		run.open_battle_shop()
	if result == "defeat":
		run.data.flags["failure_reason"] = "己方主战者倒下，远征在这里中断了。"
	for key in run.data.item_effect_counts.keys():
		if str(key).begins_with("uphill_ready:"):
			run.data.item_effect_counts.erase(key)
	run.note("击倒敌方主战者。" if result == "victory" else "己方主战者倒下。" if result == "defeat" else "远征队撤退。")
	var saved: Dictionary = run.save_game()
	if not saved.ok:
		run.note("战斗已结算，存档写入失败：" + str(saved.message))
	run.changed.emit()

func _grant_victory(npc: String) -> void:
	var key := position + ":" + npc
	var relic := ""
	var coins := 0
	var duplicate := false
	if not run.data.rewards.has(key):
		run.data.rewards[key] = true
		coins = run.reward_coins("battle", Nodes.battle_coins(int(run.data.seed), position, Nodes.is_elite(enemy_types), final_battle))
		var bonus := {"amount": 0, "elite": pending.reward_tier == "elite"}
		_relic("victory", bonus)
		coins += int(bonus.amount)
		run.data.lamp_coins += coins
		duplicate = run.data.relic_seen.has(pending.relic_offer)
		relic = run.claim_relic_reward(pending.battle_uid, pending.relic_offer, "hero", position)
		_relic("loot", {"elite": pending.reward_tier == "elite", "relic": relic})
		run.data.item_revision += 1
	for id in participants:
		if not run.data.knowledge.has(id):
			run.data.knowledge[id] = {}
		if not run.data.knowledge[id].has("victories"):
			run.data.knowledge[id].victories = []
		if position not in run.data.knowledge[id].victories:
			run.data.knowledge[id].victories.append(position)
	run.data.pending_victory = {"enemies": enemy_types.size(), "opponent": commanders[ENEMY].name, "members": participants,
		"revived": [], "relic": relic, "relic_duplicate": duplicate, "coins": coins}

static func _row(square: int) -> int:
	return floori(float(square) / COLS)

static func _distance(a: int, b: int) -> int:
	return absi(a % COLS - b % COLS) + absi(_row(a) - _row(b))

static func square_name(square: int) -> String:
	return ("%s%s" % [["左路", "中路", "右路"][square % COLS], "后排" if _row(square) in [0, 3] else "前排"])

func _log(message: String) -> void:
	log_lines.append(message)
	if log_lines.size() > 8:
		log_lines.pop_front()
