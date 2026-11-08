class_name GameCatalog
extends RefCounted
## Versioned, intentionally modest MVP balance values. AP is individual, never shared.

const VERSION = 1
const RADIUS = 8
const BATTLE_AP = 2
const ENERGY_MAX = 100
const TERRAIN = {
	"plains": {"name": "平原", "cost": 1, "color": "91a577"},
	"forest": {"name": "森林", "cost": 1, "color": "47765b"},
	"mountain": {"name": "山地", "cost": 2, "color": "8d9290"},
	"ruins": {"name": "遗迹", "cost": 1, "color": "aba28b"},
	"desert": {"name": "沙漠", "cost": 1, "color": "cfb578"},
	"swamp": {"name": "沼泽", "cost": 2, "color": "657c72"},
	"lake": {"name": "湖泊", "cost": 0, "color": "397d84"},
}
const ELEMENT_NAMES = {"normal": "普通", "fire": "火", "water": "水", "ice": "冰", "lightning": "雷", "wind": "风", "earth": "土"}
const PROFESSIONS = {
	"wayfarer": {"name": "巡路客", "description": "善于探索和支援，行动频繁。", "hp": 95, "mp": 48, "ap": 9, "attack": 18, "defense": 5, "speed": 122, "skill": "trail_shot", "ultimate": "rally", "color": "caa76d"},
	"guardian": {"name": "守灯卫", "description": "高生命与防护，机动较低。", "hp": 145, "mp": 35, "ap": 5, "attack": 24, "defense": 10, "speed": 83, "skill": "guard_all", "ultimate": "dawn_strike", "color": "799cba"},
	"arcanist": {"name": "烛纹师", "description": "以魔力施展火焰与治疗。", "hp": 83, "mp": 85, "ap": 7, "attack": 23, "defense": 4, "speed": 101, "skill": "ember", "ultimate": "warmth", "color": "b78aac"},
	"frost_archer": {"name": "霜弓手", "hero_name": "霜弦", "element": "ice", "description": "冰矢压慢单个敌人，终结技减速全场敌人。", "hp": 92, "mp": 64, "ap": 8, "attack": 20, "defense": 5, "speed": 108, "skill": "frost_arrow", "ultimate": "frostfall", "color": "93badd"},
	"storm_caller": {"name": "引雷师", "hero_name": "闻霆", "element": "lightning", "description": "雷击擅长爆发，在潮湿的场地伤害更高。", "hp": 82, "mp": 76, "ap": 7, "attack": 26, "defense": 4, "speed": 102, "skill": "thunderbolt", "ultimate": "thunderstorm", "color": "9f87d7"},
	"wind_runner": {"name": "逐风客", "hero_name": "岚翎", "element": "wind", "description": "风刃攻击全体敌人，终结技为己方提速。", "hp": 96, "mp": 56, "ap": 9, "attack": 19, "defense": 5, "speed": 124, "skill": "windblade", "ultimate": "tailwind", "color": "79bd9a"},
	"stone_guard": {"name": "岩卫", "hero_name": "石垣", "element": "earth", "description": "以石棘打击单个敌人，终结技为全队撑起护盾。", "hp": 142, "mp": 48, "ap": 6, "attack": 23, "defense": 10, "speed": 84, "skill": "stone_spike", "ultimate": "stonewall", "color": "ba9267"},
}
const COMPANIONS = {
	"frost_archer": {"name": "霜弦", "title": "精灵", "race": "精灵", "element": "ice", "terrain": "forest", "hp": 84, "mp": 50, "ap": 6, "attack": 18, "defense": 4, "speed": 89, "skill": "frost_arrow", "ultimate": "frostfall", "color": "93badd", "portrait": "frost_archer"},
	"storm_caller": {"name": "闻霆", "title": "恶魔", "race": "恶魔", "element": "lightning", "terrain": "ruins", "hp": 93, "mp": 56, "ap": 7, "attack": 20, "defense": 5, "speed": 95, "skill": "thunderbolt", "ultimate": "thunderstorm", "color": "9f87d7", "portrait": "storm_caller"},
	"wind_runner": {"name": "岚翎", "title": "人类", "race": "人类", "element": "wind", "terrain": "plains", "hp": 102, "mp": 62, "ap": 8, "attack": 22, "defense": 6, "speed": 101, "skill": "windblade", "ultimate": "tailwind", "color": "79bd9a", "portrait": "wind_runner"},
	"stone_guard": {"name": "石垣", "title": "矮人", "race": "矮人", "element": "earth", "terrain": "mountain", "hp": 142, "mp": 68, "ap": 9, "attack": 24, "defense": 10, "speed": 84, "skill": "stone_spike", "ultimate": "stonewall", "color": "ba9267", "portrait": "stone_guard"},
	"ironforge": {"name": "铎火", "title": "矮人", "race": "矮人", "element": "fire", "terrain": "mountain", "hp": 120, "mp": 50, "ap": 6, "attack": 26, "defense": 8, "speed": 113, "skill": "ironforge_skill", "ultimate": "ironforge_ult", "color": "7ca9b3", "portrait": "ironforge"},
	"granite": {"name": "岩钉", "title": "矮人", "race": "矮人", "element": "earth", "terrain": "mountain", "hp": 142, "mp": 56, "ap": 7, "attack": 18, "defense": 10, "speed": 84, "skill": "granite_skill", "ultimate": "granite_ult", "color": "93badd", "portrait": "granite"},
	"mistleaf": {"name": "沐叶", "title": "精灵", "race": "精灵", "element": "water", "terrain": "swamp", "hp": 93, "mp": 62, "ap": 8, "attack": 20, "defense": 5, "speed": 89, "skill": "mistleaf_skill", "ultimate": "mistleaf_ult", "color": "9f87d7", "portrait": "mistleaf"},
	"willow": {"name": "暮柳", "title": "精灵", "race": "精灵", "element": "normal", "terrain": "forest", "hp": 102, "mp": 68, "ap": 9, "attack": 22, "defense": 6, "speed": 95, "skill": "willow_skill", "ultimate": "willow_ult", "color": "79bd9a", "portrait": "willow"},
	"ashhorn": {"name": "灰角", "title": "恶魔", "race": "恶魔", "element": "fire", "terrain": "desert", "hp": 111, "mp": 50, "ap": 6, "attack": 24, "defense": 7, "speed": 101, "skill": "ashhorn_skill", "ultimate": "ashhorn_ult", "color": "ba9267", "portrait": "ashhorn"},
	"oathguard": {"name": "契岑", "title": "恶魔", "race": "恶魔", "element": "earth", "terrain": "ruins", "hp": 120, "mp": 56, "ap": 7, "attack": 26, "defense": 8, "speed": 107, "skill": "oathguard_skill", "ultimate": "oathguard_ult", "color": "7ca9b3", "portrait": "oathguard"},
	"highdrake": {"name": "铅翼", "title": "龙", "race": "龙", "element": "earth", "terrain": "mountain", "hp": 84, "mp": 62, "ap": 8, "attack": 18, "defense": 4, "speed": 113, "skill": "highdrake_skill", "ultimate": "highdrake_ult", "color": "93badd", "portrait": "highdrake"},
	"cloudscale": {"name": "霁鳞", "title": "龙", "race": "龙", "element": "wind", "terrain": "plains", "hp": 93, "mp": 68, "ap": 9, "attack": 20, "defense": 5, "speed": 119, "skill": "cloudscale_skill", "ultimate": "cloudscale_ult", "color": "9f87d7", "portrait": "cloudscale"},
	"longroad": {"name": "长路", "title": "人类", "race": "人类", "element": "normal", "terrain": "plains", "hp": 102, "mp": 50, "ap": 6, "attack": 22, "defense": 6, "speed": 89, "skill": "longroad_skill", "ultimate": "longroad_ult", "color": "79bd9a", "portrait": "longroad"},
	"fieldmedic": {"name": "苏茅", "title": "人类", "race": "人类", "element": "water", "terrain": "forest", "hp": 111, "mp": 56, "ap": 7, "attack": 24, "defense": 7, "speed": 95, "skill": "fieldmedic_skill", "ultimate": "fieldmedic_ult", "color": "ba9267", "portrait": "fieldmedic"},
	"siltguard": {"name": "泽栅", "title": "人类", "race": "人类", "element": "water", "terrain": "swamp", "hp": 120, "mp": 62, "ap": 8, "attack": 26, "defense": 8, "speed": 101, "skill": "siltguard_skill", "ultimate": "siltguard_ult", "color": "7ca9b3", "portrait": "siltguard"},
	"seasons": {"name": "梅文娜", "title": "四季之神", "race": "神", "element": "ice", "terrain": "forest", "hp": 84, "mp": 68, "ap": 9, "attack": 18, "defense": 4, "speed": 107, "skill": "seasons_skill", "ultimate": "seasons_ult", "color": "93badd", "portrait": "seasons"},
	"earth_god": {"name": "多兰克", "title": "大地之神", "race": "神", "element": "earth", "terrain": "mountain", "hp": 142, "mp": 50, "ap": 6, "attack": 20, "defense": 10, "speed": 84, "skill": "earth_god_skill", "ultimate": "earth_god_ult", "color": "9f87d7", "portrait": "earth_god"},
	"sky_god": {"name": "莱文索", "title": "天空神", "race": "神", "element": "lightning", "terrain": "desert", "hp": 102, "mp": 56, "ap": 7, "attack": 22, "defense": 6, "speed": 119, "skill": "sky_god_skill", "ultimate": "sky_god_ult", "color": "79bd9a", "portrait": "sky_god"},
	"snowforge": {"name": "砧雪", "title": "矮人", "race": "矮人", "element": "ice", "terrain": "mountain", "hp": 142, "mp": 62, "ap": 8, "attack": 24, "defense": 10, "speed": 84, "skill": "snowforge_skill", "ultimate": "snowforge_ult", "color": "ba9267", "portrait": "snowforge"},
	"cen": {"race": "精灵", "name": "岑枝", "title": "林缘猎人", "hp": 102, "mp": 34, "ap": 8, "attack": 22, "defense": 5, "speed": 113, "skill": "snare", "ultimate": "arrow_rain", "color": "77945c", "element": "normal", "terrain": "forest", "portrait": "cen"},
	"lorne": {"race": "人类", "name": "洛恩", "title": "山路信使", "hp": 88, "mp": 44, "ap": 10, "attack": 18, "defense": 4, "speed": 132, "skill": "trail_shot", "ultimate": "rally", "color": "be9b6c", "element": "normal", "terrain": "mountain", "portrait": "lorne"},
	"eve": {"race": "精灵", "name": "伊芙", "title": "精灵医者", "hp": 90, "mp": 90, "ap": 7, "attack": 14, "defense": 5, "speed": 99, "skill": "heal", "ultimate": "warmth", "color": "b9c69d", "element": "normal", "terrain": "forest", "portrait": "eve"},
	"grit": {"race": "龙", "name": "砾牙", "title": "远山来客", "hp": 155, "mp": 28, "ap": 6, "attack": 28, "defense": 7, "speed": 96, "skill": "rend", "ultimate": "wolf_howl", "color": "adb4b5", "element": "normal", "terrain": "forest", "portrait": "grit"},
	"ember": {"race": "恶魔", "name": "弥烬", "title": "火术师", "hp": 84, "mp": 78, "ap": 5, "attack": 29, "defense": 4, "speed": 94, "skill": "ember", "ultimate": "sunfall", "color": "bc6a52", "element": "fire", "terrain": "ruins", "portrait": "ember"},
	"tide": {"race": "人类", "name": "澄汐", "title": "水文术师", "hp": 93, "mp": 82, "ap": 7, "attack": 22, "defense": 6, "speed": 106, "skill": "torrent", "ultimate": "tide_shelter", "color": "6bafbd", "element": "water", "terrain": "ruins", "portrait": "tide"},
}
const SKILLS = {
	"ironforge_skill": {"name": "战炉火花", "element": "fire", "mp": 8, "energy": 30, "target": "enemy", "power": 1.35},
	"ironforge_ult": {"name": "炉心迸裂", "element": "fire", "mp": 0, "energy": 0, "target": "all_enemies", "power": 1.75},
	"granite_skill": {"name": "盾角撞击", "element": "earth", "mp": 9, "energy": 30, "target": "enemy", "power": 1.45},
	"granite_ult": {"name": "山门列盾", "element": "earth", "mp": 0, "energy": 0, "target": "all_allies", "shield": 31},
	"mistleaf_skill": {"name": "露矢", "element": "water", "mp": 10, "energy": 30, "target": "enemy", "power": 1.55},
	"mistleaf_ult": {"name": "薄雾齐射", "element": "water", "mp": 0, "energy": 0, "target": "all_enemies", "power": 1.99},
	"willow_skill": {"name": "枝影箭", "element": "normal", "mp": 8, "energy": 30, "target": "enemy", "power": 1.65},
	"willow_ult": {"name": "林间连矢", "element": "normal", "mp": 0, "energy": 0, "target": "all_enemies", "power": 2.11},
	"ashhorn_skill": {"name": "灰烬球", "element": "fire", "mp": 9, "energy": 30, "target": "enemy", "power": 1.35},
	"ashhorn_ult": {"name": "焰线横扫", "element": "fire", "mp": 0, "energy": 0, "target": "all_enemies", "power": 2.23},
	"oathguard_skill": {"name": "石印重击", "element": "earth", "mp": 10, "energy": 30, "target": "enemy", "power": 1.45},
	"oathguard_ult": {"name": "守约屏障", "element": "earth", "mp": 0, "energy": 0, "target": "all_allies", "shield": 28},
	"highdrake_skill": {"name": "碎石推掌", "element": "earth", "mp": 8, "energy": 30, "target": "enemy", "power": 1.55},
	"highdrake_ult": {"name": "群峰回震", "element": "earth", "mp": 0, "energy": 0, "target": "all_enemies", "power": 1.87},
	"cloudscale_skill": {"name": "回旋气流", "element": "wind", "mp": 9, "energy": 30, "target": "enemy", "power": 1.65},
	"cloudscale_ult": {"name": "薄云护身", "element": "wind", "mp": 0, "energy": 0, "target": "all_allies", "shield": 34},
	"longroad_skill": {"name": "路边连射", "element": "normal", "mp": 10, "energy": 30, "target": "enemy", "power": 1.35},
	"longroad_ult": {"name": "远行齐箭", "element": "normal", "mp": 0, "energy": 0, "target": "all_enemies", "power": 2.11},
	"fieldmedic_skill": {"name": "清水疗伤", "element": "water", "mp": 8, "energy": 30, "target": "ally", "power": 30, "healing": true},
	"fieldmedic_ult": {"name": "行囊里的药", "element": "water", "mp": 0, "energy": 0, "target": "all_allies", "power": 42, "healing": true},
	"siltguard_skill": {"name": "浅水推击", "element": "water", "mp": 9, "energy": 30, "target": "enemy", "power": 1.55},
	"siltguard_ult": {"name": "涌潮震荡", "element": "water", "mp": 0, "energy": 0, "target": "all_enemies", "power": 1.75},
	"seasons_skill": {"name": "晚霜", "element": "ice", "mp": 10, "energy": 30, "target": "enemy", "power": 1.65, "slow": 2},
	"seasons_ult": {"name": "春回", "element": "ice", "mp": 0, "energy": 0, "target": "all_allies", "power": 42, "healing": true},
	"earth_god_skill": {"name": "地动", "element": "earth", "mp": 8, "energy": 30, "target": "enemy", "power": 1.35},
	"earth_god_ult": {"name": "坚岩屏障", "element": "earth", "mp": 0, "energy": 0, "target": "all_allies", "shield": 34},
	"sky_god_skill": {"name": "落雷", "element": "lightning", "mp": 9, "energy": 30, "target": "enemy", "power": 1.45},
	"sky_god_ult": {"name": "雷雨散开", "element": "lightning", "mp": 0, "energy": 0, "target": "all_enemies", "power": 2.11},
	"snowforge_skill": {"name": "冷锤", "element": "ice", "mp": 10, "energy": 30, "target": "enemy", "power": 1.55, "slow": 2},
	"snowforge_ult": {"name": "雪夜守护", "element": "ice", "mp": 0, "energy": 0, "target": "all_allies", "shield": 40},
	"gravity": {"name": "重压", "mp": 8, "power": 1.5, "target": "enemy", "element": "gravity", "energy": 30, "slow": 2},
	"gravity_drift": {"name": "落石", "mp": 0, "power": 1.45, "target": "all_enemies", "element": "gravity", "energy": 0},
	"gravity_wave": {"name": "坠落", "mp": 0, "power": 1.9, "target": "all_enemies", "element": "gravity", "energy": 0, "slow": 2},
	"attack": {"name": "普通攻击", "mp": 0, "power": 1.0, "target": "enemy", "element": "normal", "energy": 25},
	"trail_shot": {"name": "巡路连射", "mp": 8, "power": 1.55, "target": "enemy", "element": "normal", "energy": 30},
	"snare": {"name": "缠枝箭", "mp": 9, "power": 1.25, "target": "enemy", "element": "normal", "energy": 30, "slow": 2},
	"rend": {"name": "裂石击", "mp": 7, "power": 1.7, "target": "enemy", "element": "normal", "energy": 30},
	"ember": {"name": "燧火", "mp": 10, "power": 1.65, "target": "enemy", "element": "fire", "energy": 30, "environment": "ignite"},
	"torrent": {"name": "回流", "mp": 10, "power": 1.5, "target": "enemy", "element": "water", "energy": 30, "environment": "wet"},
	"heal": {"name": "枝露疗愈", "mp": 12, "power": 38, "target": "ally", "element": "normal", "energy": 20, "healing": true},
	"guard_all": {"name": "灯盾", "mp": 9, "target": "all_allies", "shield": 25, "element": "normal", "energy": 20},
	"rally": {"name": "归途号令", "mp": 0, "target": "all_allies", "shield": 32, "element": "normal", "energy": 0},
	"dawn_strike": {"name": "破晓重击", "mp": 0, "power": 2.6, "target": "all_enemies", "element": "normal", "energy": 0},
	"arrow_rain": {"name": "千枝落羽", "mp": 0, "power": 2.2, "target": "all_enemies", "element": "normal", "energy": 0},
	"warmth": {"name": "不熄的微光", "mp": 0, "power": 65, "target": "all_allies", "healing": true, "element": "normal", "energy": 0},
	"wolf_howl": {"name": "群山长鸣", "mp": 0, "shield": 45, "target": "all_allies", "element": "normal", "energy": 0},
	"sunfall": {"name": "余烬落日", "mp": 0, "power": 2.6, "target": "all_enemies", "element": "fire", "energy": 0, "environment": "ignite"},
	"tide_shelter": {"name": "澄海归潮", "mp": 0, "power": 38, "target": "all_allies", "healing": true, "shield": 25, "element": "water", "energy": 0, "environment": "wet"},
	"frost_arrow": {"name": "凝霜矢", "mp": 9, "power": 1.35, "target": "enemy", "element": "ice", "energy": 30, "slow": 2},
	"frostfall": {"name": "寒霜齐落", "mp": 0, "power": 1.75, "target": "all_enemies", "element": "ice", "energy": 0, "slow": 2},
	"thunderbolt": {"name": "引雷", "mp": 12, "power": 1.75, "target": "enemy", "element": "lightning", "energy": 30},
	"thunderstorm": {"name": "千钧雷阵", "mp": 0, "power": 2.35, "target": "all_enemies", "element": "lightning", "energy": 0},
	"windblade": {"name": "回风刃", "mp": 9, "power": 1.15, "target": "all_enemies", "element": "wind", "energy": 30},
	"tailwind": {"name": "扶摇", "mp": 0, "target": "all_allies", "element": "wind", "energy": 0, "haste": 2},
	"stone_spike": {"name": "石棘", "mp": 8, "power": 1.5, "target": "enemy", "element": "earth", "energy": 30},
	"stonewall": {"name": "磐城", "mp": 0, "shield": 42, "target": "all_allies", "element": "earth", "energy": 0},
}
const ITEMS = {
	"salve": {"name": "疗伤药", "description": "恢复 45 HP，可同地救援重伤者。", "hp": 45},
	"ether": {"name": "澄露", "description": "恢复 30 MP。", "mp": 30},
	"trail_food": {"name": "旅途干粮", "description": "可用于分享与任务；不设每日强制消耗。"},
	"trail_blade": {"name": "巡路短刃", "slot": "weapon", "attack": 4},
	"padded_coat": {"name": "夹棉旅衣", "slot": "armor", "defense": 3},
	"lamp_charm": {"name": "旧灯护符", "slot": "accessory", "speed": 8},
}
const ENEMIES = {
	"boar": {"name": "棘背兽", "hp": 72, "attack": 18, "defense": 7, "speed": 82, "color": "8e7c58", "element": "normal", "role": "保护同伴 · 厚甲", "skill": "guard"},
	"archer": {"name": "荒路弩手", "hp": 53, "attack": 24, "defense": 3, "speed": 94, "color": "98785b", "element": "normal", "role": "蓄力 · 高伤", "skill": "charge"},
	"spider": {"name": "苔伏蛛", "hp": 48, "attack": 16, "defense": 2, "speed": 125, "color": "5c7c58", "element": "normal", "role": "伏击 · 减速", "skill": "slow"},
	"lurker": {"name": "淤泥潜伏者", "hp": 95, "attack": 19, "defense": 8, "speed": 75, "color": "537b78", "element": "water", "role": "潮湿 · 重甲", "skill": "wet"},
	"furnace": {"name": "炉心守卒", "hp": 69, "attack": 23, "defense": 5, "speed": 88, "color": "c17b50", "element": "fire", "role": "点燃场地", "skill": "ignite"},
	"canal": {"name": "渠台守卫", "hp": 76, "attack": 21, "defense": 6, "speed": 90, "color": "699da4", "element": "water", "role": "水击 · 潮湿", "skill": "wet"},
	"swarm": {"name": "巢鸣蜂群", "hp": 31, "attack": 12, "defense": 1, "speed": 151, "color": "d8b76b", "element": "normal", "role": "高速 · 脆弱", "skill": "attack"},
	"apothecary": {"name": "拾荒药师", "hp": 56, "attack": 13, "defense": 3, "speed": 105, "color": "8b9d7b", "element": "normal", "role": "治疗同伴", "skill": "heal"},
	"hunter_elite": {"name": "苔冠猎伏者", "hp": 160, "attack": 29, "defense": 7, "speed": 129, "color": "5e7751", "element": "normal", "role": "精英 · 伏击压制", "skill": "slow"},
	"furnace_elite": {"name": "裂炉监卫", "hp": 185, "attack": 33, "defense": 10, "speed": 85, "color": "ad6248", "element": "fire", "role": "精英 · 火场", "skill": "ignite"},
	"war_god": {"name": "卡德兰", "hp": 250, "attack": 29, "defense": 12, "speed": 103, "color": "bd5447", "element": "normal", "role": "使人陷入疯狂", "skill": "madness"},
	"lamp_boss": {"name": "旧石像", "hp": 320, "attack": 35, "defense": 12, "speed": 108, "color": "bbaa70", "element": "fire", "role": "重装守卫", "skill": "ignite"},
}

