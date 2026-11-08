class_name Narrative
extends RefCounted
## Authored, finite branches. Objects, knowledge, consent, companionship and location are distinct.
const Catalog = preload("res://scripts/domain/catalog.gd")
const EncounterStory = preload("res://scripts/domain/encounter_story.gd")
var run: RefCounted
const DOCUMENTS = {
	"Q-T": "测绘委托登记副本", "Q-TR": "测绘登记回执", "Q-A": "迁离完成摘要摘录",
	"Q-B": "原始接应回执", "Q-C": "乔禾本户证词", "Q-D": "陆衡补充说明",
	"Q-L": "乔穗的旧信", "Q-M": "伊芙药箱", "Q-R": "送药接收回执",
	"Q-G": "舒远诊疗与安葬摘录", "Q-WA": "旧水文稿", "Q-WB": "旧水位拓片",
	"Q-WC": "调闸维护页与流向记录", "Q-TERMS": "本户通行与送药条款", "Q-BOUND": "林地使用边界意见",
	"Q-GAUGE": "修好的水位标尺",
}
const PERSONAL = {
	"cen": {"E0": "林口的问题还没有得到答复。岑枝没有把沉默当作承诺。", "E1": "边界意见已交到归航站，也已当面回告。岑枝在地图边缘添上仍有人使用的林路。", "E2": "你坚持无视林地使用情况的直线清障。岑枝收起私人路线图，旅途中留下了一道尚未弥合的分歧。"},
	"lorne": {"E0": "投递或回告尚未完成，洛恩没有替收件人签下名字。", "E1": "旧信真实交到乔禾手中，签收也已当面告知。迟到的是信件，不是替别人作决定的权利。", "E2": "按乔禾的意愿，原信确实带回洛恩手中封存。未读不是没有结果。", "E3": "未经许可拆信的事实已经被洛恩知晓。即使信后来送达，信任的裂痕也没有被改写。"},
	"eve": {"E0": "药箱的去向或回执仍待核对，伊芙没有提前写下送达。", "E1": "乔禾家逐项核对原清单，回执真实送回。伊芙合上药箱簿，这次没有遗漏一个名字。", "E2": "应急分药事先说明并修改清单，剩余药物与实际签收相符。伊芙记录了缺口，也记录了理由。", "E3": "隐瞒的药物差异已被发现。伊芙拒绝把缺失写成齐备，把有差异的那一页留在簿里。"},
	"grit": {"E0": "扣环上的名字与旧营地的线索还没有合在一起。砾牙没有得到确定的回答。", "E1": "诊疗摘录、刻名扣环与墓记核对一致。砾牙承认舒远已去世，愿意走新的路。", "E2": "证据核实之后，砾牙表达了暂时守候的意愿；愿望没有替他跨越实际距离。", "E3": "证据尚不足，你明确没有把推测写成死讯。砾牙接受目前未证实的答案，仍可自行选择同行。"},
	"ember": {"E0": "误会可以消除，清障的判断却尚未完成。弥烬还没有签下新的记录。", "E1": "危险已解除，林地也保留下来。弥烬把没有点燃的那场火记进清障记录。", "E2": "火场或焦土的代价确实发生，你们当面承认损失，没有把灰烬写成空白。", "E3": "你要求掩去已知损失。弥烬拒绝签假报，分歧被保留下来。", "E4": "清障地点没有再响起他的回答。弥烬重伤未醒，最后见到他的人还记得那场冲突；他尚未加入远征队。"},
	"tide": {"E0": "水位与旧稿还没有形成当面的结论，那一行仍留空。", "E1": "澄汐保留原稿，在旁边添上真实刻度与有来源的维护记录。哪些问题尚无证据，她就仍留着空白。", "E2": "记录只写亲眼所见与可核实的事实。澄汐没有把局部刻度解释成整个世界的答案。", "E3": "澄汐拒绝伪造或删除不利数据。原稿、刻度与已取得的材料没有因此消失。"},
}

func _init(expedition: RefCounted) -> void:
	run = expedition

func _has(visitor: String, item: String) -> bool:
	return int(run.actor(visitor).inventory.get(item, 0)) > 0

func _knows(visitor: String, fact: String) -> bool:
	return run.data.knowledge.get(visitor, {}).get(fact, false)

func _learn(visitor: String, fact: String) -> void:
	for id in run.same_cell(run.actor(visitor).position, true):
		if not run.data.knowledge.has(id):
			run.data.knowledge[id] = {}
		run.data.knowledge[id][fact] = true

func _grant(visitor: String, item: String) -> bool:
	var source = "taken_" + item
	if run.data.flags.get(source, false):
		return false
	run.actor(visitor).inventory[item] = int(run.actor(visitor).inventory.get(item, 0)) + 1
	run.data.flags[source] = true
	return true

func _consume(visitor: String, item: String) -> bool:
	if not _has(visitor, item):
		return false
	run.actor(visitor).inventory[item] -= 1
	return true

func _hand_over(owner: String, visitor: String, item: String) -> bool:
	if run.actor(owner).position != run.actor(visitor).position or not _has(owner, item):
		return false
	if owner != visitor:
		_consume(owner, item)
		run.actor(visitor).inventory[item] = int(run.actor(visitor).inventory.get(item, 0)) + 1
	return true

func _result(id: String, result: String) -> void:
	if id == "lorne" and run.data.story[id].result == "E3" and result != "E3":
		return
	run.data.story[id].result = result
	if id == "cen" and result == "E2" and not run.actor(id).joined:
		run.data.flags["invite_cen"] = false
	run.note(run.actor(id).name + " · " + PERSONAL[id][result])

func _choice(id: String, text: String, enabled: bool = true, reason: String = "") -> Dictionary:
	return {"id": id, "text": text, "enabled": enabled, "reason": reason}

