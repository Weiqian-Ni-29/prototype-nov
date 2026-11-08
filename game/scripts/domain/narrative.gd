extends RefCounted

const Catalog = preload("res://scripts/domain/catalog.gd")
const Nodes = preload("res://scripts/domain/map_nodes.gd")

const CHARACTER_BEHAVIOR = {
	"cen": ["寡言，护短，先看行动再听承诺","岑枝把弓放低，摸了摸箭囊的背带。\n「跟紧一点。林子里的路，我认。」","她说话依然很少。队伍走到岔路时，她会先替大家踩一遍。"],
	"lorne": ["热心，做事麻利，总想把口信送到","洛恩一把把信袋甩上肩，已经朝前走了两步。\n「好。路上遇见等信的人，记得叫住我。」","洛恩把信袋里的纸按去处重新排了一遍。"],
	"eve": ["温和，细心，先照看伤员再谈别的","伊芙低头折好绷带，把药包扣起来。\n「我跟你走。半路有人受伤的话，我们停一下。」","伊芙沿路记下哪里可以找到药、哪里还有伤员。"],
	"grit": ["谨慎，守信，说话很少","砾牙抱着手，沉默了一会儿，轻轻点头。\n「我会跟上。你走你的步子。」","砾牙总把脚步放轻，怕惊着路边还在休息的人。"],
	"ember": ["嘴硬，爱开玩笑，重视自己许过的承诺","弥烬把两手塞回衣兜，自己先笑了一声。\n「行啊。奇怪，我答应得比自己想的快。」","弥烬一路上没少开玩笑，答应的活倒没有一件忘掉。"],
	"tide": ["讲究证据，有耐心，习惯事先检查","澄汐把水瓶扣回腰间，又确认了一次瓶塞。\n「走吧。下一个水源在哪里，我想亲眼看看。」","澄汐在背包里留着一小瓶水样。路过下一个村子，她还想请人辨认。"],
	"frost_archer": ["慢热，怕牵连别人，愿意为小事负责","霜弦低头把一支箭的羽毛抚顺。\n「好。走林路的时候，我先看一看。」","霜弦把箭分给了能拉弓的人，自己留了几支备用。"],
	"storm_caller": ["戒备，守约，对莫名的归属感感到困惑","闻霆把手杖收在胸前，仍然一脸疑惑，只点了一下头。\n「这一次，我自己决定。」","闻霆说，他到现在也说不明白自己为什么当时就想跟上来。"],
	"wind_runner": ["急性子，乐观，愿意替人跑一趟","岚翎把围巾甩过肩，等不及似地转向路口。\n「走啊。我这次跟你的步子。」","岚翎找到新路就想先跑过去看看，回来时通常还带着点消息。"],
	"stone_guard": ["务实，少说多做，对同行的人负责","石垣把盾背到身后，空出两只手来。\n「好。前面要搬东西，叫我。」","石垣总把最重的东西分到自己那边。"],
	"ironforge": ["好强，直率，讨厌拿好话掩饰坏事","铎火把锤子扛上肩，另一只手叉着腰。\n「行。哪儿有坏东西要修，先让我看看。」","铎火打算把没用完的工具送到缺工匠的地方。"],
	"granite": ["沉稳，有些固执，讲究照约定办事","岩钉拍了拍胸口，把盾夹到腋下。\n「说定了。遇到岔路，咱们先商量。」","岩钉还记得哪一段坡最滑，打算回去补几根扶手。"],
	"mistleaf": ["耐心，听得多说得少，擅长照顾队尾","沐叶把披风从箭囊边拉开，眼睛已经转向前面的路。\n「我走后面。有人掉队，我看得见。」","沐叶一路记着每个人的脚步声。"],
	"willow": ["内敛，记得自己犯过的错，愿意改","暮柳拂开额前的头发，朝林子看了一眼。\n「一起走吧。前面的路，这次我愿意带外人走。」","暮柳在路牌上补了以前只有族人看得懂的方向。"],
	"ashhorn": ["爱挖苦，待人有礼，关心承诺的分量","灰角把一只手背到身后，夸张地弯了弯腰。\n「既然你请得这么认真，我也认真走一趟。」","灰角偶尔还是用契约的口吻说话。有些事他已经愿意自己做了。"],
	"oathguard": ["冷静，重视界限，决定以后很少反悔","契岑合上账簿，把它夹到身侧。\n「这一次写不写都一样。我答应了。」","契岑在空白的一页记下了路上答应过的人。"],
	"highdrake": ["庄重，怕重犯旧错，把保护看得比胜负重","铅翼闭上眼，郑重地低了一下头。\n「我愿同行。出手以前，请让我先看清附近的人。」","铅翼沿途总先确认附近有人住在哪里。"],
	"cloudscale": ["好奇，情绪藏不住，容易喜欢寻常小事","霁鳞把两只手抱到下巴底下，兴奋得差点抢话。\n「好！下次有地方能烤面包，也叫我。」","霁鳞说，下一次看到炊烟，她还会下去看看。"],
	"longroad": ["干脆，幽默，讲究把答应的消息送到","长路把纸条往围巾下面一别，冲你歪了歪嘴角。\n「成。等送完这张纸，我就跟你走下一段。」","长路把已经收到回话的信折成了另一种形状。"],
	"fieldmedic": ["克制，专注，遇到伤员就先救人","苏茅把药包的系带一把拉紧。\n「好。走慢半步，药瓶别碰碎了。」","苏茅在药袋上缝了两个新口袋，好把急用的东西放在外面。"],
	"siltguard": ["警觉，信任做过事的人，愿意把风险留给自己","泽栅把矛调成拄杖的握法，试了试脚下的木板。\n「我走前面。踩我踩过的地方。」","泽栅还想回到水边看看新钉的木板有没有松。"],
	"seasons": ["温和而郑重，愿意直面自己造成的损失","梅文娜把冻伤的叶片收进衣襟，抬起眼。\n「我和你去。这场战争留下的事，也有我的一份。」","梅文娜记住了沿途几片失收的田地，也记住了还愿意重新播种的人。"],
	"earth_god": ["慎重，沉默，习惯先亲手确认损害","多兰克把石片放进腰袋，把肩转向前路。\n「走吧。看见裂缝就告诉我。」","多兰克打算回到那几段断掉的山路，一段一段看过去。"],
	"sky_god": ["决断快，对自己的责任看得重，习惯用行动表态","莱文索把手套拉紧，目光一直没有离开前面的路。\n「算我一个。走吧。」","莱文索从高处看见几处能重新渡河的地方，把它们告诉了沿途的船工。"],
	"snowforge": ["表面严厉，心软，擅长给别人留条退路","砧雪把钥匙收好，又紧了紧护手上的带子。\n「行。天黑前找到能歇脚的地方，我们再走远一点。」","砧雪仍把那把侧门钥匙留在口袋里。"],
}
const BACKGROUNDS = {
	"cen": "她在封路以前每天穿林送果，战后沿同样的路带村民离开。",
	"lorne": "他给交战双方都送过信，靠每次守信换来通行。",
	"eve": "她出身森林药棚，曾在交战的两边替伤员换药。",
	"grit": "他一直住在远山，最近第一次以人形在山下久留。",
	"ember": "召唤他的人以最后一件传家物换取一次护送，他把人送到了。",
	"tide": "她曾给村里测水，战后改为沿河寻找干净的水源。",
	"frost_archer": "她的家人还在森林里，先送邻家的孩子走是她自己的决定。",
	"storm_caller": "上一个契约要求他保护一艘船。如今船已靠岸，他可以自己决定去向。",
	"wind_runner": "他曾替商队跑腿，战争使他熟悉了每条绕开关卡的小路。",
	"stone_guard": "他带工友修过山路，直到一次塌方把工友隔在另一边。",
	"ironforge": "她曾为两边的军队打兵器，直到弟弟死在其中一把刀下。现在她只接修桥和护身的活。",
	"granite": "他在城邦守过三十年城门，退下来后专给没有护卫的商队带路。",
	"mistleaf": "她在森林边缘出生，战后把家借给从沼泽迁来的孩子，自己靠打猎送粮。",
	"willow": "他曾封闭族里的猎径，后来发现自己的决定也困住了等药的人。",
	"ashhorn": "一名商人召唤他保住最后一车水，代价是十年积蓄。他把水送到了，商人却再也没回来。",
	"oathguard": "她曾被要求守一座空堡，直到契约上的日期过去。离开堡垒后，她开始自己选择值得守的地方。",
	"highdrake": "他曾用原形拦过军队，山崩也伤了附近的百姓。从那以后，他大多以人形走路。",
	"cloudscale": "她的巢在荒无人烟的海崖。第一次下山时，一家人类农户教她怎样在炉边烤面包。",
	"longroad": "她替交战双方运过货，后来专门给沿路的村庄捎信，只收一碗热汤。",
	"fieldmedic": "他原本在军队里做医师，因坚持救治敌方伤员而被赶了出来。",
	"siltguard": "他守过沼泽的渡口，战后帮幸存的船工重修栈道。",
	"seasons": "她曾为了保住一片收成提前带来严冬，直到后来才知道，邻谷在那一冬饿死了许多人。",
	"earth_god": "他曾震开山道以阻止大军进城，事后发现坍塌的路也挡住了逃难的人。",
	"sky_god": "她曾用暴风挡住渡河的战船，直到收到岸边村庄求救的消息。",
	"snowforge": "她负责城邦的外门，封门命令下来时，仍偷偷留着一条供难民进出的侧道。",
}
const COMPANION_LINES = {
	"ironforge": "我替附近的人修了几把锄头。要是前面的路还通，我想把工具送过去。",
	"granite": "腿脚不如从前，盾还顶得住。你要过山的话，我熟这边的石路。",
	"mistleaf": "水边还有几处能过。你走在前面的话，我可以用箭帮你探路。",
	"willow": "我知道几条旧猎径。以前我不让外人走，现在想想，路本来就该给需要的人走。",
	"ashhorn": "契约已经做完了。你说要继续往前？奇怪，我听见你这么说，就想搭把手。",
	"oathguard": "这次我想自己选该守什么。你站在这儿，我倒有点像回到故乡。",
	"highdrake": "我能帮忙，但请先让我看看旁边有没有人住。我已经为一次冲动后悔够久了。",
	"cloudscale": "这几天我闻见炊烟就想往那边走。你也找一条能让人安心过日子的路吗？",
	"longroad": "我得给前面的人报个平安。你愿意结伴，我也好少回几次头。",
	"fieldmedic": "药得用在人身上。你愿意帮我带着这些去下一处村子吗？我也可以照看你的伤。",
	"siltguard": "我把坏的木板都翻了面。前面还有一截桥没看过，一起走？",
	"seasons": "我沿路看看那些提早落下的霜。亲眼看完这些，我想跟你谈谈该怎么停下这场战争。",
	"earth_god": "我认得这些裂缝。下一段路，我愿意走在最前面，看看还能救下什么。",
	"sky_god": "我从高处看见的是军队，走到这儿才看见村庄。你要去战神那边的话，我想一同去。",
	"snowforge": "门后的人都安全了。我想看看那条小路还能通到哪儿。你愿意一起走吗？",
	"cen": "我在这附近找一条还能走的林路。打仗的人把好几条路都封了，住在那边的人还要出来找吃的。",
	"lorne": "我出来送消息，前面有一段路过不去。你要往那边走的话，我们可以搭个伴。",
	"eve": "刚给人包完伤口。我想看看下一处村子有没有缺药的人，路上多双手总是好的。",
	"grit": "我住的山离这里很远。本来只想下山看看，可沿路遇到的事，总不能都绕开。",
	"ember": "召我来的人托我送一队人到安全的地方。事情办完了。说起来奇怪，我第一次见你，却觉得跟你走挺安心的。",
	"tide": "最近几处水源都出了问题。我在往前查，有人一起走，出了事也好照应。",
	"frost_archer": "我在找还通着的林路，附近的人需要一条能带孩子离开的路。",
	"storm_caller": "上一份契约已经做完。我本来想回去，可听你说话，总觉得在哪儿听过。",
	"wind_runner": "有几支商队在等消息。我打算沿路看看哪座桥还能过。",
	"stone_guard": "我从城邦带了些修桥的工具下来。路上的事太多，一个人忙不过来。",
}
var run: RefCounted

