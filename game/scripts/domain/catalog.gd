class_name GameCatalog
extends RefCounted
## Versioned, intentionally modest MVP balance values. AP is individual, never shared.

const VERSION = 1
const RADIUS = 8
const BATTLE_AP = 2
const DAILY_HP = 0.16
const DAILY_MP = 0.22
const ENERGY_MAX = 100
const TERRAIN = {
	"plains": {"name": "平原", "cost": 1, "color": "91a577"},
	"forest": {"name": "森林", "cost": 1, "color": "47765b"},
	"mountain": {"name": "山地", "cost": 2, "color": "8d9290"},
	"ruins": {"name": "遗迹", "cost": 1, "color": "aba28b"},
	"desert": {"name": "沙漠", "cost": 1, "color": "cfb578"},
	"swamp": {"name": "沼泽", "cost": 2, "color": "657c72"},
	"scorched": {"name": "焦土", "cost": 1, "color": "605951"},
	"lake": {"name": "湖泊", "cost": 0, "color": "397d84"},
}
const PROFESSIONS = {
	"wayfarer": {"name": "巡路客", "description": "善于探索和支援，行动频繁。", "hp": 95, "mp": 48, "ap": 9, "attack": 18, "defense": 5, "speed": 122, "skill": "trail_shot", "ultimate": "rally", "color": "caa76d"},
	"guardian": {"name": "守灯卫", "description": "高生命与防护，机动较低。", "hp": 145, "mp": 35, "ap": 5, "attack": 24, "defense": 10, "speed": 83, "skill": "guard_all", "ultimate": "dawn_strike", "color": "799cba"},
	"arcanist": {"name": "烛纹师", "description": "以魔力施展火焰与治疗。", "hp": 83, "mp": 85, "ap": 7, "attack": 23, "defense": 4, "speed": 101, "skill": "ember", "ultimate": "warmth", "color": "b78aac"},
}
const COMPANIONS = {
	"cen": {"name": "岑枝", "title": "林缘猎人", "hp": 102, "mp": 34, "ap": 8, "attack": 22, "defense": 5, "speed": 113, "skill": "snare", "ultimate": "arrow_rain", "color": "77945c", "element": "normal", "terrain": "forest", "portrait": "cen"},
	"lorne": {"name": "洛恩", "title": "山路信使", "hp": 88, "mp": 44, "ap": 10, "attack": 18, "defense": 4, "speed": 132, "skill": "trail_shot", "ultimate": "rally", "color": "be9b6c", "element": "normal", "terrain": "mountain", "portrait": "lorne"},
	"eve": {"name": "伊芙", "title": "精灵医者", "hp": 90, "mp": 90, "ap": 7, "attack": 14, "defense": 5, "speed": 99, "skill": "heal", "ultimate": "warmth", "color": "b9c69d", "element": "normal", "terrain": "forest", "portrait": "eve"},
	"grit": {"name": "砾牙", "title": "循迹巨狼", "hp": 155, "mp": 28, "ap": 6, "attack": 28, "defense": 7, "speed": 96, "skill": "rend", "ultimate": "wolf_howl", "color": "adb4b5", "element": "normal", "terrain": "forest", "portrait": "grit"},
	"ember": {"name": "弥烬", "title": "清障火术师", "hp": 84, "mp": 78, "ap": 5, "attack": 29, "defense": 4, "speed": 94, "skill": "ember", "ultimate": "sunfall", "color": "bc6a52", "element": "fire", "terrain": "ruins", "portrait": "ember"},
	"tide": {"name": "澄汐", "title": "水文术师", "hp": 93, "mp": 82, "ap": 7, "attack": 22, "defense": 6, "speed": 106, "skill": "torrent", "ultimate": "tide_shelter", "color": "6bafbd", "element": "water", "terrain": "ruins", "portrait": "tide"},
}
const SKILLS = {
	"attack": {"name": "普通攻击", "mp": 0, "power": 1.0, "target": "enemy", "element": "normal", "energy": 25},
	"trail_shot": {"name": "巡路连射", "mp": 8, "power": 1.55, "target": "enemy", "element": "normal", "energy": 30},
	"snare": {"name": "缠枝箭", "mp": 9, "power": 1.25, "target": "enemy", "element": "normal", "energy": 30, "slow": 2},
	"rend": {"name": "碎岩咬", "mp": 7, "power": 1.7, "target": "enemy", "element": "normal", "energy": 30},
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
}
const ITEMS = {
	"salve": {"name": "疗伤药", "description": "恢复 45 HP，可同地救援重伤者。", "hp": 45},
	"ether": {"name": "澄露", "description": "恢复 30 MP。", "mp": 30},
	"timber": {"name": "营地木料", "description": "两份木料可建立一处营地。"},
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
	"canal": {"name": "渠台守卫", "hp": 76, "attack": 21, "defense": 6, "speed": 90, "color": "699da4", "element": "water", "role": "水击 · 灭火", "skill": "wet"},
	"swarm": {"name": "巢鸣蜂群", "hp": 31, "attack": 12, "defense": 1, "speed": 151, "color": "d8b76b", "element": "normal", "role": "高速 · 脆弱", "skill": "attack"},
	"apothecary": {"name": "拾荒药师", "hp": 56, "attack": 13, "defense": 3, "speed": 105, "color": "8b9d7b", "element": "normal", "role": "治疗同伴", "skill": "heal"},
	"hunter_elite": {"name": "苔冠猎伏者", "hp": 160, "attack": 29, "defense": 7, "speed": 129, "color": "5e7751", "element": "normal", "role": "精英 · 伏击压制", "skill": "slow"},
	"furnace_elite": {"name": "裂炉监卫", "hp": 185, "attack": 33, "defense": 10, "speed": 85, "color": "ad6248", "element": "fire", "role": "精英 · 火场", "skill": "ignite"},
	"lamp_boss": {"name": "旧驿灯卫", "hp": 320, "attack": 35, "defense": 12, "speed": 108, "color": "bbaa70", "element": "fire", "role": "可选首领 · 不阻挡撤离", "skill": "ignite"},
}