func _valid(visitor: String, subject: String) -> String:
	if run.data.status != "exploring" or not run.data.pending_battle.is_empty():
		return "当前遭遇尚未结束。"
	var a = run.actor(visitor)
	if a.is_empty() or not a.joined or a.hp <= 0:
		return "需要可行动的角色实际到场。"
	if run.data.actors.has(subject):
		if run.actor(subject).position != a.position:
			return "需要和对方在同一地块交谈。"
	elif run.data.tiles[a.position].site != subject:
		return "该角色不在对应地点。"
	return ""

func encounter_intro(visitor: String, subject: String) -> Dictionary:
	var invalid = _valid(visitor, subject)
	if invalid != "":
		return {"ok": false, "message": invalid}
	var beats: Array = EncounterStory.BEATS.get(subject, [])
	if beats.is_empty():
		return {"ok": true, "beats": []}
	if run.data.story.has(subject):
		if run.data.story[subject].met or run.actor(subject).hp <= 0:
			beats = []
	elif run.data.flags.get("intro_seen_" + subject, false) or run.data.choices.any(func(choice): return choice.get("subject") == subject):
		beats = []
	return {"ok": true, "beats": beats}

func dialogue(visitor: String, subject: String) -> Dictionary:
	var invalid = _valid(visitor, subject)
	if invalid != "":
		return {"ok": false, "message": invalid}
	var options: Array = []
	var title = "旧灯路上的人"
	var text = ""
	var flags = run.data.flags
	var actor = run.actor(visitor)
	var can_investigate = actor.ap >= 1
	if run.data.actors.has(subject):
		var npc = run.actor(subject)
		title = npc.name + " · " + npc.title
		run.data.story[subject].met = true
		if run.data.story[subject].relation == "unmet":
			run.data.story[subject].relation = "met"
		if npc.hp <= 0:
			var rescue_choices = [_choice("rescue", "使用个人道具救援", _has(visitor, "salve"), "需要携带疗伤药")]
			if actor.skill == "heal":
				rescue_choices.append(_choice("rescue_skill", "治疗救援 · 1 精力 / 12 MP", can_investigate and actor.mp >= 12, "需要 1 精力 和 12 MP"))
			rescue_choices.append(_choice("leave", "暂时离开，保留回访机会"))
			return {"ok": true, "subject": subject, "title": title, "text": "对方仍昏迷着，无法交谈。可由同地队友使用疗伤药或治疗技能救援。", "options": rescue_choices}
		match subject:
			"cen":
				text = "“脚别往前。你踩的是网绳。”\n岑枝用肩抵着一根弯枝，网里扑腾着一只信鸟。“帮我托一下？等它飞走，我再指给你看林子里哪条路有人走。”"
				if flags.get("cen_helped", false):
					text = "岑枝摊开林地图，指尖沿着一条弯弯的细线走。\n“有人每天走这条小路去药草坡。你给归航站画图的时候，记得留上这一笔。”"
				if run.data.tiles[run.actor(visitor).position].site == "forest":
					_learn(visitor, "cen_boundary")
				options.append(_choice("help", "扶住树枝，帮她放开捕网", not flags.get("cen_helped", false), "鸟已经放走，帮助不重复发生"))
				options.append(_choice("boundary", "如实记录仍在使用的林地边界", _knows(visitor, "cen_boundary"), "需实际观察林地界标或同地交换见闻"))
				options.append(_choice("straight", "坚持直线清障，不考虑林地使用情况"))
				options.append(_choice("report", "当面回告：边界意见已实际送站", _knows(visitor, "boundary_submitted"), "需把边界意见真实交到归航站，并当面回告"))
			"lorne":
				text = "洛恩正把旧路牌转回正确方向。\n“你是从断桥那边来的？顺着这些灯走，归航站还有船。我得先去林边找乔禾。这封信在旧邮仓躺了好多年，读不读，得由她自己决定。”"
				if npc.joined or run.data.story.lorne.result != "E0":
					text = "洛恩检查信袋上的旧地址与已有记录。\n“信的去向已经发生的，就不能重新说成还没发生。下一段路，我们照实际情况走。”"
				options.append(_choice("letter", "接过原信，答应实际代送", _has("lorne", "Q-L") and run.data.story.lorne.result != "E2", "原信已交给持有人，或已按收件人意愿封存"))
				options.append(_choice("letter_report", "当面说明旧信的真实结果", _knows(visitor, "letter_delivered") or _knows(visitor, "letter_opened") or (_knows(visitor, "letter_sealed") and (_has(visitor, "Q-L") or _has("lorne", "Q-L"))), "需亲历投递/私拆，或实际带回封存原信"))
				flags["invite_lorne"] = true
			"eve":
				text = "树荫下，伊芙把最后一只药瓶裹进干布，塞进箱角。\n“你若往林边走，能替我把这箱药捎给乔禾吗？旧驿站把她家写在清单上了。请她照单点一遍，再把签好的回执带给我。”"
				if flags.get("medicine_receipt_returned", false):
					text = "伊芙把回执夹在原清单后面。\n“以后有人来查这箱药，就让他两页一起看。”"
				elif not _has("eve", "Q-M"):
					text = "伊芙的药箱簿摊在膝上，签收栏还空着。\n“箱子已经托出去了。我得见到乔禾的回执，才好填这一栏。”"
				options.append(_choice("medicine", "接取药箱，送往乔禾家", _has("eve", "Q-M"), "药箱已在实际接取者处"))
				options.append(_choice("emergency", "说明应急分药，改写清单并实际分出一份", _has(visitor, "Q-M") and not flags.get("medicine_split", false), "需要实际携带尚未分药的药箱"))
				options.append(_choice("conceal", "隐瞒取走一份药物", _has(visitor, "Q-M") and not flags.get("medicine_split", false), "需要实际携带尚未分药的药箱"))
				options.append(_choice("medicine_report", "交回真实回执，核对送药结果", _has(visitor, "Q-R"), "回执需实际带到伊芙身边"))
				if flags.get("medicine_receipt_returned", false) and not run.has_relic("life_seed"):
					options.append(_choice("medicine_reward", "领取伊芙的送药谢礼"))
			"grit":
				text = "巨狼在旧营地转了一圈，把一枚扣环推到你脚边。环上刻着“舒远”。\n“他的气味到这儿就淡了。你见过他吗？”"
				if run.data.tiles[run.actor(visitor).position].site != "track":
					text = "砾牙用鼻尖碰了碰带在身边的扣环。\n“舒远。旧营地那边还能闻到一点。这里没有。”"
				if run.data.story.grit.result != "E0":
					text = "砾牙把扣环拢到爪边。环在石子上轻轻碰了一声。\n“舒远的事，我记着。”"
				_learn(visitor, "grit_name")
				_learn(visitor, "grit_ring")
				if run.data.tiles[run.actor(visitor).position].site == "track":
					_learn(visitor, "grave_mark")
				options.append(_choice("share_food", "交付一份旅途干粮，询问是否同行", _has(visitor, "trail_food"), "需要个人持有旅途干粮；没有每日强制口粮"))
				var proof = _has(visitor, "Q-G") and _knows(visitor, "grave_mark") and _knows(visitor, "grit_ring")
				options.append(_choice("new_path", "核实记录后，承认死讯并邀请一条新路", proof, "需诊疗摘录、墓记与刻名扣环相互印证"))
				options.append(_choice("stay", "核实记录后，尊重暂时守候的意愿", proof, "需完整证据"))
				options.append(_choice("uncertain", "证据不足，不制造确定的答案", not proof, "已有完整证据时应如实面对"))
			"ember":
				text = "弥烬横过一步，挡住旧清障设备，手停在燧石上。\n“又有人拿着地图来拆东西？三年前我也信过图上的‘废弃’二字，结果烧了别人还在用的棚子。说吧，谁让你来的？”"
				if flags.get("invite_ember", false):
					text = "弥烬把燧石收回袋里。\n“这回先说看到的事。哪块林子还在，哪块过了火，我照实写。”"
				options.append(_choice("explain", "出示实际持有的测绘副本或登记回执，说明来意", _has(visitor, "Q-T") or _has(visitor, "Q-TR"), "凭据在异地时不能遥取"))
				var can_deploy = false
				for ally_id in run.same_cell(npc.position, true):
					if run.actor(ally_id).ap >= Catalog.BATTLE_AP:
						can_deploy = true
						break
				var duel_reason = "弥烬已经同行。" if npc.joined else "至少一名同地队员需要 %d 精力 才能参战。" % Catalog.BATTLE_AP
				options.append(_choice("duel", "普通交战：承担重伤与远征失败风险", not npc.joined and can_deploy, duel_reason))
				if flags.get("duel_won_ember", false):
					flags["invite_ember"] = true
				options.append(_choice("preserve", "报告亲历的解除危险与保林结果", _has_conservation_report(visitor), "需亲历森林遭遇胜利，林地实际保留且未燃烧"))
				options.append(_choice("admit", "如实承认已经观察到的火场损失", _has_fire_report(visitor), "需有真实、已知的火场代价"))
				options.append(_choice("falsify", "明知损失，仍要求不写入报告", _has_fire_report(visitor), "不能凭空假设发生过火灾"))
			"tide":
				text = "澄汐蹲在干渠边，用指节敲了敲石壁上的刻度。\n“老师写‘可能是季节变化’。你看，这一道比他记得高。台下石匣是放拓片的，背面那道槽存维护页。先对水位，再查水去了哪儿。”"
				if run.data.tiles[run.actor(visitor).position].site != "water":
					text = "澄汐用两根手指比出刻度间的距离。\n“就差这么一截，记下来却是两回事。要弄清楚，还得回水文台对刻度。”"
				options.append(_choice("water_draft", "借取她实际持有的旧水文稿", _has("tide", "Q-WA"), "原稿已交给实际持有人"))
				var at_water = run.data.tiles[run.actor(visitor).position].site == "water"
				options.append(_choice("water_observe", "观察现场石壁与流向", at_water, "需实际到水文台"))
				options.append(_choice("water_rubbing", "调查石匣，取得旧水位拓片 · 1 精力", at_water and can_investigate and not flags.get("taken_Q-WB", false), "原件需仍在现场，且需要 1 精力"))
				options.append(_choice("water_maintenance", "调查背侧档案槽，取得维护页 · 1 精力", at_water and can_investigate and not flags.get("taken_Q-WC", false), "原件需仍在现场，且需要 1 精力"))
				var observed = _knows(visitor, "water_wall") and _knows(visitor, "water_rubbing") and (_has(visitor, "Q-WA") or visitor == "tide" or _knows(visitor, "water_draft"))
				options.append(_choice("annotate", "保留原稿，加注真实观测差异", observed, "需现场观测并核对旧稿"))
				options.append(_choice("limited", "只写可证明的事实，不推断动机", observed, "需实际完成核对"))
				options.append(_choice("forge", "要求删去不利数据或伪造结论", observed, "需实际完成核对"))
				if at_water and _knows(visitor, "water_wall") and not flags.get("taken_Q-GAUGE", false):
					options.append(_choice("repair_gauge", "按石壁刻度修复水位标尺"))
				if _has(visitor, "Q-GAUGE"):
					options.append(_choice("return_gauge", "交还修好的水位标尺"))
		if not npc.joined:
			options.append(_choice("join", "邀请同行；不额外消耗精力", flags.get("invite_" + subject, false), "先满足角色清楚说明的同行条件"))
			options.append(_choice("decline", "这次不同行，但保留已经完成的帮助"))
			options.append(_choice("later", "暂缓决定，之后再来"))
		else:
			options.append(_choice("share", "同地交换亲历见闻与记录"))
		if run.data.story[subject].result != "E0":
			text += "\n\n" + PERSONAL[subject].get(str(run.data.story[subject].result), "")
	else:
		if EncounterStory.BEATS.has(subject):
			flags["intro_seen_" + subject] = true
		match subject:
			"inn":
				title = "陆衡 · 白栎旧驿站"
				text = "陆衡把药包挪开，腾出一角桌面让你摊开地图。\n“你问这里为什么还有灯？今晚还有药要送。档案说十七户早搬走了，你也看见了，灯底下还有人在等。”"
				options.append(_choice("read", "平静阅读摘要，请他给出有来源的摘录"))
				options.append(_choice("accuse", "直接质问为何签下不实摘要"))
				options.append(_choice("statement", "当面请他解释签署过程", not flags.get("accused_lu", false) and (_knows(visitor, "resident_alive") or _has(visitor, "Q-B")), "需要有矛盾线索；强硬质问后他可拒绝额外说明"))
				options.append(_choice("diagnosis", "询问舒远，取得有来源的诊疗/安葬摘录", _knows(visitor, "grit_name"), "先实际听到舒远的名字"))
			"home":
				title = "乔禾 · 林边仍有人居住的家"
				text = "乔禾推开门，把挡路的药篮提到一旁。\n“伊芙的药送我这儿。你若是来问旧驿站那班船，我也记得。我们一家等到灯灭，都没上船。要把这话写下来，先告诉我会给谁看。”"
				_learn(visitor, "resident_alive")
				_learn(visitor, "home_route")
				options.append(_choice("public", "说明仅本户、不代迁离，按她授权范围署名", not flags.get("taken_Q-C", false), "本户证词已交给真实接收者"))
				options.append(_choice("sealed", "请求仅供站内核查的密封证词", not flags.get("taken_Q-C", false), "证词已有明确范围，不复制另一份"))
				options.append(_choice("oral", "不留文字，只听她讲亲历的事"))
				options.append(_choice("terms", "记录她授权的通行、送药与留居条款"))
				options.append(_choice("deliver_letter", "尊重她现在阅读，将旧信真正交给她", _has(visitor, "Q-L"), "原信需在当前角色包中"))
				options.append(_choice("seal_letter", "尊重她要求封存，将原信带回洛恩", _has(visitor, "Q-L"), "原信需实际在场"))
				options.append(_choice("open_letter", "未经许可拆阅旧信（留下事实）", _has(visitor, "Q-L"), "原信需实际在场"))
				options.append(_choice("deliver_medicine", "按真实清单交付药箱，取得唯一接收回执", _has(visitor, "Q-M"), "药箱需在当前角色包中"))
			"record":
				title = "旧调度柜 · 同一批次的两种记录"
				text = "柜里的接应回执写着：告知已送达，接应未实施。它与摘要属于同一批次，不能证明今天居民的意愿。"
				_learn(visitor, "record_seen")
				options.append(_choice("take_record", "实际调查并取出原始回执 · 1 精力", can_investigate and not flags.get("taken_Q-B", false), "原件需仍在现场，且需要 1 精力"))
			"water":
				title = "水文台 · 现场与档案槽"
				text = "即使澄汐已经离开，刻度、石匣与背侧档案槽仍在原处。任何角色都可以调查，不需要先掌握水魔法。"
				options.append(_choice("water_observe", "观察现场石壁与流向"))
				options.append(_choice("water_rubbing", "调查石匣，取得旧水位拓片 · 1 精力", can_investigate and not flags.get("taken_Q-WB", false), "原件需仍在现场，且需要 1 精力"))
				options.append(_choice("water_maintenance", "调查背侧档案槽，取得维护页 · 1 精力", can_investigate and not flags.get("taken_Q-WC", false), "原件需仍在现场，且需要 1 精力"))
				if _knows(visitor, "water_wall") and not flags.get("taken_Q-GAUGE", false):
					options.append(_choice("repair_gauge", "按石壁刻度修复水位标尺"))
			"track":
				title = "旧兽径营地 · 墓记"
				text = "墓记刻着舒远的名字与一年前的日期。需与诊疗摘录及砾牙的刻名扣环核对，才能形成有来源的结论。"
				_learn(visitor, "grave_mark")
				options.append(_choice("observe", "记下亲眼看到的墓记"))
			"forest":
				title = "林缘捕网 · 使用界标"
				text = "界标和仍有人使用的林路留在原处，不能因为岑枝同行离开就从地图上消失。"
				_learn(visitor, "cen_boundary")
				options.append(_choice("observe", "记下真实林地边界"))
			"exit":
				title = "归航站 · 常态接应，没有末班倒计时"
				text = "值守者把码头的灯拨亮，给你留出一块干净桌面。\n“从断桥走到这儿，辛苦了。委托副本可以交给我，路上记下的事也可以一起说。你要是还等人，船会照常往返。”"
				options.append(_choice("register", "交付本次测绘副本，领取唯一登记回执", _has(visitor, "Q-T") and not run.data.submitted.has("Q-T"), "副本需实际持有，普通登记不算旧案证据"))
				options.append(_choice("roads", "只提交亲历路况，不替历史下结论"))
				options.append(_choice("report_oral", "提供亲历口述，作为待查线索", _knows(visitor, "resident_alive") or _knows(visitor, "record_seen") or _knows(visitor, "summary_seen"), "需要实际获得有来源的线索"))
				var has_history = _has(visitor, "Q-A") or _has(visitor, "Q-B") or _has(visitor, "Q-C") or _has(visitor, "Q-D")
				options.append(_choice("submit", "按证词许可递交当前实际持有的历史材料", has_history, "异地原件不能从共享地图递交"))
				options.append(_choice("submit_terms", "提交居民条款与亲历路线", _has(visitor, "Q-TERMS") and _knows(visitor, "home_route"), "需要实际条款和亲历路线，或同地交换见闻"))
				options.append(_choice("submit_boundary", "提交实际持有的林地边界意见", _has(visitor, "Q-BOUND"), "需持有边界意见原件"))
				options.append(_choice("keep", "明确保留关键材料，随实际持有人带走", _has(visitor, "Q-B") or _has(visitor, "Q-C"), "关键原件需实际持有"))
				options.append(_choice("wait", "先登记位置，我还要等人"))
				options.append(_choice("depart", "查看归航名单，再决定是否结束", run.actor("hero").position == run.data.exit and run.actor("hero").hp > 0, "主角需可行动并到站"))
	if run.data.story.has(subject) and run.data.story[subject].result != "E0":
		var terminal_choices = {"cen": ["boundary", "straight", "report"], "grit": ["new_path", "stay", "uncertain"], "ember": ["preserve", "admit", "falsify"], "tide": ["annotate", "limited", "forge"]}
		for option in options:
			if option.id in terminal_choices.get(subject, []):
				option.enabled = false
				option.reason = "本局已作出明确选择，保留实际结果。"
	options.append(_choice("leave", "我还想回去看看"))
	if run.data.tiles[run.actor(visitor).position].terrain == "scorched":
		text += "\n\n灰烬覆盖了原来的林地。这里的地点和人物仍在，但新鲜药草已不能照旧采集。"
	return {"ok": true, "subject": subject, "title": title, "text": text, "options": options}

