extends RefCounted

const DATA = {
	"telescope": {"name": "望远镜", "once": false, "effect": "每名可行动队员的视野扩大到两圈。", "story": "你擦去铜镜筒上的泥。镜片照出雾里的山脊，同伴接过镜筒，一起记住了雾里露出的道路。"},
	"trail_boots": {"name": "轻行靴", "once": false, "effect": "全队每次移动少花 1 点精力，最低花费为 1。", "story": "驿亭里留着一双轻行靴。鞋底的纹路能稳住脚步，队里的工匠照着给每人补了一双。"},
	"ranged_sight": {"name": "远射准星", "once": false, "effect": "所有远程角色攻击力 +15%。", "story": "你从远射手留下的器具中取出刻度清晰的准星。队里的射手和术师都能按这些刻度重新校准瞄点。"},
	"lamp_badge": {"name": "护灯徽章", "once": false, "effect": "每场战斗首次上场时，队员获得相当于自身生命上限 12% 的护盾。", "story": "守卫倒下后，胸前的徽章还亮着。有人认出这是以前分给护送队的徽章，便把护身的办法教给了同行的人。"},
	"herbal_case": {"name": "青枝药匣", "once": false, "effect": "全队使用恢复生命的道具时，恢复量提高 25%。", "story": "药棚已经空了，青枝药匣的内盖还留着调配刻线。照刻线研开药膏，原本留在容器里的药质也能用上。"},
	"rainstone": {"name": "雨纹石", "once": false, "effect": "此后每天结算天气时，降雨概率提高 20 个百分点。", "story": "旧测雨台上有块布满水纹的石头。带走它时，石缝里的湿气没有散开，像是总有一小股云在随队而行。"},
	"life_seed": {"name": "生命之种", "once": true, "effect": "本局全队生命上限 +20%，后来加入的伙伴也享受加成。", "story": "一粒封在蜡里的种子还活着。你把它带在身边，同行的人一路都能感到它的暖意。"},
	"road_hourglass": {"name": "余程沙漏", "once": true, "effect": "所有可行动队员立即恢复 2 点精力，最多到个人上限。", "story": "巡守的行囊里有只歪倒的沙漏。你把它扶正，最后一撮沙落了下去。远征队的人都缓过了一口气。"},
	"stillwater_stone": {"name": "静泉石", "once": true, "effect": "所有可行动队员立即恢复自身魔力上限的 40%，最多到个人上限。", "story": "封存的泉眼只剩一泓浅水。你捧起泉底的石头，最后一圈涟漪沿着队伍的行囊传开，石面也随之干了。"},
	"rain_bell": {"name": "引雨铃", "once": true, "effect": "当天立即转为细雨。", "story": "这只铃一直挂在干涸的渠边。你摇了一下，铃声很轻。过了一会儿，细雨落了下来。"},
}

const SITES = {
	"telescope": ["旧观测点", "mountain"],
	"trail_boots": ["旧商路驿亭", "plains"],
	"herbal_case": ["废弃医棚", "forest"],
	"rainstone": ["旧测雨台", "swamp"],
	"stillwater_stone": ["封存泉眼", "ruins"],
}

static func exploration_sites(tiles: Dictionary, seed_value: int) -> Dictionary:
	var sites = {}
	for relic in SITES:
		var candidates = tiles.keys().filter(func(id):
			var tile = tiles[id]
			return tile.site.is_empty() and tile.npc.is_empty() and tile.base_terrain == SITES[relic][1])
		candidates.sort_custom(func(a, b):
			var left = hash("%d:%s:%s" % [seed_value, relic, a])
			var right = hash("%d:%s:%s" % [seed_value, relic, b])
			return a < b if left == right else left < right)
		for id in candidates.slice(0, 4):
			sites[id] = relic
	return sites

static func battle_rewards(types: Array) -> Array[String]:
	var candidates: Array[String] = []
	if types.has("archer"):
		candidates.append("ranged_sight")
	if types.has("furnace_elite") or types.has("lamp_boss"):
		candidates.append("lamp_badge")
	if types.has("boar") or types.has("furnace") or types.has("canal"):
		candidates.append("road_hourglass")
	return candidates
