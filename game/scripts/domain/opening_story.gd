extends RefCounted

const DEPARTURE = "你醒了？我们在战场上找到你，你连名字都忘了。带上这副牌，沿鼓声走。"

const VILLAGES = {
	"plains": ["河边村庄", "human"],
	"forest": ["林间村庄", "elf"],
	"mountain": ["山间村庄", "dwarf"],
	"desert": ["沙地村庄", "human"],
	"swamp": ["水边村庄", "elf"],
}

static func village(terrain: String) -> Array:
	return VILLAGES.get(terrain, VILLAGES.plains)

static func terrain(seed_value: int) -> String:
	return VILLAGES.keys()[posmod(hash("village:%d" % seed_value), VILLAGES.size())]
