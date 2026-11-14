extends RefCounted

const Cards = preload("res://scripts/domain/card_catalog.gd")

# Event, conditions, operation, argument, charges per battle, player-facing effect.
const RULES = {
	"telescope": ["enemy_draw", "", "reveal", "", 1, "扩大地图视野；敌方第一次自然抽牌时，公开抽到的牌。"],
	"ranged_sight": ["equip", "weapon,partner", "sight", 1, 1, "首次给伙伴装备武器后，它下一次横竖普通攻击射程 +1，最高 3 格。"],
	"lamp_badge": ["entry", "", "entry", "", 0, "己方棋子首次登场时，获得其生命上限 12% 的护甲，四舍五入。"],
	"herbal_case": ["heal", "spell_heal", "amount", 1, 1, "每场首次用治疗法术实际回血时，治疗量 +1。"],
	"rainstone": ["opening_weather", "", "weather", "rain", 1, "选择此开局天气时，前两轮为降雨。"],
	"life_seed": ["growth", "", "entry", "", 0, "启用后，本次远征所有己方棋子的战棋生命上限 +1。重复启用不叠加。"],
	"opening_flint": ["attack", "own_front_from", "bonus", 1, 1, "第一次从己方前排发起的普通攻击伤害 +1。"],
	"patient_knot": ["action_end", "patient", "leader_armor", 2, 1, "前两次行动均未普攻或施放伤害法术，第二次行动后主战者获得 2 甲。"],
	"dry_ink_seal": ["spell", "", "bonus", 1, 2, "本场前两张伤害法术各 +1 伤害。"],
	"untouched_edge": ["equip", "weapon", "edge", 1, 1, "第一次装备武器时，装备者下一次普通攻击伤害 +1。"],
	"closing_weight": ["attack", "weak_enemy", "bonus", 1, 1, "首次普通攻击生命不超过 2 的敌方伙伴时，伤害 +1。"],
	"shield_borer": ["attack", "armored", "pierce", 1, 1, "首次普通攻击有护甲的敌棋时，1 点伤害直接扣生命。"],
	"cadence_beads": ["spell", "previous_attack", "bonus", 1, 2, "上一手是普通攻击时，本次伤害法术 +1。每场最多两次。"],
	"lone_watch_token": ["incoming", "alone", "block", 2, 1, "首次有独占一列的己方伙伴受击时，伤害 −2。"],
	"spent_rune_clip": ["weather_cast", "", "weather_card", "", 1, "首次打出天气法术后，按新天气生成一张牌：降雨给冰针，烈日给余烬，雾幕给回春。"],
	"measured_spoon": ["opening", "only_partners", "search", "action", 1, "如果三张起手全是伙伴，从牌库额外抽取第一张非伙伴牌。"],
	"aftersong_shell": ["kill", "spell", "generate", "mend_spell", 1, "首次用伤害法术击倒敌方伙伴后，生成「回春」。"],
	"third_stitch": ["deploy", "third", "armor", 2, 1, "第三个部署的伙伴登场时获得 2 甲。"],
	"witness_ribbon": ["occupy", "", "occupy_armor", "", 1, "首次击倒敌人并占格后，攻击者获得 1 甲，若占领敌后排则获得 2 甲。"],
	"clear_air_reed": ["opening_weather", "", "weather", "sun", 1, "选择此开局天气时，前两轮为烈日。"],
	"mended_buckle": ["survive", "broken_armor", "armor_victim", 1, 1, "首次有伙伴的护甲被打空且它存活时，为其补 1 甲。"],
	"guard_candle_cap": ["deploy", "near_leader", "leader_armor", 2, 1, "首次将伙伴部署在主战者相邻格时，主战者获得 2 甲。"],
	"broken_ring": ["turn_start", "ally_lost", "draw", 1, 1, "首次有己方伙伴倒下后，下一个己方回合额外抽 1 张，牌库空时不抽。"],
	"surplus_cotton": ["defense", "full", "armor", 1, 1, "首次给满血棋子打出防御牌时，选中的棋子额外获得 1 甲。"],
	"dented_whistle": ["enemy_advance", "", "leader_armor", 1, 1, "首次有敌方伙伴进入己方半场时，己方主战者获得 1 甲。"],
	"shield_lining": ["incoming", "armored,attack", "block", 1, 1, "首次受到打在护甲上的普通攻击时，伤害 −1。"],
	"quiet_abacus": ["fatigue", "", "fatigue_block", 1, 1, "首次疲劳的伤害 −1，疲劳计数照常增长。"],
	"relay_sash": ["move", "two_steps,partner", "relay", "", 1, "第一个走两格的伙伴标记自己；随后部署在它邻格的伙伴获得 1 甲。"],
	"return_seam": ["loss", "", "leader_heal", 2, 1, "首次失去己方伙伴时，受伤的主战者回复 2 点生命。"],
	"fallen_standard_tassel": ["loss", "", "partner_armor", 1, 1, "首次失去己方伙伴时，其他存活伙伴各获得 1 甲。"],
	"narrow_margin": ["turn_end", "hand_empty", "draw", 1, 1, "己方回合结束时若手牌打空，且牌库有牌，抽 1 张。"],
	"impact_pad": ["defense", "coat", "neighbor_armor", 1, 1, "首次打出「夹棉旅衣」或装备同名护甲时，给选中棋子相邻的一枚友方棋子 1 甲。"],
	"familiar_knock": ["incoming", "armed_enemy", "block", 2, 1, "首次受到已装备武器的敌棋普通攻击时，伤害 −2。"],
	"tender_gauze": ["heal", "talent_heal", "amount", 1, 1, "首次由伙伴天赋实际治疗时，治疗量 +1。"],
	"unburdened_clasp": ["deploy", "edge", "diagonal", "", 1, "首枚部署在边路的伙伴，下一次移动可斜走到相邻空格。"],
	"last_drop_cup": ["healed", "saved", "armor", 1, 1, "首次将生命不超过 2 的友方治到至少 3 点时，为其加 1 甲。"],
	"rain_listening_pin": ["defense", "rain", "generate", "rain", 1, "降雨中首次打出防御牌后，生成「唤雨」。"],
	"banked_ember_box": ["opening", "", "generate", "ember_spell", 1, "开场生成一张「余烬」。"],
	"rime_thimble": ["opening", "", "generate", "ice_spell", 1, "开场生成一张「冰针」。首次获得时也永久解锁该牌。"],
	"copper_rain_comb": ["hit", "rain,water,attack,hp_damage", "leader_armor", 1, 1, "雨中己方水属性普通攻击首次扣除敌方生命时，主战者获得 1 甲。"],
	"crossed_wind_chimes": ["opening", "", "generate", "fog_spell", 1, "开场生成一张「起雾」；己方风属性棋子的攻击不受雾幕削弱。首次获得时也永久解锁该牌。"],
	"rootbound_bracelet": ["deploy", "rain,earth", "armor", 2, 1, "雨中首枚部署的地属性伙伴获得 2 甲。"],
	"field_water_sponge": ["heal", "rain", "heal_guard", 1, 1, "雨中首次实际治疗时，治疗量 +1，目标也获得 1 甲。"],
	"dripping_spool": ["weather_end", "rain_ended", "column_armor", 1, 1, "第一次降雨自然结束时，与主战者同列的己方棋子各获得 1 甲。"],
	"conductive_needle": ["attack", "rain,lightning", "bonus", 1, 1, "雨中首次雷属性普通攻击伤害 +1。"],
	"ice_anchor_button": ["hit", "rain,ice,attack,alive_victim", "slow", "", 1, "雨中己方冰属性普通攻击首次击中仍存活的敌棋时，敌棋下回合最多移动 1 格。"],
	"grounding_heel": ["incoming", "rain,spell", "block", 2, 1, "降雨中己方首次受到伤害法术时，伤害 −2。"],
	"river_brace": ["move", "rain,two_steps,partner", "armor", 2, 1, "雨中伙伴首次走两格后，该伙伴获得 2 甲。"],
	"ash_filter_patch": ["incoming", "sun,fire", "block", 2, 1, "烈日中己方首次受到火伤害时，伤害 −2。"],
	"thaw_water_vial": ["weather_cast", "sun,wet_before", "weakest_heal", 2, 1, "首次用烈日覆盖降雨或雾幕时，最缺血的己方棋子回复 2 点。"],
	"field_dial": ["weather_cast", "", "bottom", "", 1, "首次打出天气法术后，将下一张待抽的牌移到牌库底，并在战报中显示牌名。"],
	"waterline_thread": ["move", "rain,water,own_front", "neighbor_heal", 1, 2, "雨中水属性棋子走到己方前排后，治疗相邻且最缺血的友方 1 点，每场最多两次。"],
	"survey_tally": ["loot", "", "survey", "", 1, "共鸣期间累计赢过一场普通战和一场精英战后，解锁「冰针」。"],
	"market_window": ["shop", "", "entry", "", 0, "共鸣时，商店每轮库存额外展示第二本未解锁的法术牌谱；每轮仍只能买一本。"],
	"caution_compass": ["opening", "ambush", "leader_armor", 2, 1, "被伏击、由敌方先手时，主战者开局获得 2 甲。"],
	"honest_ledger": ["victory", "ordinary", "daily_coin", 2, 1, "每天第一场普通战胜利后多得 2 灯铢。"],
	"terrain_caliper": ["move", "cross_columns,partner", "armor", 2, 1, "首次有伙伴从一侧边路横跨到另一侧边路时，为其加 2 甲。"],
	"cloud_almanac": ["opening", "clear", "generate", "sun", 1, "实际开局无特殊天气时，生成一张「烈日」。"],
	"uphill_kneepad": ["move", "from_back,own_front", "armor", 1, 1, "第一枚由己方后排走到己方前排的棋子获得 1 甲。"],
	"milestone_waterbag": ["opening", "wounded_victory", "generate", "mend_spell", 1, "若上场战斗主战者带伤获胜，这场开局生成一张「回春」。"],
	"bargaining_counter": ["shop", "", "entry", "", 0, "商店法术牌谱减价 2 灯铢。"],
	"workshop_gauge": ["loot", "elite", "workshop", "", 1, "带着未满阶伙伴赢得精英战后，下次伙伴突破抵 2 灯铢，不累积。"],
	"fair_weight_seal": ["victory", "guarded_victory", "amount", 1, 1, "用过防御牌且主战者带甲获胜，多得 1 灯铢。"],
	"commission_carbon": ["victory", "two_kills", "amount", 2, 1, "击倒至少两枚敌方伙伴后获胜，多得 2 灯铢。"],
	"farewell_receipt": ["victory", "ally_lost", "amount", 2, 1, "有伙伴倒下后仍获胜，多得 2 灯铢。"],
	"survey_bonus_stamp": ["loot", "elite,treasure_found", "unlock_next", "", 1, "发现过寻宝遗器后，共鸣赢得精英战可解锁一张新法术，每次远征一次。"],
	"first_fit_pattern": ["equip", "weapon,partner", "search", "defense", 1, "首次为伙伴装备武器后，从牌库检索第一张防御牌。"],
	"price_pair_slip": ["loot", "no_relic", "discount_spell", "", 1, "胜利未掉遗器时，获得下次购买法术牌谱半价的机会，不累积。"],
	"breath_reserve": ["after_fatigue", "", "generate", "mend_spell", 1, "第一次疲劳结算后，若主战者仍在场，生成「回春」。"],
	"tracking_notch": ["hit", "attack,alive_victim", "track", "", 1, "己方第一次普通攻击为存活敌棋留下标记。下一次另一枚己方棋子攻击它时，伤害 +1。"],
	"ready_sandal_loop": ["deploy", "center_front", "ready_move", 2, 1, "首枚部署在中路前排的伙伴，下一次可横竖移动两格，路径须畅通。"],
	"closing_chime": ["hit", "leader_hit,hp_damage", "draw", 1, 1, "第一次实际打伤敌方主战者生命后，额外抽 1 张，牌库空时不抽。"],
	"sheltered_stitch": ["defense", "half_hp", "heal_unit", 2, 1, "首次对生命不超过一半的棋子打出防御牌时，它也回复 2 点生命。"],
	"witness_slate": ["kill", "", "scout", "", 1, "首次击倒敌方伙伴后，公开并将己方接下来三张待抽牌中的第一张伙伴牌放到牌顶。"],
}