static func item_name(id: String) -> String:
	return str(ITEMS.get(id, {}).get("name", id))

static func terrain_name(id: String) -> String:
	return str(TERRAIN.get(id, TERRAIN.plains).name)

static func skill_description(id: String) -> String:
	var skill = SKILLS[id]
	var parts: Array[String] = ["%d MP" % skill.mp]
	parts.append({"enemy": "敌方单体", "ally": "己方单体，可救援", "all_enemies": "敌方全体", "all_allies": "己方在场全体"}[skill.target])
	if skill.element == "gravity":
		parts.append("重力魔法")
	elif skill.element != "normal":
		parts.append(ELEMENT_NAMES[skill.element] + "属性")
	if skill.get("healing", false):
		parts.append("恢复 %d HP" % skill.power)
	elif skill.has("power"):
		parts.append("攻击 ×%.2f" % skill.power)
	if skill.has("shield"):
		parts.append("护盾 +%d，上限 60" % skill.shield)
	if skill.has("slow"):
		parts.append("减速 %d 次行动" % skill.slow)
		if skill.element == "ice":
			parts.append("潮湿时额外减速 1 次")
	if skill.element == "lightning":
		parts.append("潮湿时伤害 ×1.25")
	if skill.has("haste"):
		parts.append("行动速度提高 25%%，持续 %d 个行动间隔" % skill.haste)
	if skill.get("environment", "") == "ignite":
		parts.append("晴天可点燃干燥的森林战场，双方承受持续火伤")
	elif skill.get("environment", "") == "wet":
		parts.append("使本场战地潮湿，降低火系技能伤害")
	return " · ".join(parts)

static func passive_description(id: String) -> String:
	return {"hero": "以重力魔法作战。", "cen": "森林采集额外 +1。", "lorne": "山地移动只需 1 精力。", "eve": "同地可行动时，休整恢复额外 +10 个百分点。", "grit": "辨识附近已发现敌人；在场时令低于 35% HP 的队友减伤 20%。", "ember": "火术可在晴天点燃干燥的森林战场。", "tide": "水术可使当前战场潮湿，减弱火系技能伤害。"}.get(id, "")
