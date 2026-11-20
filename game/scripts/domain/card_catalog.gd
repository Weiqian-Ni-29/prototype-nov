extends RefCounted

const Catalog = preload("res://scripts/domain/catalog.gd")
const Gear = preload("res://scripts/domain/gear_catalog.gd")
const OPENING_HAND = 3
const MIN_DECK_SIZE = OPENING_HAND
const STARTING_PARTNER_HP_BONUS = 2
const RECRUIT_PRICE = 8
const BREAKTHROUGH_PRICES = [8, 14, 22]
const BREAKTHROUGH_BENEFITS = ["生命上限 +2", "生命上限 +1 · 初始护甲 +1", "攻击 +1 · 解锁天赋"]
const DEFAULT_DECK = ["blade", "pike", "coat", "coat", "brace", "brace", "ward", "ward",
	"ember_spell", "ember_spell", "mend_spell"]
const STARTER_SPELLS = ["ember_spell", "mend_spell"]
const LEGACY_STARTERS = {"highdrake": "support_vanguard", "lorne": "support_archer", "eve": "support_medic",
	"oathguard": "support_guard", "ember": "support_caster"}
const SUPPORT = {
	"support_vanguard": {"name": "远征先锋", "element": "earth", "attack": 4, "hp": 5, "armor": 1, "move": 2, "range": 2, "trait": "横竖最多走或攻击两格，路径上的棋子会挡路。"},
	"support_archer": {"name": "远征弓手", "element": "wind", "attack_delivery": "ranged", "attack_projectile": "arrow", "attack": 3, "hp": 4, "armor": 0, "move": 1, "range": 2, "trait": "横竖走一格，可沿无阻挡的直线攻击两格。"},
	"support_medic": {"name": "远征医师", "element": "water", "attack_delivery": "ranged", "attack": 2, "hp": 4, "armor": 0, "move": 1, "range": 1, "diagonal": true, "heal": 2, "trait": "横竖斜走一格，落位时治疗相邻且缺血最多的友方 2 点生命。"},
	"support_guard": {"name": "远征卫士", "element": "earth", "attack": 2, "hp": 6, "armor": 2, "move": 1, "range": 1, "trait": "横竖走一格，带 2 点护甲登场。"},
	"support_caster": {"name": "远征术士", "element": "fire", "attack_delivery": "ranged", "attack": 3, "hp": 4, "armor": 0, "move": 1, "range": 1, "trait": "横竖走一格。"},
}
const PARTNERS = {
	"highdrake": {"attack": 5, "hp": 6, "armor": 1, "element": "earth", "move": 2, "trait": "横竖最多走两格，路径上的棋子会挡路。"},
	"lorne": {"attack": 3, "hp": 5, "armor": 0, "element": "wind", "range": 2, "trait": "横竖走一格，可沿无阻挡的直线攻击两格。"},
	"eve": {"attack": 2, "hp": 5, "armor": 0, "element": "water", "diagonal": true, "heal": 3, "trait": "横竖斜走一格。落位时治疗相邻、缺血最多的一名友方 3 点生命。"},
	"ember": {"attack": 4, "hp": 5, "armor": 0, "element": "fire", "trait": "横竖走一格。"},
	"oathguard": {"attack": 3, "hp": 7, "armor": 3, "element": "earth", "trait": "横竖走一格，带着 3 点护甲登场。"},
}
const ACTIONS = {
	"blade": {"cost": 1, "name": "巡路短刃", "kind": "weapon", "attack_delivery": "melee", "icon": "trail_blade", "attack": 2, "trait": "仅近战棋子可装备。攻击 +2。替换下来的武器牌回到手牌。"},
	"pike": {"cost": 2, "name": "护沿短戟", "kind": "weapon", "attack_delivery": "melee", "icon": "frontier_guard_weapon", "attack": 1, "range": 2, "trait": "仅近战棋子可装备。攻击 +1，可沿无阻挡的直线攻击两格。替换下来的武器牌回到手牌。"},
	"staff": {"cost": 2, "name": "分枝诊杖", "kind": "weapon", "attack_delivery": "ranged", "icon": "grove_mender_weapon", "attack": 2, "trait": "仅远程棋子可装备。攻击 +2。替换下来的武器牌回到手牌。"},
	"coat": {"cost": 1, "name": "夹棉旅衣", "kind": "defense", "icon": "padded_coat", "armor": 3, "trait": "选一枚友方棋子，增加 3 点护甲。"},
	"brace": {"cost": 1, "name": "护身", "kind": "defense", "icon": "shield", "armor": 3, "trait": "选一枚友方棋子，增加 3 点护甲。"},
	"ward": {"cost": 2, "name": "列阵", "kind": "defense", "icon": "shield", "armor": 2, "column": true, "trait": "选一枚友方棋子，同列所有己方棋子各获得 2 点护甲。"},
	"ember_spell": {"cost": 1, "name": "余烬", "kind": "spell", "icon": "spell_ember", "element": "fire", "damage": 2, "trait": "对射程内的敌棋造成 2 点火伤害。射程为任一友方棋子横竖 2 格，路径须畅通。"},
	"ice_spell": {"cost": 1, "name": "冰针", "kind": "spell", "icon": "spell_ice", "element": "ice", "damage": 1, "slow": true, "trait": "对射程内的敌棋造成 1 点冰伤害，并使其下回合最多移动 1 格。横竖射程 2，路径须畅通。"},
	"mend_spell": {"cost": 1, "name": "回春", "kind": "spell", "icon": "spell_mend", "element": "water", "heal": 2, "trait": "选一枚受伤的友方棋子，回复 2 点生命。"},
	"bandage_card": {"cost": 1, "name": "包扎", "kind": "spell", "icon": "spell_bandage", "heal": 3, "trait": "选一枚受伤的友方棋子，回复 3 点生命。"},
	"broth_card": {"cost": 2, "name": "热汤", "kind": "defense", "icon": "balanced_broth_jar", "armor": 1, "heal": 2, "trait": "选一枚友方棋子，回复 2 点生命并获得 1 点护甲。"},
	"cup_card": {"cost": 1, "name": "递饮", "kind": "defense", "icon": "passing_cup", "armor": 2, "cup": true, "trait": "选一枚友方伙伴，使其获得 2 点护甲。若主战者与其相邻，主战者回复 1 点生命。"},
	"loaf_card": {"cost": 2, "name": "分食", "kind": "defense", "icon": "divided_warm_loaf", "armor": 1, "heal": 1, "row": true, "trait": "选一枚友方棋子，同排友方各回复 1 点生命并获得 1 点护甲。"},
	"tailwind_spell": {"cost": 1, "name": "顺风", "kind": "spell", "icon": "spell_tailwind", "element": "wind", "relocate": "straight",
		"trait": "立即将一枚友方棋子横竖移动最多 2 格到空格，路径须畅通。减速时最多走 1 格。可在普通走棋后施放。"},
	"sidestep_spell": {"cost": 1, "name": "斜步", "kind": "spell", "icon": "spell_sidestep", "element": "wind", "relocate": "diagonal",
		"trait": "立即将一枚友方棋子斜移 1 格到空格。可在普通走棋后施放。"},
}
const UNLOCKABLE_SPELLS = ["ember_spell", "ice_spell", "mend_spell", "tailwind_spell", "sidestep_spell"]
const COLLECTION_CARDS = {
	"spark_needle": {"cost": 1, "name": "跳火针", "kind": "spell", "icon": "conductive_needle", "element": "lightning",
		"damage": 1, "cast_range": 3, "trait": "对任一友方棋子横竖 3 格内的敌棋造成 1 点雷伤害，路径须畅通。"},
	"field_dressing": {"cost": 1, "name": "裹伤", "kind": "defense", "icon": "tender_gauze",
		"heal": 1, "armor": 1, "trait": "选一枚友方棋子，回复 1 点生命并获得 1 点护甲。"},
	"thin_frost": {"cost": 2, "name": "薄霜", "kind": "spell", "icon": "rime_thimble", "element": "ice",
		"damage": 2, "slow": true, "trait": "对任一友方棋子横竖 2 格内的敌棋造成 2 点冰伤害，并使其下回合最多移动 1 格。路径须畅通。"},
	"windbreak": {"cost": 2, "name": "挡风列", "kind": "defense", "icon": "gale_runner_armor", "element": "wind",
		"row": true, "armor": 2, "trait": "选一枚友方棋子，同排友方各获得 2 点护甲。"},
	"stone_shard": {"cost": 3, "name": "岩刺", "kind": "spell", "icon": "stone_vow_weapon", "element": "earth",
		"damage": 4, "trait": "对任一友方棋子横竖 2 格内的敌棋造成 4 点地伤害，路径须畅通。"},
	"camp_respite": {"cost": 3, "name": "营火歇息", "kind": "defense", "icon": "shared_kettle_lid",
		"row": true, "heal": 3, "armor": 1, "trait": "选一枚友方棋子，同排友方各回复 3 点生命并获得 1 点护甲。"},
	"furnace_surge": {"cost": 4, "name": "炉涌", "kind": "spell", "icon": "banked_ember_box", "element": "fire",
		"damage": 5, "trait": "对任一友方棋子横竖 2 格内的敌棋造成 5 点火伤害，路径须畅通。"},
	"ironbark_guard": {"cost": 4, "name": "铁木甲", "kind": "defense", "icon": "stone_vow_armor", "element": "earth",
		"armor": 8, "trait": "选一枚友方棋子，使其获得 8 点护甲。"},
	"cliffwind": {"cost": 5, "name": "断崖长风", "kind": "spell", "icon": "crossed_wind_chimes", "element": "wind",
		"damage": 5, "cast_range": 3, "trait": "对任一友方棋子横竖 3 格内的敌棋造成 5 点风伤害，路径须畅通。"},
	"firebreak": {"cost": 5, "name": "封火线", "kind": "defense", "icon": "ember_warden_armor", "element": "fire",
		"column": true, "heal": 1, "armor": 4, "trait": "选一枚友方棋子，同列友方各回复 1 点生命并获得 4 点护甲。"},
	"frost_tide": {"cost": 6, "name": "冻潮冰锋", "kind": "spell", "icon": "rime_path_weapon", "element": "ice",
		"damage": 5, "cast_range": 3, "slow": true,
		"trait": "对任一友方棋子横竖 3 格内的敌棋造成 5 点冰伤害，并使其下回合最多移动 1 格。路径须畅通。"},
	"dune_shelter": {"cost": 6, "name": "沙脊掩护", "kind": "defense", "icon": "dune_keeper_armor", "element": "earth",
		"row": true, "heal": 2, "armor": 4, "trait": "选一枚友方棋子，同排友方各回复 2 点生命并获得 4 点护甲。"},
	"ashfall": {"cost": 7, "name": "赤灰陨火", "kind": "spell", "icon": "ember_warden_weapon", "element": "fire",
		"damage": 9, "trait": "对任一友方棋子横竖 2 格内的敌棋造成 9 点火伤害，路径须畅通。"},
	"camp_spring": {"cost": 7, "name": "归营泉", "kind": "defense", "icon": "stillwater_stone", "element": "water",
		"column": true, "heal": 4, "armor": 3, "trait": "选一枚友方棋子，同列友方各回复 4 点生命并获得 3 点护甲。"},
	"thunderstrike": {"cost": 8, "name": "霆击", "kind": "spell", "icon": "storm_conductor_weapon", "element": "lightning",
		"damage": 10, "trait": "对任一友方棋子横竖 2 格内的敌棋造成 10 点雷伤害，路径须畅通。"},
	"root_wall": {"cost": 8, "name": "森垒", "kind": "defense", "icon": "rootbound_bracelet", "element": "earth",
		"row": true, "armor": 7, "trait": "选一枚友方棋子，同排友方各获得 7 点护甲。"},
	"winter_lock": {"cost": 9, "name": "深冬封锁", "kind": "spell", "icon": "rime_path_accessory", "element": "ice",
		"damage": 9, "cast_range": 3, "slow": true,
		"trait": "对任一友方棋子横竖 3 格内的敌棋造成 9 点冰伤害，并使其下回合最多移动 1 格。路径须畅通。"},
	"deepwater_refuge": {"cost": 9, "name": "深泉庇护", "kind": "defense", "icon": "tide_weaver_accessory", "element": "water",
		"row": true, "heal": 6, "armor": 4, "trait": "选一枚友方棋子，同排友方各回复 6 点生命并获得 4 点护甲。"},
	"sunforge_flare": {"cost": 10, "name": "日铸焰火", "kind": "spell", "icon": "ember_warden_accessory", "element": "fire",
		"damage": 12, "cast_range": 3, "trait": "对任一友方棋子横竖 3 格内的敌棋造成 12 点火伤害，路径须畅通。"},
	"lantern_vigil": {"cost": 10, "name": "长灯守夜", "kind": "defense", "icon": "guard_candle_cap", "element": "water",
		"column": true, "heal": 5, "armor": 7, "trait": "选一枚友方棋子，同列友方各回复 5 点生命并获得 7 点护甲。"},
}
const PREP_CARDS = ["bandage_card", "broth_card", "cup_card", "loaf_card"]
const KINDS = {"all": "全部", "partner": "伙伴", "weapon": "武器", "equipment": "装备", "defense": "防御", "spell": "法术"}
const ELEMENTS = {"earth": "地", "fire": "火", "water": "水", "ice": "冰", "wind": "风", "lightning": "雷"}
const TALENTS = {
	"diagonal": {"name": "斜行", "text": "可以斜向移动或攻击一格。", "changes": {"diagonal": true}},
	"march": {"name": "疾行", "text": "可以横竖移动两格，路径须畅通。", "changes": {"move": 2}},
	"range": {"name": "远射", "text": "可沿无阻挡的直线攻击三格。", "changes": {"range": 3}},
	"heal": {"name": "援护", "text": "落位时治疗相邻、缺血最多的一名友方 4 点生命。", "changes": {"heal": 4}},
	"guard": {"name": "坚守", "text": "入场额外获得 2 点护甲。", "changes": {}},
}