func choose(visitor: String, subject: String, option_id: String) -> Dictionary:
	var result = _choose(visitor, subject, option_id)
	if result.ok:
		if not run.data.has("choices"):
			run.data.choices = []
		run.data.choices.append({"day": run.data.day, "visitor": visitor, "subject": subject, "option": option_id})
	return result

func _choose(visitor: String, subject: String, option_id: String) -> Dictionary:
	var d = dialogue(visitor, subject)
	if not d.ok:
		return d
	var selected = {}
	for option in d.options:
		if option.id == option_id:
			selected = option
	if selected.is_empty() or not selected.enabled:
		return {"ok": false, "message": str(selected.get("reason", "当前没有这个选项。"))}
	if option_id in ["leave", "later", "decline", "join", "share", "rescue", "rescue_skill"]:
		return _common(visitor, subject, option_id)
	if option_id == "repair_gauge":
		_grant(visitor, "Q-GAUGE")
		var repaired = "你按石壁上的旧刻度扶直标尺，把松脱的底座扣好。带回给澄汐，她可以核对修复结果。"
		run.note(repaired)
		run.changed.emit()
		return {"ok": true, "response": repaired}
	var response = ""
	var flags = run.data.flags
	match subject:
		"cen":
			match option_id:
				"help":
					flags["cen_helped"] = true
					flags["invite_cen"] = run.data.story.cen.result != "E2"
					response = "信鸟掠过你们的头顶，抖落几片叶子。" + ("\n“多谢。你还要往前走？要是缺个认路的人，可以叫上我。”" if flags.invite_cen else "\n“多谢你搭手。林路的事我还是那个意思，咱们各走各的吧。”")
				"boundary":
					_grant(visitor, "Q-BOUND")
					_learn(visitor, "boundary_terms")
					response = "岑枝听你把林地边界说完，点了点头。\n“这份意见捎给归航站吧。要是他们收下了，回来跟我说一声。”"
				"straight":
					_result("cen", "E2")
					response = "岑枝把自己的图折起来。\n“你这条直线从人家的药草坡上过。再往前的林路，我就不给你画了。”"
				"report":
					_result("cen", "E1")
					response = "“他们收下了？好。”岑枝重新摊开自己的图，在林路边补了一道短线。"
		"lorne":
			match option_id:
				"letter":
					_hand_over("lorne", visitor, "Q-L")
					_learn(visitor, "letter_task")
					response = "原信交到真实代送者手中。乔禾在林边家；是否读信，由她本人决定。"
				"letter_report":
					if _knows(visitor, "letter_opened"):
						_result("lorne", "E3")
					elif _knows(visitor, "letter_delivered"):
						_result("lorne", "E1")
					else:
						_hand_over(visitor, "lorne", "Q-L")
						_result("lorne", "E2")
					response = "洛恩听到了真实结果，没有替缺席的人签收或拆阅。"
		"eve":
			match option_id:
				"medicine":
					_hand_over("eve", visitor, "Q-M")
					_learn(visitor, "medicine_task")
					response = "伊芙把药箱递给你，清单压在提绳下面。\n“抬稳些。到了乔禾家，先把清单给她看。”"
				"emergency", "conceal":
					flags["medicine_split"] = true
					flags["medicine_concealed"] = option_id == "conceal"
					flags["medicine_authorized"] = option_id == "emergency"
					run.actor(visitor).inventory.salve = int(run.actor(visitor).inventory.get("salve", 0)) + 1
					response = ("“急用就先拿一份。等等，我把缺的这瓶写上，免得乔禾对不上。”\n伊芙改过清单，才把箱盖合上。" if option_id == "emergency" else "你把一瓶药收进自己的包里。清单上，那一格还是满的。")
				"medicine_report":
					_consume(visitor, "Q-R")
					flags["medicine_receipt_returned"] = true
					_result("eve", "E3" if flags.get("medicine_concealed", false) else "E2" if flags.get("medicine_authorized", false) else "E1")
					flags["invite_eve"] = run.data.story.eve.result != "E3"
					response = "伊芙把乔禾签的回执贴着清单，顺着两张纸逐行核对。"
					run.grant_relic("life_seed", visitor, run.actor(visitor).position, "eve", response)
				"medicine_reward":
					response = "伊芙取出先前核对过的签收回执，把药箱转向你。"
					run.grant_relic("life_seed", visitor, run.actor(visitor).position, "eve", response)
		"grit":
			match option_id:
				"share_food":
					_consume(visitor, "trail_food")
					flags["invite_grit"] = true
					response = "砾牙低头吃完你递来的干粮，往旁边挪了一步。\n“还走吗？我可以跟你一程。”"
				"new_path", "stay", "uncertain":
					_result("grit", "E1" if option_id == "new_path" else "E2" if option_id == "stay" else "E3")
					flags["invite_grit"] = true
					response = PERSONAL.grit[run.data.story.grit.result]
		"ember":
			match option_id:
				"explain":
					flags["invite_ember"] = true
					response = "弥烬读过你递到眼前的凭据，手从燧石上移开。\n“是这趟测绘的登记。看来我拦错人了。接下来的路，要我搭把手吗？”"
				"duel":
					run.data.pending_battle = {"position": run.actor(visitor).position, "origin": run.actor(visitor).position, "ambush": false, "movers": [], "npc": "ember"}
					flags["duel_seen_ember"] = true
					return {"ok": true, "battle": true}
				"preserve", "admit", "falsify":
					_result("ember", "E1" if option_id == "preserve" else "E2" if option_id == "admit" else "E3")
					response = PERSONAL.ember[run.data.story.ember.result]
		"tide":
			match option_id:
				"return_gauge":
					_consume(visitor, "Q-GAUGE")
					response = "澄汐把标尺与原来的拓印并排放下，逐一对过记号。"
					run.grant_relic("rain_bell", visitor, run.actor(visitor).position, "tide", response)
				"water_draft":
					_hand_over("tide", visitor, "Q-WA")
					_learn(visitor, "water_draft")
					response = "澄汐把旧稿递给你，指了一下末尾的批注。\n“‘可能’两个字也留着。我还不知道老师看没看过维护页。”"
				"water_observe":
					_learn(visitor, "water_wall")
					response = "石壁的水痕停在另一道刻度上。你先记下这一笔，成因那一栏暂且空着。"
				"water_rubbing", "water_maintenance":
					var check = run._map_action(visitor, 1)
					if not check.ok:
						return check
					run.actor(visitor).ap -= 1
					var item = "Q-WB" if option_id == "water_rubbing" else "Q-WC"
					_grant(visitor, item)
					_learn(visitor, "water_rubbing" if item == "Q-WB" else "water_maintenance")
					response = ("你从背槽抽出维护页。同批记录里有开闸日期，还有一支指向稳流支路的箭头。" if item == "Q-WC" else "你从石匣里取出旧水位拓片。墨线还能辨认，正好带回去对旧稿。")
				"annotate", "limited", "forge":
					_result("tide", "E1" if option_id == "annotate" else "E2" if option_id == "limited" else "E3")
					flags["invite_tide"] = option_id != "forge"
					response = PERSONAL.tide[run.data.story.tide.result]
		"inn":
			match option_id:
				"read":
					var received = _grant(visitor, "Q-A")
					_learn(visitor, "summary_seen")
					flags["investigated"] = true
					response = "你读到同一批次十七户迁离完成的记载。" + ("取得一份有来源的摘录。" if received else "摘录已在实际持有人处或已交站，没有再复制一份。") + "原始接应回执可能仍在旧调度柜。"
				"accuse":
					flags["accused_lu"] = true
					flags["investigated"] = true
					response = "“我不会写下无法保证的承诺。”陆衡拒绝额外署名；公开摘要和柜中原始回执没有因此消失。"
				"statement":
					_grant(visitor, "Q-D")
					response = "陆衡说明签署过程：告知办结被归档为迁离完成，他后来没有正式追回。说明可补充，不替代原始回执与居民证词。"
				"diagnosis":
					_grant(visitor, "Q-G")
					response = "诊疗簿与安葬摘录指向一年前去世的舒远。还需到旧兽径营地核对墓记与刻名扣环。"
		"home":
			flags["investigated"] = true
			match option_id:
				"public", "sealed":
					flags["testimony_scope"] = option_id
					_grant(visitor, "Q-C")
					response = "乔禾在本户的证词末尾签了字。\n“这只写我们一家。邻居自己开口，家信也归家信。" + ("这一页可以公开。”" if option_id == "public" else "请封好，只交给站里核查的人看。”")
				"oral":
					_learn(visitor, "resident_oral")
					response = "乔禾指向窗边的长凳。\n“那晚我娘就坐这儿等船。天快亮的时候，我把她劝回屋了。”\n你听她讲完，没有请她签字。"
				"terms":
					_grant(visitor, "Q-TERMS")
					response = "乔禾在纸上按住三行字，把它推到你面前。\n“房子留着，送药的路留着。要动林路，先来跟住在这儿的人商量。”"
				"deliver_letter":
					_consume(visitor, "Q-L")
					flags["letter_location"] = "home"
					_learn(visitor, "letter_delivered")
					if flags.get("letter_opened", false):
						_learn(visitor, "letter_opened")
					response = "乔禾接过信，用指腹抹平信封的一角。\n“是我姐姐的字。我想现在看。”她把信留在自己手中。"
				"seal_letter":
					_learn(visitor, "letter_sealed")
					response = "乔禾看了片刻，把手收了回去。\n“我今天还没准备好。请把原信带回给洛恩，托他替我封好。”"
				"open_letter":
					flags["letter_opened"] = true
					_learn(visitor, "letter_opened")
					response = "封口在你手中裂开。信还可以送到，封口已经合不回去了。"
				"deliver_medicine":
					_consume(visitor, "Q-M")
					_grant(visitor, "Q-R")
					flags["medicine_delivered"] = true
					_learn(visitor, "medicine_delivered")
					response = "乔禾照着清单点完药瓶，签好回执递给你。\n“劳你交给伊芙。她看了，就知道我收到多少。”"
		"record":
			var check = run._map_action(visitor, 1)
			if not check.ok:
				return check
			run.actor(visitor).ap -= 1
			_grant(visitor, "Q-B")
			flags["investigated"] = true
			response = "原始接应回执进入执行者个人背包。可以保留、同格交接，或实际送至归航站。"
		"water":
			if option_id == "water_observe":
				_learn(visitor, "water_wall")
				response = "记录了现场水位差异，不直接推断老师动机。"
			else:
				var check = run._map_action(visitor, 1)
				if not check.ok:
					return check
				run.actor(visitor).ap -= 1
				var item = "Q-WB" if option_id == "water_rubbing" else "Q-WC"
				_grant(visitor, item)
				_learn(visitor, "water_rubbing" if item == "Q-WB" else "water_maintenance")
				response = "实际取出了" + DOCUMENTS[item] + "，原件进入执行者个人背包。"
		"track", "forest":
			response = "亲眼观察的记录已写入本角色见闻。"
		"exit":
			match option_id:
				"register":
					_consume(visitor, "Q-T")
					run.data.submitted["Q-T"] = {"by": visitor, "day": run.data.day}
					_grant(visitor, "Q-TR")
					response = "副本已由站方保管，唯一登记回执只签给实际交件者。登记不结束远征，也不自动证明旧案。"
				"roads":
					flags["roads_submitted"] = true
					response = "新路况已登记，历史与人口空白没有因此自动解决。"
				"report_oral":
					flags["oral_submitted"] = true
					response = "站方接收有来源的口述作为待查线索，没有把异地原件写成已经收件。"
				"submit":
					var submitted: Array[String] = []
					for item in ["Q-A", "Q-B", "Q-C", "Q-D"]:
						if _consume(visitor, item):
							run.data.submitted[item] = {"by": visitor, "day": run.data.day, "scope": flags.get("testimony_scope", "") if item == "Q-C" else "record"}
							submitted.append(DOCUMENTS[item])
					if run.data.submitted.has_all(["Q-A", "Q-B", "Q-C"]):
						flags["verified_submission"] = run.data.submitted["Q-C"].scope
					response = "站方实际收到：" + "、".join(submitted) + "。材料按真实授权范围处理；本航线核查不等于全大陆已定案。"
				"submit_terms":
					_consume(visitor, "Q-TERMS")
					flags["terms_submitted"] = true
					response = "居民留居、通行和送药条款已受理；没有自动搬迁。"
				"submit_boundary":
					_consume(visitor, "Q-BOUND")
					flags["boundary_submitted"] = true
					_learn(visitor, "boundary_submitted")
					response = "林地边界意见已真实到站。岑枝仍需在场听见或等待实际回告。"
				"keep":
					flags["keep_materials"] = true
					response = "你明确选择保留关键材料。结局只有在原件确实随到站撤离者离开时，才记为带走。"
				"wait":
					response = "值守者记下位置，接应随时可用。你可以继续操作远处同伴、返回探索或之后再确认。"
				"depart":
					return {"ok": true, "extract_requested": true}
	run.note(response)
	run.changed.emit()
	return {"ok": true, "response": response}