static func item_name(id: String) -> String:
	return str(ITEMS.get(id, {}).get("name", id))

static func terrain_name(id: String) -> String:
	return str(TERRAIN.get(id, TERRAIN.plains).name)

static func skill_description(id: String) -> String:
	var skill = SKILLS[id]
	var parts: Array[String] = ["%d MP" % skill.mp]
	parts.append({"enemy": "敌方单体", "ally": "己方单体，可救援", "all_enemies": "敌方全体", "all_allies": "己方在场全体"}[skill.target])
	if skill.get("healing", false):
		parts.append("恢复 %d HP" % skill.power)
	elif skill.has("power"):
		parts.append("攻击 ×%.2f" % skill.power)
	if skill.has("shield"):
		parts.append("护盾 +%d，上限 60" % skill.shield)
	if skill.has("slow"):
		parts.append("减速 2 次行动")
	if skill.get("environment", "") == "ignite":
		parts.append("点燃当前干燥森林，双方承受火伤")
	elif skill.get("environment", "") == "wet":
		parts.append("当前格灭火并浸湿")
	return " · ".join(parts)

static func passive_description(id: String) -> String:
	return {"hero": "职业决定各自的生命、魔力、机动与技能。", "cen": "未烧毁森林采集额外 +1。", "lorne": "山地移动只需 1 AP。", "eve": "同地可行动时，休整恢复额外 +10 个百分点。", "grit": "辨识附近已发现敌人；在场时令低于 35% HP 的队友减伤 20%。", "ember": "可花 1 AP / 8 MP 点燃当前干燥森林。", "tide": "可花 1 AP / 8 MP 对当前地块灭火或浸湿。"}.get(id, "")