static func definition(id: String, rank: int = 0) -> Dictionary:
	if ACTIONS.has(id):
		return ACTIONS[id]
	if COLLECTION_CARDS.has(id):
		return COLLECTION_CARDS[id]
	if SUPPORT.has(id):
		var support: Dictionary = SUPPORT[id].duplicate()
		support.kind = "partner"
		support.portrait = id
		support.cost = 2
		support.hp += STARTING_PARTNER_HP_BONUS
		balance_ranged(support)
		return support
	if not Catalog.COMPANIONS.has(id):
		return {}
	var actor: Dictionary = Catalog.COMPANIONS[id]
	var ranged := is_ranged(actor)
	var entry := {"name": actor.name, "kind": "partner", "portrait": id, "cost": 2,
		"attack_delivery": actor.get("attack_delivery", "melee"),
		"attack_projectile": "arrow" if is_archer(actor) else "energy",
		"element": chess_element(actor), "attack": maxi(2, roundi(float(actor.attack) / 6.0)),
		"hp": maxi(4, roundi(float(actor.hp) / 16.0)), "armor": 0, "move": 1, "range": 2 if ranged else 1,
		"trait": "横竖走一格，可沿无阻挡的直线攻击两格。" if ranged else "横竖移动或攻击一格。"}
	entry.merge(PARTNERS.get(id, {}), true)
	entry.hp += STARTING_PARTNER_HP_BONUS
	balance_ranged(entry)
	if entry.move > 1:
		entry.range = maxi(entry.range, entry.move)
	if rank >= 1:
		entry.hp += 2
	if rank >= 2:
		entry.hp += 1
		entry.armor += 1
	if rank >= 3:
		var talent := breakthrough_talent(id)
		entry.attack += 1
		entry.armor += int(talent.get("armor_bonus", 0))
		entry.merge(talent.changes, true)
		entry.trait += "\n天赋 · %s。%s" % [talent.name, talent.text]
	return entry

