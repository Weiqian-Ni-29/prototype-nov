extends RefCounted

const Cards = preload("res://scripts/domain/card_catalog.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Nodes = preload("res://scripts/domain/map_nodes.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
const COLS = 3
const ROWS = 4
const PLAYER = 0
const ENEMY = 1
const COMMANDER_DEFEAT_SCORE = 1000000

var run: RefCounted
var pending: Dictionary
var position: String
var board: Array[Dictionary] = []
var commanders: Array[Dictionary] = []
var hands: Array = [[], []]
var piles: Array = [[], []]
var fatigue: Array[int] = [0, 0]
var draw_count := 0
var weather := ""
var weather_rounds := 0
var round_number := 1
var turn := PLAYER
var player_has_played := false
var enemy_has_played := false
var enemy_drew := false
var outcome := ""
var reveal_pending := false
var river := false
var final_battle := false
var log_lines: Array[String] = []
var enemy_types: Array = []
var participants: Array[String] = ["hero"]
var initial_hero_hp := 0
var initial_board_hp := 0
var uid_serial := 0

func begin(expedition: RefCounted, encounter: Dictionary, deck: Array) -> Dictionary:
	if expedition.data.status != "exploring" or not Cards.valid_deck(deck, expedition.data.actors, true):
		return {"ok": false, "message": "请先编好 12 张牌。"}
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
	position = cell
	pending = encounter.duplicate(true)
	enemy_types = types
	final_battle = "war_god" in types
	var source := "battle:%s:%s" % [cell, npc]
	var elite: bool = run.node_at(cell).get("kind") == "elite" or pending.get("reward_tier") == "elite"
	if not run.data.battle_offers.has(source):
		run.data.battle_offers[source] = run.relic_offer(source, Relics.DATA.keys(), 1.0 if elite else 0.30)
	pending.merge({"battle_uid": source, "reward_tier": "elite" if elite else "ordinary",
		"relic_offer": run.data.battle_offers[source]}, true)
	run.data.pending_battle = pending.duplicate(true)
	var saved: Dictionary = run.save_game()
	if not saved.ok:
		return saved

	for square in COLS * ROWS:
		board.append({})
	var boss_type: String = "war_god" if final_battle else str(types[0])
	board[10] = _piece(commander_definition(run), PLAYER, true)
	board[1] = _piece(enemy_definition(run, boss_type, true), ENEMY, true)
	commanders.assign([board[10], board[1]])
	initial_hero_hp = int(hero.hp)
	board[10].hp = maxi(1, ceili(float(board[10].hp_max * hero.hp) / hero.hp_max))
	initial_board_hp = int(board[10].hp)
	var roller := RandomNumberGenerator.new()
	roller.seed = hash("%d:card-battle:%s:%d" % [int(run.data.seed), source, int(run.data.battles)])
	piles[PLAYER] = deck.duplicate()
	_shuffle(piles[PLAYER], roller)
	piles[ENEMY] = _enemy_deck(types, boss_type, roller)
	if run.data.weather == "rain":
		weather = "rain"
		weather_rounds = 2
	_draw(PLAYER, Cards.OPENING_HAND)
	_draw(ENEMY, Cards.OPENING_HAND)
	run.data.status = "battle"
	run.data.battles += 1
	run.note("战棋对战开始。")
	turn = ENEMY if pending.get("ambush", false) else PLAYER
	return {"ok": true}

func _shuffle(pile: Array, roller: RandomNumberGenerator) -> void:
	for i in range(pile.size() - 1, 0, -1):
		var j := roller.randi_range(0, i)
		var entry: Variant = pile[i]
		pile[i] = pile[j]
		pile[j] = entry

func _enemy_deck(types: Array, lead: String, roller: RandomNumberGenerator) -> Array:
	var support := types.duplicate()
	support.erase(lead)
	var pool := support.duplicate()
	pool.append_array(["boar", "archer", "furnace"] if final_battle else ["boar", "archer"])
	var deck := ["foe:" + str(pool[0]), "foe:" + str(pool[1 % pool.size()]), "coat"]
	for type in support:
		deck.append("foe:" + str(type))
	while deck.size() < Cards.DECK_SIZE:
		deck.append("foe:" + str(pool[roller.randi_range(0, pool.size() - 1)]) if deck.size() % 3 != 0 else ["blade", "coat", "ward"][roller.randi_range(0, 2)])
	_shuffle(deck, roller)
	return deck

static func commander_definition(expedition: RefCounted) -> Dictionary:
	var hero: Dictionary = expedition.actor("hero")
	var attack := 4 + floori(float(expedition.stat("hero", "attack") - hero.attack) / 6.0)
	var armor := 1 + floori(float(expedition.stat("hero", "defense") - hero.defense) / 4.0)
	return {"name": hero.name, "portrait": "hero", "element": "gravity", "attack": attack, "hp": 11,
		"armor": armor, "move": 1, "range": 1, "diagonal": true, "trait": "横竖斜走一格。"}

static func enemy_definition(expedition: RefCounted, id: String, leader: bool = false) -> Dictionary:
	var npc := id.begins_with("npc:")
	var actor_id := id.trim_prefix("npc:")
	var source: Dictionary = expedition.actor(actor_id) if npc else expedition.war_god_stats() if id == "war_god" else Catalog.ENEMIES[id]
	var ranged: bool = source.get("attack_delivery") == "ranged"
	var hp := maxi(4, roundi(float(source.hp) / (13.0 if leader else 19.0)))
	if leader:
		hp += 3
	return {"name": source.name, "kind": "partner", "portrait": actor_id if npc or id == "war_god" else "",
		"icon": "ranged_sight" if ranged else "ember_warden_armor", "element": "fire" if id == "war_god" else source.get("element", "normal"),
		"attack": maxi(2, roundi(float(source.attack) / 7.0)), "hp": hp,
		"armor": 1 if leader or not ranged else 0, "move": 1, "range": 2 if ranged else 1,
		"diagonal": leader, "trait": "横竖斜走一格。" if leader else "横竖走一格，可沿无阻挡的直线攻击两格。" if ranged else "横竖移动或攻击一格。"}

func definition(id: String) -> Dictionary:
	return enemy_definition(run, id.trim_prefix("foe:")) if id.begins_with("foe:") else Cards.owned_definition(id, run.data.actors)

func _piece(entry: Dictionary, side: int, leader: bool = false) -> Dictionary:
	var piece := entry.duplicate()
	uid_serial += 1
	piece.merge({"side": side, "leader": leader, "weapon": "", "uid": uid_serial}, true)
	if side == PLAYER:
		piece.hp += Cards.SEED_BONUS
		if run.has_relic("lamp_badge"):
			piece.armor += roundi(float(piece.hp) * 0.12)
	piece.hp_max = piece.hp
	return piece

func attack_power(piece: Dictionary) -> int:
	var climate: Dictionary = Cards.WEATHER.get(weather, {}).get("damage", {})
	return maxi(0, int(piece.attack) + int(Cards.ACTIONS.get(piece.weapon, {}).get("attack", 0))
		+ int(climate.get(piece.element, 0)) - (1 if weather == "river" and piece.side == ENEMY else 0))

func _attack_range(piece: Dictionary) -> int:
	return maxi(int(piece.get("range", piece.get("move", 1))), int(Cards.ACTIONS.get(piece.weapon, {}).get("range", 0)))

func moves(from: int) -> Dictionary:
	var options := {}
	if from < 0 or from >= board.size() or board[from].is_empty():
		return options
	var actor: Dictionary = board[from]
	var walking := int(actor.get("move", 1))
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
		if not ((actor.get("diagonal", false) and maxi(dx, dy) == 1) or (straight and length <= (range_attack if strike else walking))):
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
	if card.kind == "spell":
		return [-1]
	for square in board.size():
		var piece: Dictionary = board[square]
		if card.kind == "partner":
			if piece.is_empty() and ((_row(square) >= 2) == (side == PLAYER)):
				targets.append(square)
		elif piece.get("side", -1) == side and (card.kind == "defense" or piece.weapon.is_empty()):
			targets.append(square)
	return targets

func can_act() -> bool:
	return turn == PLAYER and outcome.is_empty() and not reveal_pending

func move(from: int, target: int) -> bool:
	if not can_act() or not moves(from).has(target) or board[from].side != PLAYER:
		return false
	_move_piece(from, target)
	_end_player_action()
	return true

func play(index: int, target: int) -> bool:
	if not can_act() or target not in card_targets(PLAYER, index):
		return false
	_play_card(PLAYER, index, target)
	_end_player_action()
	return true

func must_pass() -> bool:
	for square in board.size():
		if board[square].get("side", -1) == PLAYER and not moves(square).is_empty():
			return false
	for i in hands[PLAYER].size():
		if not card_targets(PLAYER, i).is_empty():
			return false
	return true

func pass_turn() -> bool:
	if not can_act() or not must_pass():
		return false
	_log("己方没有可走的棋子或可出的牌。")
	_end_player_action()
	return true

func _end_player_action() -> void:
	player_has_played = true
	turn = ENEMY
	_check_outcome()

func enemy_turn() -> void:
	if turn != ENEMY or not outcome.is_empty() or reveal_pending:
		return
	if enemy_has_played and not enemy_drew:
		enemy_drew = true
		_draw(ENEMY)
		if _check_outcome():
			return
	enemy_has_played = true
	var action := _choose_enemy_action()
	if action.has("from"):
		_move_piece(action.from, action.target)
	elif action.has("card_index"):
		_play_card(ENEMY, action.card_index, action.target)
	if _check_outcome():
		return
	enemy_drew = false
	_start_player_turn()

func _choose_enemy_action() -> Dictionary:
	var options: Array[Dictionary] = []
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
	var player_draws_fatigue: bool = player_has_played and piles[PLAYER].is_empty()
	for option in options:
		var preview := _copy_public_position()
		if option.has("from"):
			preview._move_piece(option.from, option.target)
		else:
			preview._apply_card(ENEMY, option.id, option.card, option.target)
		if preview.commanders[PLAYER].hp <= 0:
			return option
		if player_has_played:
			preview._advance_weather()
			if player_draws_fatigue:
				preview._fatigue(PLAYER)

		var position_score: int = preview._position_score()
		# The opponent can only lower this score. Skip a branch once it cannot beat best.
		var minimum_reply_score := best_reply_score + (0 if position_score > best_position_score else 1)
		if position_score < minimum_reply_score:
			continue
		var reply_score: int = preview._score_player_reply(position_score, minimum_reply_score)
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
	preview.weather = weather
	preview.weather_rounds = weather_rounds
	preview.fatigue = fatigue.duplicate()
	preview.final_battle = final_battle
	preview.river = river
	preview.uid_serial = uid_serial
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

func _start_player_turn() -> void:
	turn = PLAYER
	if not player_has_played:
		return
	round_number += 1
	_advance_weather()
	_draw(PLAYER)
	_check_outcome()

func _advance_weather() -> void:
	if weather_rounds > 0:
		weather_rounds -= 1
		if weather_rounds == 0:
			weather = ""

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
	if side == PLAYER:
		draw_count = drawn
		if drawn > 0:
			_log("开局抽 %d 张牌。" % drawn if count > 1 else "抽到「%s」。" % definition(hands[side][-1]).name)

func _fatigue(side: int) -> void:
	fatigue[side] += 1
	var damage := fatigue[side]
	_log("%s牌库已空，所有在场棋子各受 %d 点疲劳伤害。" % ["己方" if side == PLAYER else "敌方", damage])
	for square in board.size():
		var piece: Dictionary = board[square]
		if piece.get("side", -1) == side:
			_damage(piece, damage)
			if piece.hp <= 0:
				_log("%s倒下。" % piece.name)
				board[square] = {}

func _damage(piece: Dictionary, damage: int) -> int:
	var absorbed := mini(int(piece.armor), damage)
	piece.armor -= absorbed
	var phase_floor := 1 if final_battle and not river and piece.leader and piece.side == ENEMY else 0
	piece.hp = maxi(phase_floor, int(piece.hp) - (damage - absorbed))
	return absorbed

func _move_piece(from: int, target: int) -> void:
	var piece: Dictionary = board[from]
	var opponent: Dictionary = board[target]
	if not opponent.is_empty():
		var damage := attack_power(piece)
		var absorbed := _damage(opponent, damage)
		_log("%s攻击%s，%d 点%s伤害%s。" % [piece.name, opponent.name, damage,
			Cards.ELEMENTS.get(piece.element, "物理"), "，护甲吸收 %d" % absorbed if absorbed > 0 else ""])
		if opponent.hp > 0:
			return
		_log("%s倒下，%s占格。" % [opponent.name, piece.name])
	else:
		_log("%s走到%s。" % [piece.name, square_name(target)])
	board[from] = {}
	board[target] = piece
	_heal_adjacent(target)

func _play_card(side: int, index: int, target: int) -> void:
	var id: String = hands[side].pop_at(index)
	var card := definition(id)
	_apply_card(side, id, card, target)
	if side == PLAYER and card.kind == "partner" and run.actor(id).get("joined", false) and id not in participants:
		participants.append(id)

func _apply_card(side: int, id: String, card: Dictionary, target: int) -> void:
	match card.kind:
		"partner":
			board[target] = _piece(card, side)
			_log("%s部署到%s。" % [card.name, square_name(target)])
			_heal_adjacent(target)
		"spell":
			weather = card.weather
			weather_rounds = 2
			_log("打出「%s」，天气改为%s。" % [card.name, Cards.WEATHER[weather].name])
		"weapon":
			board[target].weapon = id
			_log("%s装备%s。" % [board[target].name, card.name])
		"defense":
			if card.get("column", false):
				for i in board.size():
					if i % COLS == target % COLS and board[i].get("side", -1) == side:
						board[i].armor += int(card.armor)
			else:
				board[target].armor += int(card.armor)
			_log("打出「%s」，%s获得护甲。" % [card.name, "同列友方" if card.get("column", false) else board[target].name])

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
	if not patient.is_empty():
		var healed := mini(missing, healing)
		patient.hp += healed
		_log("%s为%s回复 %d 点生命。" % [piece.name, patient.name, healed])

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
	weather = "river"
	weather_rounds = 0
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
	var change := int(commanders[PLAYER].hp) - initial_board_hp
	var scaled := floori(float(change * hero.hp_max) / commanders[PLAYER].hp_max)
	hero.hp = 0 if result == "defeat" else clampi(initial_hero_hp + scaled, 1, int(hero.hp_max))
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
	var receiver := ""
	var relic := ""
	var coins := 0
	var duplicate := false
	if not run.data.rewards.has(key):
		receiver = "hero"
		var inventory: Dictionary = run.actor(receiver).inventory
		inventory.salve = int(inventory.get("salve", 0)) + 1
		run.data.rewards[key] = true
		coins = run.reward_coins("battle", Nodes.battle_coins(int(run.data.seed), position, Nodes.is_elite(enemy_types), final_battle))
		run.data.lamp_coins += coins
		duplicate = run.data.relic_seen.has(pending.relic_offer)
		relic = run.claim_relic_reward(pending.battle_uid, pending.relic_offer, receiver, position)
		run.data.item_revision += 1
	for id in participants:
		if not run.data.knowledge.has(id):
			run.data.knowledge[id] = {}
		if not run.data.knowledge[id].has("victories"):
			run.data.knowledge[id].victories = []
		if position not in run.data.knowledge[id].victories:
			run.data.knowledge[id].victories.append(position)
	run.data.pending_victory = {"enemies": enemy_types.size(), "opponent": commanders[ENEMY].name, "members": participants,
		"revived": [], "salve_receiver": receiver, "relic": relic, "relic_duplicate": duplicate, "coins": coins}

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