const PREPARATIONS = {
	"stillwater_stone": "首个己方回合结束时，主战者回复 2 点生命。",
	"rain_bell": "开局下雨两轮，优先于共鸣遗器设定的开局天气。",
	"clean_bandage_roll": "开场生成临时牌「包扎」：治疗友方 3 点。",
	"mint_distillate": "开局额外抽 1 张牌。",
	"balanced_broth_jar": "开场生成临时牌「热汤」：选友方回复 2 点生命并获得 1 甲。",
	"bitter_exchange_vial": "开局以主战者 2 点生命换取额外抽 2 张牌，生命不足时不可携带。",
	"unfolding_map_leaf": "开局抽完牌后，若接下来三张待抽牌里有伙伴，把第一张伙伴牌放到牌顶。",
	"cache_tracing_powder": "开场从四张进阶法术中生成一张临时牌。",
	"patient_recovery_oil": "前两个己方回合开始时，主战者各回复 1 点生命。",
	"modest_trade_coupon": "开局从牌库抽取第一张防御牌或装备牌。",
	"fitting_labor_ticket": "开场生成临时装备牌「护沿短戟」。",
	"folded_route_string": "首枚部署的伙伴，下一次可沿两格空路转弯移动，终点须在己方半场。",
	"passing_cup": "开场生成临时牌「递饮」：给伙伴 2 甲，若邻接主战者，主战者也回复 1 点。",
	"divided_warm_loaf": "开场生成临时牌「分食」：同排友方各回复 1 点生命并获得 1 甲。",
	"encounter_rubbing": "开场公开敌方三张起手牌。",
}


