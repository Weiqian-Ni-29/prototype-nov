extends RefCounted

const COMPANION_LINES = {
	"frost_archer": "她在酒馆喝冰水，通常连杯子也冻上了。",
	"storm_caller": "他试着给湿透的灯打火，吓跑了三只螃蟹。",
	"wind_runner": "她把餐桌布系在桨上，临时做了张帆。",
	"stone_guard": "水涌进来时，他抱住了酒柜。",
	"ironforge": "他出门只带了锤子，没想到还真用得上。",
	"granite": "他不喝酒，来酒馆只是为了找人下棋。",
	"mistleaf": "她从进水的柜子里救出了一盆薄荷。",
	"willow": "他拿皮带和木勺做了一支钓竿。",
	"ashhorn": "他一直举着一盏没灭的油灯。",
	"oathguard": "他把仅剩的一块干毛巾先递给了别人。",
	"highdrake": "他说自己会飞，但今天这里实在太窄。",
	"cloudscale": "她认得每一种绳结，也认得打错的那个。",
	"longroad": "他在门框上划了道线，想看看水还会涨多少。",
	"fieldmedic": "她从水里拎起药箱，里面还有两卷干绷带。",
	"siltguard": "他踩着门板划过来，说这比上班有意思。",
	"seasons": "老板娘梅姨端着一盆还能吃的炖菜。",
	"earth_god": "他从碎木里挑了三块宽板，打算钉个筏子。",
	"sky_god": "他拿一根坏桅杆试了试水深。",
	"snowforge": "她把坏铁钩敲直，重新挂上了门。",
	"cen": "她只要听一声水响，就能指出哪里能落脚。",
	"lorne": "洛恩替人送酒，跟最后一桶酒一起漂了过来。",
	"eve": "伊芙把湿外套剪开，给摔伤的人绑了个吊带。",
	"grit": "砾牙掀开水里的桌子，找到两条还活着的鱼。",
	"ember": "弥烬一直护着炉火，说湿靴子总得烤干。",
	"tide": "澄汐顺手抛了根绳，把漂远的三个人拉回来。",
}

var run: RefCounted

func _init(expedition: RefCounted) -> void:
	run = expedition

func character_records(id: String) -> Array[Dictionary]:
	if id == "hero":
		return [{"body": "你刚在酒馆坐下，转眼就被鲸吞了。"}]
	if run.actor(id).get("joined", false) or run.data.story.get(id, {}).get("met", false):
		return [{"body": COMPANION_LINES[id]}]
	return []

func main_ending() -> Dictionary:
	if run.data.status == "won":
		return {"title": "回到海面", "text": "招牌摆正了。你刚才那杯还喝吗？"}
	return {"title": "没能出去", "text": run.data.flags.get("failure_reason", "你没能找到出口。")}
