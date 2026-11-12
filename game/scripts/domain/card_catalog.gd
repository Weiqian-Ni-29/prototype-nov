extends RefCounted

const Catalog = preload("res://scripts/domain/catalog.gd")
const DECK_SIZE = 12
const OPENING_HAND = 3
const SEED_BONUS = 2
const RECRUIT_PRICE = 8
const BREAKTHROUGH_PRICES = [8, 14, 22]
const BREAKTHROUGH_BENEFITS = ["生命上限 +2", "生命上限 +1 · 初始护甲 +1", "攻击 +1 · 解锁天赋"]
const DEFAULT_DECK = ["support_vanguard", "support_archer", "support_medic", "support_guard", "support_caster", "blade", "pike", "coat", "coat", "ward", "rain", "sun"]
const LEGACY_STARTERS = {"highdrake": "support_vanguard", "lorne": "support_archer", "eve": "support_medic",
	"oathguard": "support_guard", "ember": "support_caster"}
const SUPPORT = {
	"support_vanguard": {"name": "远征先锋", "icon": "frontier_guard_weapon", "element": "earth", "attack": 4, "hp": 5, "armor": 1, "move": 2, "range": 2, "trait": "横竖最多走或攻击两格，路径上的棋子会挡路。"},
	"support_archer": {"name": "远征弓手", "icon": "ranged_sight", "element": "wind", "attack": 3, "hp": 4, "armor": 0, "move": 1, "range": 2, "trait": "横竖走一格，可沿无阻挡的直线攻击两格。"},
	"support_medic": {"name": "远征医师", "icon": "clean_bandage_roll", "element": "water", "attack": 2, "hp": 4, "armor": 0, "move": 1, "range": 1, "diagonal": true, "heal": 2, "trait": "横竖斜走一格，落位时治疗相邻且缺血最多的友方 2 点生命。"},
	"support_guard": {"name": "远征卫士", "icon": "shield", "element": "earth", "attack": 2, "hp": 6, "armor": 2, "move": 1, "range": 1, "trait": "横竖走一格，带 2 点护甲登场。"},
	"support_caster": {"name": "远征术士", "icon": "banked_ember_box", "element": "fire", "attack": 3, "hp": 4, "armor": 0, "move": 1, "range": 1, "trait": "横竖走一格，火攻受天气影响。"},
}
const PARTNERS = {
	"highdrake": {"attack": 5, "hp": 6, "armor": 1, "element": "earth", "move": 2, "trait": "横竖最多走两格，路径上的棋子会挡路。"},
	"lorne": {"attack": 3, "hp": 5, "armor": 0, "element": "wind", "range": 2, "trait": "横竖走一格，可沿无阻挡的直线攻击两格。"},
	"eve": {"attack": 2, "hp": 5, "armor": 0, "element": "water", "diagonal": true, "heal": 3, "trait": "横竖斜走一格。落位时治疗相邻、缺血最多的一名友方 3 点生命。"},
	"ember": {"attack": 4, "hp": 5, "armor": 0, "element": "fire", "trait": "横竖走一格。烈日增强火攻，降雨削弱火攻。"},
	"oathguard": {"attack": 3, "hp": 7, "armor": 3, "element": "earth", "trait": "横竖走一格，带着 3 点护甲登场。"},
}
const ACTIONS = {
	"blade": {"name": "巡路短刃", "kind": "weapon", "icon": "trail_blade", "attack": 2, "trait": "给一枚友方棋子装备短刃，本场攻击 +2。每枚棋子装备一把武器。"},
	"pike": {"name": "护沿短戟", "kind": "weapon", "icon": "frontier_guard_weapon", "attack": 1, "range": 2, "trait": "攻击 +1，可沿无阻挡的直线攻击两格。每枚棋子装备一把武器。"},
	"coat": {"name": "夹棉旅衣", "kind": "defense", "icon": "padded_coat", "armor": 3, "trait": "选一枚友方棋子，增加 3 点护甲。"},
	"ward": {"name": "列阵", "kind": "defense", "icon": "shield", "armor": 2, "column": true, "trait": "选一枚友方棋子，同列所有己方棋子各获得 2 点护甲。"},
	"rain": {"name": "唤雨", "kind": "spell", "icon": "rain", "element": "water", "weather": "rain", "trait": "降雨持续两轮（含施放轮）。双方水攻 +1，火攻 −1。"},
	"sun": {"name": "烈日", "kind": "spell", "icon": "sun", "element": "fire", "weather": "sun", "trait": "烈日持续两轮（含施放轮）。双方火攻 +1，水攻 −1。"},
}
const KINDS = {"all": "全部", "partner": "伙伴", "weapon": "武器", "defense": "防御", "spell": "法术"}
const ELEMENTS = {"gravity": "重力", "normal": "物理", "earth": "地", "fire": "火", "water": "水",
	"ice": "冰", "wind": "风", "lightning": "雷"}