static func effect(id: String) -> String:
	return PREPARATIONS.get(id, RULES.get(id, ["", "", "", "", 0, ""])[5])

static func fire(b, event: String, context: Dictionary) -> void:
	for id in b.relic_ids:
		var rule: Array = RULES.get(id, [])
		if rule.is_empty() or (rule[0] != event and not (id == "impact_pad" and event == "equip")) or b.relic_used.get(id, 0) >= rule[4]:
			continue
		var conditions: String = rule[1]
		if not conditions.is_empty() and not Array(conditions.split(",")).all(func(tag): return _condition(b, tag, context)):
			continue
		b.relic_used[id] = int(b.relic_used.get(id, 0)) + 1
		if not _apply(b, rule[2], rule[3], context, id):
			b.relic_used[id] -= 1
		elif not b.public_preview and event not in ["victory", "loot"]:
			b._log("遗器触发：" + b.relic_name(id))
	if event == "attack":
		var attacker: Dictionary = context.unit
		var victim: Dictionary = context.victim
		context.bonus += int(attacker.get("edge", 0))
		attacker.erase("edge")
		if victim.has("tracked_by") and victim.tracked_by != attacker.uid:
			context.bonus += 1
			victim.erase("tracked_by")
	elif event == "deploy":
		for i in b.board.size():
			var ally: Dictionary = b.board[i]
			if ally.get("relay", false) and b._neighbors(i, int(context.square)):
				ally.erase("relay")
				context.unit.armor += 1
				break
	elif not b.public_preview and event == "turn_end" and b.prep == "stillwater_stone" and b.round_number == 1:
		b._heal(b.commanders[0], 2, "relic")
	elif event == "turn_start" and b.prep == "patient_recovery_oil" and b.round_number <= 2:
		b._heal(b.commanders[0], 1, "relic")