static func is_ranged(piece: Dictionary) -> bool:
	return piece.get("attack_delivery", "melee") == "ranged"

static func attack_type(entry: Dictionary) -> String:
	return "远程" if is_ranged(entry) else "近战"

static func card_attack_type(card: Dictionary) -> String:
	return attack_type(card) if card.get("kind") == "partner" or equipment_slot(card) == "weapon" else ""

static func weapon_fits(card: Dictionary, piece: Dictionary) -> bool:
	return equipment_slot(card) != "weapon" or is_ranged(card) == is_ranged(piece)

static func balance_ranged(piece: Dictionary, starts_on_board: bool = false) -> void:
	if not is_ranged(piece):
		return
	if not starts_on_board:
		piece.cost += 1
	piece.hp -= 1
	if piece.attack >= 3:
		piece.attack -= 1

static func equipment_slot(card: Dictionary) -> String:
	if card.get("kind") == "weapon":
		return "weapon"
	return card.get("slot", "") if card.get("kind") == "equipment" else ""

static func is_archer(actor: Dictionary) -> bool:
	return actor.get("skill") in ["frost_arrow", "trail_shot"] or actor.get("ultimate") == "arrow_rain"

static func breakthrough_talent(id: String) -> Dictionary:
	if id in ["eve", "fieldmedic", "mistleaf"]:
		return TALENTS.heal
	if id in ["grit", "oathguard", "granite", "stone_guard", "snowforge", "siltguard"]:
		return {"name": TALENTS.guard.name, "text": TALENTS.guard.text, "changes": {}, "armor_bonus": 2}
	if id in ["highdrake", "ember", "cloudscale", "wind_runner"]:
		return TALENTS.diagonal
	return TALENTS.range if Catalog.COMPANIONS[id].attack_delivery == "ranged" else TALENTS.march

