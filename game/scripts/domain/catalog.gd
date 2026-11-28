class_name GameCatalog
extends RefCounted
## Balance values for terrain, characters, items, and combat.

const VERSION = 1
const RADIUS = 3
const ENERGY_MAX = 100
const TERRAIN = {
	"plains": {"name": "平原", "color": "91a577"},
	"forest": {"name": "森林", "color": "47765b"},
	"mountain": {"name": "山地", "color": "8d9290"},
	"ruins": {"name": "遗迹", "color": "aba28b"},
	"desert": {"name": "沙漠", "color": "cfb578"},
	"swamp": {"name": "沼泽", "color": "657c72"},
	"lake": {"name": "湖泊", "color": "397d84"},
}
const PROFESSIONS = {
	"wayfarer": {"name": "巡路客", "description": "善于探索和支援，行动频繁。", "hp": 95, "mp": 48, "attack": 18, "defense": 5, "speed": 122, "skill": "trail_shot", "ultimate": "rally", "color": "caa76d", "attack_delivery": "ranged"},
	"guardian": {"name": "守灯卫", "description": "高生命与防护，机动较低。", "hp": 145, "mp": 35, "attack": 24, "defense": 10, "speed": 83, "skill": "guard_all", "ultimate": "dawn_strike", "color": "799cba", "attack_delivery": "melee"},
	"arcanist": {"name": "烛纹师", "description": "以魔力施展火焰与治疗。", "hp": 83, "mp": 85, "attack": 23, "defense": 4, "speed": 101, "skill": "ember", "ultimate": "warmth", "color": "b78aac", "attack_delivery": "ranged"},
	"frost_archer": {"name": "霜弓手", "hero_name": "霜弦", "description": "用冰箭给一个敌人减速，终结技可以让所有敌人变慢。", "hp": 92, "mp": 64, "attack": 20, "defense": 5, "speed": 108, "skill": "frost_arrow", "ultimate": "frostfall", "color": "93badd", "attack_delivery": "ranged"},
	"storm_caller": {"name": "引雷师", "hero_name": "闻霆", "description": "雷击擅长爆发。", "hp": 82, "mp": 76, "attack": 26, "defense": 4, "speed": 102, "skill": "thunderbolt", "ultimate": "thunderstorm", "color": "9f87d7", "attack_delivery": "ranged"},
	"wind_runner": {"name": "逐风客", "hero_name": "岚翎", "description": "风刃攻击全体敌人，终结技为己方提速。", "hp": 96, "mp": 56, "attack": 19, "defense": 5, "speed": 124, "skill": "windblade", "ultimate": "tailwind", "color": "79bd9a", "attack_delivery": "ranged"},
	"stone_guard": {"name": "岩卫", "hero_name": "石垣", "description": "以石棘打击单个敌人，终结技为全队撑起护盾。", "hp": 142, "mp": 48, "attack": 23, "defense": 10, "speed": 84, "skill": "stone_spike", "ultimate": "stonewall", "color": "ba9267", "attack_delivery": "ranged"},
}
const COMPANIONS = {
	"frost_archer": {"name": "霜弦", "title": "冷饮师", "race": "精灵", "terrain": "forest", "hp": 84, "mp": 50, "attack": 18, "defense": 4, "speed": 89, "skill": "frost_arrow", "ultimate": "frostfall", "color": "93badd", "portrait": "frost_archer", "attack_delivery": "ranged"},
	"storm_caller": {"name": "闻霆", "title": "电工", "race": "恶魔", "terrain": "ruins", "hp": 93, "mp": 56, "attack": 20, "defense": 5, "speed": 95, "skill": "thunderbolt", "ultimate": "thunderstorm", "color": "9f87d7", "portrait": "storm_caller", "attack_delivery": "ranged"},
	"wind_runner": {"name": "岚翎", "title": "帆手", "race": "人类", "terrain": "plains", "hp": 102, "mp": 62, "attack": 22, "defense": 6, "speed": 101, "skill": "windblade", "ultimate": "tailwind", "color": "79bd9a", "portrait": "wind_runner", "attack_delivery": "ranged"},
	"stone_guard": {"name": "石垣", "title": "搬运工", "race": "矮人", "terrain": "mountain", "hp": 142, "mp": 68, "attack": 24, "defense": 10, "speed": 84, "skill": "stone_spike", "ultimate": "stonewall", "color": "ba9267", "portrait": "stone_guard", "attack_delivery": "ranged"},
	"ironforge": {"name": "铎火", "title": "铁匠", "race": "矮人", "terrain": "mountain", "hp": 120, "mp": 50, "attack": 26, "defense": 8, "speed": 113, "skill": "ironforge_skill", "ultimate": "ironforge_ult", "color": "7ca9b3", "portrait": "ironforge", "attack_delivery": "ranged"},
	"granite": {"name": "岩钉", "title": "石匠", "race": "矮人", "terrain": "mountain", "hp": 142, "mp": 56, "attack": 18, "defense": 10, "speed": 84, "skill": "granite_skill", "ultimate": "granite_ult", "color": "93badd", "portrait": "granite", "attack_delivery": "melee"},
	"mistleaf": {"name": "沐叶", "title": "园丁", "race": "精灵", "terrain": "swamp", "hp": 93, "mp": 62, "attack": 20, "defense": 5, "speed": 89, "skill": "mistleaf_skill", "ultimate": "mistleaf_ult", "color": "9f87d7", "portrait": "mistleaf", "attack_delivery": "ranged"},
	"willow": {"name": "暮柳", "title": "钓手", "race": "精灵", "terrain": "forest", "hp": 102, "mp": 68, "attack": 22, "defense": 6, "speed": 95, "skill": "willow_skill", "ultimate": "willow_ult", "color": "79bd9a", "portrait": "willow", "attack_delivery": "ranged"},
	"ashhorn": {"name": "灰角", "title": "提灯人", "race": "恶魔", "terrain": "desert", "hp": 111, "mp": 50, "attack": 24, "defense": 7, "speed": 101, "skill": "ashhorn_skill", "ultimate": "ashhorn_ult", "color": "ba9267", "portrait": "ashhorn", "attack_delivery": "ranged"},
	"oathguard": {"name": "契岑", "title": "门卫", "race": "恶魔", "terrain": "ruins", "hp": 120, "mp": 56, "attack": 26, "defense": 8, "speed": 107, "skill": "oathguard_skill", "ultimate": "oathguard_ult", "color": "7ca9b3", "portrait": "oathguard", "attack_delivery": "melee"},
	"highdrake": {"name": "铅翼", "title": "酒客", "race": "龙", "terrain": "mountain", "hp": 84, "mp": 62, "attack": 18, "defense": 4, "speed": 113, "skill": "highdrake_skill", "ultimate": "highdrake_ult", "color": "93badd", "portrait": "highdrake", "attack_delivery": "melee"},
	"cloudscale": {"name": "霁鳞", "title": "索具工", "race": "龙", "terrain": "plains", "hp": 93, "mp": 68, "attack": 20, "defense": 5, "speed": 119, "skill": "cloudscale_skill", "ultimate": "cloudscale_ult", "color": "9f87d7", "portrait": "cloudscale", "attack_delivery": "ranged"},
	"longroad": {"name": "长路", "title": "领路人", "race": "人类", "terrain": "plains", "hp": 102, "mp": 50, "attack": 22, "defense": 6, "speed": 89, "skill": "longroad_skill", "ultimate": "longroad_ult", "color": "79bd9a", "portrait": "longroad", "attack_delivery": "ranged"},
	"fieldmedic": {"name": "苏茅", "title": "船医", "race": "人类", "terrain": "forest", "hp": 111, "mp": 56, "attack": 24, "defense": 7, "speed": 95, "skill": "fieldmedic_skill", "ultimate": "fieldmedic_ult", "color": "ba9267", "portrait": "fieldmedic", "attack_delivery": "ranged"},
	"siltguard": {"name": "泽栅", "title": "摆渡人", "race": "人类", "terrain": "swamp", "hp": 120, "mp": 62, "attack": 26, "defense": 8, "speed": 101, "skill": "siltguard_skill", "ultimate": "siltguard_ult", "color": "7ca9b3", "portrait": "siltguard", "attack_delivery": "melee"},
	"seasons": {"name": "梅姨", "title": "厨师", "race": "人类", "terrain": "forest", "hp": 84, "mp": 68, "attack": 18, "defense": 4, "speed": 107, "skill": "seasons_skill", "ultimate": "seasons_ult", "color": "93badd", "portrait": "seasons", "attack_delivery": "ranged"},
	"earth_god": {"name": "多克", "title": "木匠", "race": "人类", "terrain": "mountain", "hp": 142, "mp": 50, "attack": 20, "defense": 10, "speed": 84, "skill": "earth_god_skill", "ultimate": "earth_god_ult", "color": "9f87d7", "portrait": "earth_god", "attack_delivery": "ranged"},
	"sky_god": {"name": "莱索", "title": "瞭望员", "race": "人类", "terrain": "desert", "hp": 102, "mp": 56, "attack": 22, "defense": 6, "speed": 119, "skill": "sky_god_skill", "ultimate": "sky_god_ult", "color": "79bd9a", "portrait": "sky_god", "attack_delivery": "ranged"},
	"snowforge": {"name": "砧雪", "title": "修理工", "race": "矮人", "terrain": "mountain", "hp": 142, "mp": 62, "attack": 24, "defense": 10, "speed": 84, "skill": "snowforge_skill", "ultimate": "snowforge_ult", "color": "ba9267", "portrait": "snowforge", "attack_delivery": "melee"},
	"cen": {"race": "精灵", "name": "岑枝", "title": "猎手", "hp": 102, "mp": 34, "attack": 22, "defense": 5, "speed": 113, "skill": "snare", "ultimate": "arrow_rain", "color": "77945c", "terrain": "forest", "portrait": "cen", "attack_delivery": "ranged"},
	"lorne": {"race": "人类", "name": "洛恩", "title": "送酒人", "hp": 88, "mp": 44, "attack": 18, "defense": 4, "speed": 132, "skill": "trail_shot", "ultimate": "rally", "color": "be9b6c", "terrain": "mountain", "portrait": "lorne", "attack_delivery": "ranged"},
	"eve": {"race": "精灵", "name": "伊芙", "title": "医者", "hp": 90, "mp": 90, "attack": 14, "defense": 5, "speed": 99, "skill": "heal", "ultimate": "warmth", "color": "b9c69d", "terrain": "forest", "portrait": "eve", "attack_delivery": "ranged"},
	"grit": {"race": "龙", "name": "砾牙", "title": "渔人", "hp": 155, "mp": 28, "attack": 28, "defense": 7, "speed": 96, "skill": "rend", "ultimate": "wolf_howl", "color": "adb4b5", "terrain": "forest", "portrait": "grit", "attack_delivery": "melee"},
	"ember": {"race": "恶魔", "name": "弥烬", "title": "炉工", "hp": 84, "mp": 78, "attack": 29, "defense": 4, "speed": 94, "skill": "ember", "ultimate": "sunfall", "color": "bc6a52", "terrain": "ruins", "portrait": "ember", "attack_delivery": "ranged"},
	"tide": {"race": "人类", "name": "澄汐", "title": "水手", "hp": 93, "mp": 82, "attack": 22, "defense": 6, "speed": 106, "skill": "torrent", "ultimate": "tide_shelter", "color": "6bafbd", "terrain": "ruins", "portrait": "tide", "attack_delivery": "ranged"},
}
# Older expedition saves still store these identifiers on each actor.
const SAVE_SKILL_IDS = [
	"ironforge_skill", "ironforge_ult", "granite_skill", "granite_ult", "mistleaf_skill",
	"mistleaf_ult", "willow_skill", "willow_ult", "ashhorn_skill", "ashhorn_ult",
	"oathguard_skill", "oathguard_ult", "highdrake_skill", "highdrake_ult", "cloudscale_skill",
	"cloudscale_ult", "longroad_skill", "longroad_ult", "fieldmedic_skill", "fieldmedic_ult",
	"siltguard_skill", "siltguard_ult", "seasons_skill", "seasons_ult", "earth_god_skill",
	"earth_god_ult", "sky_god_skill", "sky_god_ult", "snowforge_skill", "snowforge_ult",
	"gravity", "gravity_drift", "gravity_wave", "attack", "trail_shot",
	"snare", "rend", "ember", "torrent", "heal",
	"guard_all", "rally", "dawn_strike", "arrow_rain", "warmth",
	"wolf_howl", "sunfall", "tide_shelter", "frost_arrow", "frostfall",
	"thunderbolt", "thunderstorm", "windblade", "tailwind", "stone_spike",
	"stonewall",
]
const ITEMS = {
	"trail_food": {"name": "旅途干粮", "description": "可以送给别人或用来完成任务。", "story": "粗布包里是烤得干透的麦饼，掰碎后泡在汤里也能吃。"},
	"trail_blade": {"name": "巡路短刃", "slot": "weapon", "attack": 4},
	"padded_coat": {"name": "夹棉旅衣", "slot": "armor", "defense": 3},
	"lamp_charm": {"name": "旧灯护符", "slot": "accessory", "speed": 8},
}
const ENEMIES = {
	"boar": {"name": "棘背兽", "hp": 72, "attack": 18, "defense": 7, "speed": 82, "color": "8e7c58", "role": "保护同伴 · 厚甲", "skill": "guard", "attack_delivery": "melee"},
	"archer": {"name": "荒路弩手", "hp": 53, "attack": 24, "defense": 3, "speed": 94, "color": "98785b", "role": "蓄力 · 高伤", "skill": "charge", "attack_delivery": "ranged"},
	"spider": {"name": "苔伏蛛", "hp": 48, "attack": 16, "defense": 2, "speed": 125, "color": "5c7c58", "role": "伏击 · 减速", "skill": "slow", "attack_delivery": "melee"},
	"lurker": {"name": "淤泥潜伏者", "hp": 95, "attack": 19, "defense": 8, "speed": 75, "color": "537b78", "role": "重甲 · 支援", "skill": "support", "attack_delivery": "melee"},
	"furnace": {"name": "炉心守卒", "hp": 69, "attack": 23, "defense": 5, "speed": 88, "color": "c17b50", "role": "伤害法术", "skill": "assault", "attack_delivery": "melee"},
	"canal": {"name": "渠台守卫", "hp": 76, "attack": 21, "defense": 6, "speed": 90, "color": "699da4", "role": "减速 · 支援", "skill": "support", "attack_delivery": "melee"},
	"swarm": {"name": "巢鸣蜂群", "hp": 31, "attack": 12, "defense": 1, "speed": 151, "color": "d8b76b", "role": "高速 · 脆弱", "skill": "attack", "attack_delivery": "melee"},
	"apothecary": {"name": "拾荒药师", "hp": 56, "attack": 13, "defense": 3, "speed": 105, "color": "8b9d7b", "role": "治疗同伴", "skill": "heal", "attack_delivery": "ranged"},
	"hunter_elite": {"name": "苔冠猎伏者", "hp": 160, "attack": 29, "defense": 7, "speed": 129, "color": "5e7751", "role": "精英 · 伏击压制", "skill": "slow", "attack_delivery": "melee"},
	"furnace_elite": {"name": "裂炉监卫", "hp": 185, "attack": 33, "defense": 10, "speed": 85, "color": "ad6248", "role": "精英 · 伤害法术", "skill": "assault", "attack_delivery": "melee"},
	"war_god": {"name": "捕鲸机", "hp": 250, "attack": 29, "defense": 12, "speed": 103, "color": "bd5447", "role": "绞盘牵引", "skill": "madness", "attack_delivery": "melee"},
	"lamp_boss": {"name": "旧石像", "hp": 320, "attack": 35, "defense": 12, "speed": 108, "color": "bbaa70", "role": "重装守卫", "skill": "assault", "attack_delivery": "melee"},
}

static func item_name(id: String) -> String:
	return str(ITEMS.get(id, {}).get("name", id))

static func terrain_name(id: String) -> String:
	return str(TERRAIN.get(id, TERRAIN.plains).name)