static func _condition(b, tag: String, c: Dictionary) -> bool:
	var unit: Dictionary = c.get("unit", {})
	var victim: Dictionary = c.get("victim", {})
	var square := int(c.get("square", -1))
	var leader: Dictionary = b.commanders[0]
	match tag:
		"rain", "sun":
			return b.weather == tag
		"clear":
			return b.weather.is_empty()
		"rain_ended":
			return c.old == "rain"
		"wet_before":
			return c.old in ["rain", "fog"]
		"earth", "ice", "water", "fire", "lightning":
			return c.get("element", unit.get("element", "")) == tag
		"spell", "attack":
			return c.get("kind", "") == tag
		"weapon":
			return c.slot == "weapon"
		"partner":
			return not unit.get("leader", true)
		"spell_heal", "talent_heal":
			return c.source == tag.trim_suffix("_heal")
		"own_front":
			return square / 3 == 2
		"own_front_from":
			return int(c.from) / 3 == 2
		"from_back":
			return int(c.from) / 3 == 3
		"center_front":
			return square == 7
		"edge":
			return square % 3 != 1
		"third":
			return b.deployments == 3
		"patient":
			return b.player_actions == 2 and b.previous_action not in ["attack", "damage_spell"] and b.action_kind not in ["attack", "damage_spell"]
		"previous_attack":
			return b.previous_action == "attack"
		"weak_enemy":
			return not victim.leader and victim.hp <= 2
		"armored":
			return int(c.armor_before) > 0
		"broken_armor":
			return c.armor_before > 0 and victim.armor == 0 and not victim.leader
		"near_leader":
			return b._neighbors(square, b.board.find(leader))
		"full":
			return unit.hp == unit.hp_max
		"half_hp":
			return unit.hp * 2 <= unit.hp_max
		"alone":
			if victim.leader:
				return false
			for i in b.board.size():
				if i != square and i % 3 == square % 3 and b.board[i].get("side", -1) == 0:
					return false
			return true
		"armed_enemy":
			return c.kind == "attack" and not unit.get("weapon", "").is_empty()
		"two_steps":
			return c.distance == 2
		"cross_columns":
			return absi(int(c.from) % 3 - square % 3) == 2
		"ally_lost":
			return b.ally_losses > 0
		"two_kills":
			return b.enemy_losses >= 2
		"guarded_victory":
			return b.defense_played and leader.armor > 0
		"hand_empty":
			return not b.public_preview and b.hands[0].is_empty()
		"only_partners":
			return not b.public_preview and b.hands[0].all(func(id): return b.definition(id).kind == "partner")
		"coat":
			return c.id == "coat" or c.get("icon", "") == "padded_coat"
		"saved":
			return c.old_hp <= 2 and unit.hp >= 3
		"hp_damage":
			return c.hp_loss > 0
		"leader_hit":
			return victim.leader
		"alive_victim":
			return victim.hp > 0
	if b.public_preview:
		return false
	match tag:
		"ambush":
			return b.pending.get("ambush", false)
		"wounded_victory":
			return b.run.data.relic_effect_flags.get("last_battle_wounded_victory", false)
		"ordinary":
			return not c.elite
		"elite":
			return c.elite
		"no_relic":
			return c.relic.is_empty()
		"treasure_found":
			for key in b.run.data.relic_claims:
				if key.begins_with("field_cache:") and b.run.data.relic_claims[key].get("success", false):
					return true
	return false