func _common(visitor: String, subject: String, option: String) -> Dictionary:
	if option == "leave":
		return {"ok": true, "close": true}
	if option == "rescue":
		return {"ok": true, "rescue": subject}
	if option == "rescue_skill":
		return {"ok": true, "heal_dialog": subject}
	if option == "join":
		var previous = run.data.story[subject].relation
		var result = run.join_companion(subject, visitor)
		if result.ok:
			result.response = ("你改变了之前的决定，" if previous in ["declined", "later"] else "") + run.actor(subject).name + "确认与你同行。"
		return result
	if option in ["decline", "later"]:
		run.data.story[subject].relation = "declined" if option == "decline" else "later"
		var response = "你说明接下来想独自走。%s点了点头，留在原地。" % run.actor(subject).name
		if option == "later":
			response = "你们约好各自再想一想。若沿路折返，还能到这里继续这场谈话。"
		return {"ok": true, "response": response}
	if option == "share":
		var facts = {}
		for id in run.same_cell(run.actor(visitor).position, true):
			for fact in run.data.knowledge.get(id, {}):
				var value = run.data.knowledge[id][fact]
				if value is Array:
					if not facts.has(fact):
						facts[fact] = []
					for entry in value:
						if entry not in facts[fact]:
							facts[fact].append(entry)
				else:
					facts[fact] = value
		for fact in facts:
			for id in run.same_cell(run.actor(visitor).position, true):
				if not run.data.knowledge.has(id):
					run.data.knowledge[id] = {}
				run.data.knowledge[id][fact] = facts[fact].duplicate() if facts[fact] is Array else facts[fact]
		return {"ok": true, "response": "同地角色当面交换了亲历见闻，原件仍在各自背包，没有复制。"}
	return {"ok": false, "message": "未知交谈动作。"}