func _init(expedition: RefCounted) -> void:
	run = expedition

func _choice(id: String, label: String) -> Dictionary:
	return {"id": id, "text": label, "enabled": true, "reason": ""}

func encounter_intro(visitor: String, subject: String) -> Dictionary:
	var member = run.actor(visitor)
	var person = run.actor(subject)
	if member.is_empty() or member.hp <= 0 or person.is_empty() or subject == visitor or person.position != member.position:
		return {"ok": false, "message": "要到同一处才能交谈。", "beats": []}
	if not run.data.tiles[person.position].enemies.is_empty():
		return {"ok": false, "message": "先处理这里的危险，再和对方交谈。", "beats": []}
	return {"ok": true, "beats": []}

func dialogue(visitor: String, subject: String) -> Dictionary:
	var intro = encounter_intro(visitor, subject)
	if not intro.ok:
		return intro
	var person = run.actor(subject)
	run.data.story[subject].met = true
	var title = "%s · %s" % [person.name, person.get("race", "旅人")]
	var body: String = BACKGROUNDS[subject] + "\n\n「" + COMPANION_LINES[subject] + "」"
	var node = run.node_at(person.position)
	var choices: Array = []
	if person.hp <= 0:
		body = "对方伤得很重。可以在同地使用药物救助。"
		choices.append(_choice("rescue", "使用药物救助"))
	elif person.joined:
		body = CHARACTER_BEHAVIOR[subject][2]
	else:
		choices.append(_choice("join", "邀请一起上路"))
		if not node.result.is_empty():
			choices.append(_choice("discuss", "聊聊这里发生的事"))
		if subject in ["granite", "ashhorn", "oathguard", "highdrake", "siltguard", "snowforge"] and not run.data.story[subject].get("duel", false) and run.actor(visitor).ap >= Catalog.BATTLE_AP:
			choices.append(_choice("duel", "提出交手，确认彼此的实力"))
	choices.append(_choice("leave", "结束交谈"))
	var pose = "friendly" if person.joined or not node.result.is_empty() else "serious" if node.get("kind") == "haunt" or person.hp <= 0 else ""
	return {"ok": true, "title": title, "text": body, "options": choices, "pose": pose}