static func owned_definition(id: String, actors: Dictionary, state: Dictionary = {}) -> Dictionary:
	if id.begins_with("gear:"):
		var instance: Dictionary = state.get("gear_instances", {}).get(id.trim_prefix("gear:"), {})
		return {} if instance.is_empty() else Gear.card(instance)
	return definition(id, int(actors.get(id, {}).get("breakthrough", 0)))

static func collection(actors: Dictionary, state: Dictionary = {}, legacy_support: bool = false) -> Array[String]:
	var result: Array[String] = []
	if legacy_support:
		result.assign(SUPPORT.keys())
	for id in Catalog.COMPANIONS:
		var actor: Variant = actors.get(id)
		if actor is Dictionary and actor.get("joined", false):
			result.append(id)
	for id in ["blade", "pike", "coat", "brace", "ward"]:
		if state.is_empty() or id not in ["blade", "pike", "coat"]:
			result.append(id)
	for id in UNLOCKABLE_SPELLS:
		if id in state.get("spell_collection", []):
			result.append(id)
	for uid in state.get("gear_instances", {}):
		var owner: Dictionary = state.gear_instances[uid].owner
		if owner.kind == "actor" and actors.get(owner.id, {}).get("joined", false):
			result.append("gear:" + str(uid))
	result.append_array(COLLECTION_CARDS.keys())
	return result