func _has_conservation_report(visitor: String) -> bool:
	for position in run.data.knowledge.get(visitor, {}).get("victories", []):
		var t = run.data.tiles[position]
		if t.terrain == "forest" and not t.burning and int(t.fuel) == 3:
			return true
	return false

func _has_fire_report(visitor: String) -> bool:
	for position in run.data.knowledge.get(visitor, {}).get("ignitions", []):
		var t = run.data.tiles[position]
		if (t.burning or t.terrain == "scorched" or int(t.fuel) < 3) and run.data.flags.get("player_ignitions", {}).has(position):
			return true
	return false

func character_ending(id: String) -> Dictionary:
	var a = run.actor(id)
	var s = run.data.story[id]
	var result = str(s.result)
	if id == "ember" and not a.joined and a.hp <= 0 and run.data.flags.get("duel_seen_ember", false):
		result = "E4"
	var prefix = {"cen": "CEN", "lorne": "LOR", "eve": "EVE", "grit": "GRIT", "ember": "EMB", "tide": "TIDE"}[id]
	var personal = str(PERSONAL[id].get(result, PERSONAL[id].E0))
	if not s.met and not a.joined:
		return {"code": prefix + "-UNMET", "name": "未曾相遇", "text": "另一条路上的旅人没有与你相遇。你的记录里，还没有这个名字。", "personal": result}
	if not a.joined:
		return {"code": prefix + "-" + result + "-LOCAL", "name": a.name, "text": personal + " 你们没有同行，这次相遇仍各自留下了记忆。", "personal": result}
	if run.data.status == "failed":
		return {"code": prefix + "-INTERRUPTED", "name": a.name, "text": personal + " 远征中断，记录停在实际地点 " + str(a.position) + "，不虚构成功归航。", "personal": result}
	if a.position == run.data.exit:
		return {"code": prefix + "-EXTRACTED", "name": a.name, "text": personal + " 这一次，" + a.name + "确实在归航站名单上。", "personal": result}
	var injured = a.hp <= 0
	var resolved = result != "E0"
	var code = prefix + "-U-" + ("I" if injured else "H") + "-" + ("R" if resolved else "O")
	var variant = (2 if injured else 0) + (0 if resolved else 1)
	var texts = {
		"cen": ["岑枝还留在未走完的路上。边界的答复她已经听过，那份认可或分歧不会因归航名单而消失；此刻她仍能行动，却尚未到站。","岑枝还在等林地意见的回音。未回答的承诺没有被写进地图，下一段路也还没有走完。","伤势让岑枝没能站起。关于边界的答案她已经听过，现在却还需要同伴的援手。","林口那个未回答的问题仍在，而岑枝已经无法自己起身。她最后等到的还不是归航的消息。"],
		"lorne": ["旧信的去向已有交代，信使自己的返程却没有完成。投递的结果与他所在的位置，成了记录里两件不同的事。","投递约定尚未结束。洛恩记着最后一个亲耳听到的地址，仍留在这段没有走完的路上。","洛恩已听到签收、封存或私拆的真实结果，伤势却让他无法继续。信件的终点没有替信使完成归途。","未完成的投递与待救的伤势一起留下。洛恩没有等到最后的回告，也还没有到达归航站。"],
		"eve": ["伊芙核对过的清单已有明确结果，自己的归途却未完成。药物是否齐备、缺口是否事先说明，都仍记在原来的那一页。","回执或回告还没有来到面前。伊芙只记得最后一次交接，药箱簿上的那栏仍空着。","清单已有答复，医者自己却在此地重伤待援。她曾经为别人整理药物，此刻也需要一双真正来到身边的手。","药物的去向尚未核对，伊芙又已无法自行行动。最后的交接与眼前的伤势，分别留在两行未完成的记录里。"],
		"grit": ["砾牙对旧主人、新路或未证实的线索已有回应，却仍留在这片边境。归航没有替他把每一步选择都走完。","砾牙还记着旧物的气味。扣环上的名字尚未形成完整的答案，他的返程也没有完成。","砾牙记得已经说清的答案，重伤的四肢却无法支撑他离开。新路或守候的愿望，此刻都还停在脚步之前。","旧物还唤起尚未核实的记忆，伤势又让砾牙无法起身。他等着的答案与援手，都还没有来到。"],
		"ember": ["保林、承认损失或拒签假报，都已在弥烬的清障记录中留下后果。那一页有了答案，他自己却还没有到站。","弥烬还没能为这次清障写下结论。争论与危险停在未完成处，他也仍留在这片边境。","弥烬已作出的判断没有改变，伤势却让他无法继续行动。他的名字仍在远征队名册上，归航一栏尚未勾选。","尚未完成的合作与伤势一同留下。弥烬已经与你们同行过，此刻还在等待真正来到身边的救援。"],
		"tide": ["澄汐已经给出有界限的结论。文书有它自己的去向，而她本人的归途仍未完成。","未核对的一行保持空白。澄汐记着最后看过的刻度，记录和返程都还没有闭合。","澄汐已经分清哪些刻度可核实、哪些结论应当保留，伤势却不是知识可以治好的。她仍在等待同伴。","未闭合的数据与伤势留在同一个地点。水文稿还有空行，澄汐也还没有走到归航的灯下。"],
	}
	var item_notes: Array[String] = []
	for item in a.inventory:
		if item in DOCUMENTS and int(a.inventory[item]) > 0:
			item_notes.append(DOCUMENTS[item])
	var text = texts[id][variant] + "\n" + personal + "\n最后已知地点：" + str(a.position) + "。归航的记录只到这一刻，之后的消息尚未传来。"
	if not item_notes.is_empty():
		text += " 原件留在其处：" + "、".join(item_notes) + "。"
	return {"code": code, "name": a.name, "text": text, "personal": result}