static func _apply(b, op: String, value: Variant, c: Dictionary, id: String) -> bool:
	var unit: Dictionary = c.get("unit", {})
	var victim: Dictionary = c.get("victim", {})
	var leader: Dictionary = b.commanders[0]
	match op:
		"bonus", "pierce", "block", "amount":
			c[op] += value
		"fatigue_block":
			c.amount = maxi(0, int(c.amount) - int(value))
		"armor":
			unit.armor += value
		"armor_victim":
			victim.armor += value
		"leader_armor":
			leader.armor += value
		"occupy_armor":
			unit.armor += 2 if int(c.square) / 3 == 0 else 1
		"partner_armor", "column_armor":
			var leader_square: int = b.board.find(leader)
			for i in b.board.size():
				var ally: Dictionary = b.board[i]
				if ally.get("side", -1) == 0 and ((op == "partner_armor" and not ally.leader) or (op == "column_armor" and i % 3 == leader_square % 3)):
					ally.armor += value
		"neighbor_armor", "neighbor_heal", "weakest_heal":
			var ally := _weakest(b, int(c.get("square", -1)) if op.begins_with("neighbor") else -1, op != "neighbor_armor")
			if ally.is_empty():
				return false
			if op == "neighbor_armor":
				ally.armor += value
			else:
				b._heal(ally, value, "relic")
		"leader_heal", "heal_unit":
			b._heal(leader if op == "leader_heal" else unit, value, "relic")
		"heal_guard":
			c.amount += value
			unit.armor += 1
		"sight", "edge", "ready_move":
			unit[op] = value
		"diagonal", "relay":
			unit["ready_diagonal" if op == "diagonal" else "relay"] = true
		"track":
			victim.tracked_by = unit.uid
		"slow":
			victim.slow_until = b.round_number
		_:
			return false if b.public_preview else _private_effect(b, op, value, c, id)
	return true