func choose(visitor: String, subject: String, option_id: String) -> Dictionary:
	var d = dialogue(visitor, subject)
	if not d.ok:
		return d
	if not d.options.any(func(option): return option.id == option_id):
		return {"ok": false, "message": "现在无法这样做。"}
	match option_id:
		"join":
			var result = run.join_companion(subject, visitor)
			if result.ok:
				result.response = CHARACTER_BEHAVIOR[subject][1]
				run.record_story_progress(run.actor(visitor).position, false)
			return result
		"duel":
			var cell: String = run.actor(visitor).position
			run.data.story[subject].duel = true
			run.data.pending_battle = {"position": cell, "origin": cell, "npc": subject, "ambush": false, "movers": []}
			return {"ok": true, "battle": true}
		"discuss":
			return {"ok": true, "response": "「刚才总算是把事情说清了。前面如果还遇见类似的事，先听听那边的人怎么讲。」"}
		"rescue":
			return {"ok": true, "rescue": true}
	return {"ok": true, "close": true}

func main_ending() -> Dictionary:
	if run.data.status == "won":
		return {"title": "终于可以告别", "text": "卡德兰倒下了。冥河退去后，战场上只剩风声。\n\n各地的亡者有了归处，诸神也终于停下这场战争。那个在村屋里醒来的旅人还记得村民送给他的第一包药。现在，他可以回去告诉他们，外面的仗打完了。"}
	return {"title": "这次没能走到最后", "text": run.data.flags.get("failure_reason", "远征在这里中断了。")}

func character_ending(id: String) -> Dictionary:
	var person = run.actor(id)
	var result = "你们一起走过一段路。"
	if person.hp <= 0:
		result = "%s受了伤，伙伴们记得他一路所做的事。" % person.name
	elif person.joined:
		result = "%s听见了停战的消息。他收拾行装，打算回去看看一路遇到的人。" % person.name if run.data.status == "won" else "%s和你走到了这里。前面的路还没走完。" % person.name
	else:
		result = "%s留在原来的地方，继续做手头的事。" % person.name
	return {"name": person.name, "text": result}