func main_ending() -> Dictionary:
	var flags = run.data.flags
	if run.data.status == "failed":
		return {"code": "FAIL", "title": "停在途中", "text": str(flags.get("failure_reason", "远征中断。")) + " 已送达材料仍由站方保管，其余留在实际持有人处。"}
	var code = "CH-00"
	if flags.get("verified_submission", "") == "public":
		code = "CH-03"
	elif flags.get("verified_submission", "") == "sealed":
		code = "CH-04"
	elif flags.get("terms_submitted", false):
		code = "CH-05"
	elif flags.get("keep_materials", false) and _key_material_extracted() and not run.data.submitted.has("Q-B") and not run.data.submitted.has("Q-C"):
		code = "CH-06"
	elif flags.get("roads_submitted", false):
		code = "CH-01"
	elif flags.get("investigated", false) or flags.get("oral_submitted", false) or _any_history_submitted():
		code = "CH-02"
	var endings = {
		"CH-00": ["只走归途", "归航站的灯映在水面上。你完成这次过境，旧驿站的事仍藏在另一条路里。"],
		"CH-01": ["新路、旧空白", "归航站收到新路况，人口与历史空白尚未因此改好。"],
		"CH-02": ["一条待查的线索", "已有来源线索送入站内，等待后续核查。" if flags.get("oral_submitted", false) or _any_history_submitted() else "调查确实发生，但关键材料尚未送达。记录停在途中，不能替站方虚构收件。"],
		"CH-03": ["名字重新写上地图", "摘要、原始回执与本户授权公开证词相互印证。值守者把已确认住处记入本航线临时图，受理旧档核查；没有替其他十六户签字或宣布全大陆定案。"],
		"CH-04": ["密封的证词", "核验材料按许可密封收件，私人姓名未被公开；必要接应地点有限登记，核查仍将继续。"],
		"CH-05": ["留在这里的权利", "居民留居与通行、送药条款已受理。记录真实意愿不等于自动迁移，也不授权无限清障。"],
		"CH-06": ["没有交出去的那一页", "关键原件确实随到站撤离者带走，没有交给站方。站方只知道此前实际收到的路况或口述。"],
	}
	return {"code": code, "title": endings[code][0], "text": endings[code][1] + (" 居民意愿也已记录。" if flags.get("terms_submitted", false) and code in ["CH-03", "CH-04"] else "")}

func _key_material_extracted() -> bool:
	for id in run.joined_ids():
		if run.actor(id).position == run.data.exit and (_has(id, "Q-B") or _has(id, "Q-C")):
			return true
	return false

func _any_history_submitted() -> bool:
	for item in ["Q-A", "Q-B", "Q-C", "Q-D"]:
		if run.data.submitted.has(item):
			return true
	return false