static func _private_effect(b, op: String, value: Variant, c: Dictionary, id: String) -> bool:
	match op:
		"weather":
			if b.run.prepared_weather != id or b.prep == "rain_bell":
				return false
			b.weather = value
			b.weather_rounds = 2
		"weather_card":
			_generate(b, {"rain": "ice_spell", "sun": "ember_spell", "fog": "mend_spell"}[b.weather])
		"generate":
			_generate(b, value)
		"reveal":
			b._log("望远镜看到敌方抽到「%s」。" % b.definition(c.card).name)
			b.revealed_enemy.append(c.card)
		"draw":
			if b.piles[0].is_empty():
				return false
			b._draw(0, mini(int(value), b.piles[0].size()))
		"search":
			return _search(b, value)
		"bottom":
			if b.piles[0].is_empty():
				return false
			var next: String = b.piles[0].pop_front()
			b.piles[0].append(next)
			b._log("「%s」移到牌库底。" % b.definition(next).name)
		"scout":
			return _scout(b)
		"daily_coin":
			var key := "chess_ledger:" + str(b.run.data.day)
			if b.run.data.item_effect_counts.has(key):
				return false
			b.run.data.item_effect_counts[key] = 1
			c.amount += value
		"survey":
			var flag: String = "chess_survey_" + ("elite" if c.elite else "ordinary")
			var flags: Dictionary = b.run.data.relic_effect_flags
			flags[flag] = true
			if flags.has("chess_survey_elite") and flags.has("chess_survey_ordinary"):
				b.run.unlock_spell("ice_spell")
		"workshop":
			for partner in b.participants:
				if partner != "hero" and int(b.run.actor(partner).get("breakthrough", 0)) < 3:
					b.run.data.relic_effect_flags["chess_workshop_credit"] = true
					return true
			return false
		"unlock_next":
			var flags: Dictionary = b.run.data.relic_effect_flags
			if flags.has("chess_survey_bonus"):
				return false
			for spell in Cards.UNLOCKABLE_SPELLS:
				if b.run.unlock_spell(spell):
					flags["chess_survey_bonus"] = true
					return true
			return false
		"discount_spell":
			b.run.data.relic_effect_flags["chess_spell_discount"] = true
		_:
			return false
	return true

static func _weakest(b, square: int, wounded: bool) -> Dictionary:
	var best := {}
	var amount := -1
	for i in b.board.size():
		var ally: Dictionary = b.board[i]
		if ally.get("side", -1) != 0 or (square >= 0 and not b._neighbors(square, i)):
			continue
		var missing := int(ally.hp_max - ally.hp)
		if ally.hp > 0 and (not wounded or missing > 0) and missing > amount:
			best = ally
			amount = missing
	return best

static func _generate(b, card: String) -> void:
	b.hands[0].append("temp:" + card)
	b.draw_count += 1
	b._log("生成临时牌「%s」。" % b.definition(card).name)

static func _search(b, kind: String) -> bool:
	for i in b.piles[0].size():
		var card: String = b.piles[0][i]
		var type: String = b.definition(card).kind
		if type == kind or (kind == "action" and type != "partner") or (kind == "supply" and type in ["defense", "equipment"]):
			b.hands[0].append(b.piles[0].pop_at(i))
			b.draw_count += 1
			b._log("从牌库抽取「%s」。" % b.definition(card).name)
			return true
	return false

static func _scout(b) -> bool:
	for i in mini(3, b.piles[0].size()):
		var card: String = b.piles[0][i]
		if b.definition(card).kind == "partner":
			b.piles[0].push_front(b.piles[0].pop_at(i))
			b._log("「%s」移到牌库顶。" % b.definition(card).name)
			return true
	return false

static func prepare(b, id: String) -> void:
	match id:
		"rain_bell":
			b.weather = "rain"
			b.weather_rounds = 2
		"clean_bandage_roll":
			_generate(b, "bandage_card")
		"mint_distillate":
			b._draw(0)
		"balanced_broth_jar":
			_generate(b, "broth_card")
		"bitter_exchange_vial":
			b.commanders[0].hp -= 2
			b._draw(0, 2)
		"unfolding_map_leaf":
			_scout(b)
		"cache_tracing_powder":
			var index := posmod(hash("%s:%s:%s" % [b.run.data.seed, b.position, b.run.data.battles]), Cards.UNLOCKABLE_SPELLS.size())
			_generate(b, Cards.UNLOCKABLE_SPELLS[index])
		"modest_trade_coupon":
			_search(b, "supply")
		"fitting_labor_ticket":
			_generate(b, "pike")
		"passing_cup":
			_generate(b, "cup_card")
		"divided_warm_loaf":
			_generate(b, "loaf_card")
		"encounter_rubbing":
			b.revealed_enemy = b.hands[1].duplicate()
			var names: Array[String] = []
			for card in b.hands[1]:
				names.append(b.definition(card).name)
			b._log("敌方起手：" + "、".join(names))

static func prepared_deploy(b, unit: Dictionary) -> void:
	if b.prep == "folded_route_string" and b.deployments == 1:
		unit.bend_move = true