static func migrate_deck(deck: Array, actors: Dictionary) -> Array:
	var result := deck.duplicate()
	for i in result.size():
		var id: Variant = result[i]
		if id is String and LEGACY_STARTERS.has(id):
			var actor: Variant = actors.get(id)
			if actor is Dictionary and not actor.get("joined", false):
				result[i] = LEGACY_STARTERS[id]
	return result

static func limit(id: String) -> int:
	return 2 if ACTIONS.has(id) or COLLECTION_CARDS.has(id) else 1

static func valid_deck(deck: Variant, actors: Dictionary, require_minimum: bool = false, state: Dictionary = {}, legacy_support: bool = false) -> bool:
	if not deck is Array or (require_minimum and deck.size() < MIN_DECK_SIZE):
		return false
	var available := collection(actors, state, legacy_support)
	var counts := {}
	for id in deck:
		if not id is String or id not in available:
			return false
		counts[id] = int(counts.get(id, 0)) + 1
		if counts[id] > limit(id):
			return false
	return true

static func chess_element(entry: Dictionary) -> String:
	var element: String = entry.get("element", "")
	return element if ELEMENTS.has(element) else ""

static func stats(entry: Dictionary) -> String:
	return "攻 %d · 血 %d · 甲 %d" % [entry.attack, entry.hp, entry.armor]