const WEATHER = {
	"rain": {"name": "降雨", "hint": "水攻 +1 · 火攻 −1", "damage": {"water": 1, "fire": -1}},
	"sun": {"name": "烈日", "hint": "火攻 +1 · 水攻 −1", "damage": {"fire": 1, "water": -1}},
	"river": {"name": "冥河", "hint": "敌方攻击 −1", "damage": {}},
}
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
	if SUPPORT.has(id):
		var support: Dictionary = SUPPORT[id].duplicate()
		support.kind = "partner"
		return support
	if not Catalog.COMPANIONS.has(id):
		return {}
	var actor: Dictionary = Catalog.COMPANIONS[id]
	var ranged: bool = actor.get("attack_delivery") == "ranged"
	var entry := {"name": actor.name, "kind": "partner", "portrait": id,
		"element": actor.get("element", "normal"), "attack": maxi(2, roundi(float(actor.attack) / 6.0)),
		"hp": maxi(4, roundi(float(actor.hp) / 16.0)), "armor": 0, "move": 1, "range": 2 if ranged else 1,
		"trait": "横竖走一格，可沿无阻挡的直线攻击两格。" if ranged else "横竖移动或攻击一格。"}
	entry.merge(PARTNERS.get(id, {}), true)
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

static func breakthrough_talent(id: String) -> Dictionary:
	if id in ["eve", "fieldmedic", "mistleaf"]:
		return TALENTS.heal
	if id in ["grit", "oathguard", "granite", "stone_guard", "snowforge", "siltguard"]:
		return {"name": TALENTS.guard.name, "text": TALENTS.guard.text, "changes": {}, "armor_bonus": 2}
	if id in ["highdrake", "ember", "cloudscale", "wind_runner"]:
		return TALENTS.diagonal
	return TALENTS.range if Catalog.COMPANIONS[id].attack_delivery == "ranged" else TALENTS.march

static func owned_definition(id: String, actors: Dictionary) -> Dictionary:
	return definition(id, int(actors.get(id, {}).get("breakthrough", 0)))

static func collection(actors: Dictionary) -> Array[String]:
	var result: Array[String] = []
	result.assign(SUPPORT.keys())
	for id in Catalog.COMPANIONS:
		var actor: Variant = actors.get(id)
		if actor is Dictionary and actor.get("joined", false):
			result.append(id)
	result.append_array(ACTIONS.keys())
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
	return 2 if ACTIONS.has(id) else 1

static func valid_deck(deck: Variant, actors: Dictionary, require_full: bool = false) -> bool:
	if not deck is Array or deck.size() > DECK_SIZE or (require_full and deck.size() != DECK_SIZE):
		return false
	var available := collection(actors)
	var counts := {}
	for id in deck:
		if not id is String or id not in available:
			return false
		counts[id] = int(counts.get(id, 0)) + 1
		if counts[id] > limit(id):
			return false
	return true

static func stats(entry: Dictionary) -> String:
	return "%s属性 · 攻 %d · 血 %d · 甲 %d" % [ELEMENTS.get(entry.element, "物理"), entry.attack, entry.hp, entry.armor]
