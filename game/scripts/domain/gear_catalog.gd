extends RefCounted

const DATA = {
	"ember_warden_weapon": {"name": "截焰林钩", "slot": "weapon", "set_id": "ember_warden", "stats": {"attack": 4}, "effect": "行动开始时战场正在燃烧，你这次主动打出的火直接伤害提高 8%。灼烧和额外触发的伤害照旧。", "story": "林工用钩刃拖开着火的枝条，让火舌离避难队伍远一些。刃背刻的是风向记号，不是神名。", "source": "森林藏物点；林缘商人武器库存。"},
	"ember_warden_armor": {"name": "炭衬守夜衣", "slot": "armor", "set_id": "ember_warden", "stats": {"defense": 3}, "effect": "你受到的战场灼烧伤害降低 15%。", "story": "衣襟里缝着可替换的炭毡，旧针脚来自不同村落。它能缓一缓灼痛，却从未许诺穿衣人不会烧伤。", "source": "森林藏物点；林缘商人护甲库存。"},
	"ember_warden_accessory": {"name": "封口余炭筒", "slot": "accessory", "set_id": "ember_warden", "stats": {"speed": 8}, "effect": "主动打出的火直接伤害击倒敌人后，你回复 3 点魔力。每次行动只算一次，每场最多两次。灼烧或额外触发的伤害击倒敌人时不算。", "story": "守林人把火种装进能锁住的筒里，才肯走进难民歇脚的棚屋。筒底仍压着一张尚未送达的巡林路线。", "source": "森林藏物点；林缘商人饰品库存。"},
	"tide_weaver_weapon": {"name": "分汊导流杖", "slot": "weapon", "set_id": "tide_weaver", "stats": {"attack": 4}, "effect": "行动开始时战场湿润，你这次主动打出的水直接伤害提高 8%。", "story": "杖首的分汊原是疏通水槽的工具。使用它的人相信，让水走对地方比把浪卷得更高更重要。", "source": "沼泽藏物点；渡口商人武器库存。"},
	"tide_weaver_armor": {"name": "浸线短披", "slot": "armor", "set_id": "tide_weaver", "stats": {"defense": 3}, "effect": "攻击开始时战场湿润，你受到的火直接伤害降低 10%。灼烧伤害照旧。", "story": "披衣缝线吸水后会变沉，穿戴者不得不放慢脚步。渡口账本把这份负担当作保住皮肤的交换。", "source": "沼泽藏物点；渡口商人护甲库存。"},
	"tide_weaver_accessory": {"name": "回潮结绳", "slot": "accessory", "set_id": "tide_weaver", "stats": {"speed": 8}, "effect": "在湿润的战场上防御后，你回复生命上限的 3%。每场最多两次。满血时不扣次数。", "story": "结绳原本用于标记水袋轮流领取的次序。最深的一道结留给仍未归队的人，没有人擅自解开。", "source": "沼泽藏物点；渡口商人饰品库存。"},
	"rime_path_weapon": {"name": "刻霜短镐", "slot": "weapon", "set_id": "rime_path", "stats": {"attack": 4}, "effect": "行动开始时战场有冰面，你这次主动打出的冰直接伤害提高 8%。", "story": "短镐的齿距来自挑夫辨认薄冰裂纹的经验。它先是保命工具，后来才被用来挡住追兵。", "source": "山地藏物点；山道商人武器库存。"},
	"rime_path_armor": {"name": "钉纹行霜袄", "slot": "armor", "set_id": "rime_path", "stats": {"defense": 3}, "effect": "当你将受到至少持续两次行动的迟缓时，持续时间缩短一次行动，至少保留一次。每场最多两次。同一次迟缓最多缩短一次，减速幅度照旧。", "story": "袄摆缀着细小配重，提醒穿衣人不要在湿滑处跨得太大。修补者仍在每件衣领写下“薄冰不可托命”。", "source": "山地藏物点；山道商人护甲库存。"},
	"rime_path_accessory": {"name": "霜纹记步扣", "slot": "accessory", "set_id": "rime_path", "stats": {"speed": 8}, "effect": "如果你打中的第一个目标在你出手前就已迟缓，你在这次行动结束后回复 2 点魔力。每场最多两次。", "story": "扣面一格一格刻着需要歇脚的间隔。一个信使将它留下，只说别把沉默当作前方安全。", "source": "湿地藏物点；山道商人饰品库存。"},
	"storm_conductor_weapon": {"name": "分流测杆", "slot": "weapon", "set_id": "storm_conductor", "stats": {"attack": 4}, "effect": "行动开始时战场湿润或导电，你这次主动打出的雷直接伤害提高 8%。两个条件都满足时也只加一次。", "story": "测杆上的刻度原用于记录旧塔导线的残余震颤。每个被划去的刻度都提醒学徒不要凭声音判断安全。", "source": "废墟藏物点；测绘商人武器库存。"},
	"storm_conductor_armor": {"name": "断环绝缘衣", "slot": "armor", "set_id": "storm_conductor", "stats": {"defense": 3}, "effect": "攻击开始时战场导电，你受到的雷直接伤害降低 20%。与其他装备和遗器共用减伤上限，战场本身的雷伤加成照旧。", "story": "衣上铜环故意没有闭合，边缘垫着厚树脂。旧说明最醒目的一行是“绝缘会磨损，勿把自己当避雷针”。", "source": "废墟藏物点；测绘商人护甲库存。"},
	"storm_conductor_accessory": {"name": "记闪小铃", "slot": "accessory", "set_id": "storm_conductor", "stats": {"speed": 8}, "effect": "主动打出雷直接伤害后，你额外获得 5 点能量。每场最多两次。能量满时不扣次数。", "story": "铃舌被布包住，只在掌中传来轻响。测绘员用它数两阵雷之间的间隙，避免催促同行人冒进。", "source": "湿地藏物点；测绘商人饰品库存。"},
	"gale_runner_weapon": {"name": "折羽引风刃", "slot": "weapon", "set_id": "gale_runner", "stats": {"attack": 4}, "effect": "防御后，全场接下来四次行动内，你下一次主动打出的风直接伤害提高 10%。每场最多准备两次，未用掉的效果不会刷新。", "story": "刃脊曾是一片可收起的风向板。信使宁愿等风转向，也不愿把同行的伤者留在路边。", "source": "平原藏物点；驿路商人武器库存。"},
	"gale_runner_armor": {"name": "夹信轻斗篷", "slot": "armor", "set_id": "gale_runner", "stats": {"defense": 3}, "effect": "攻击开始时战场有风障，你受到的远程直接伤害再降低 8%。风障本身另算，两项合用时受到原伤害的 82.8%。", "story": "斗篷内侧分成几个窄袋，让不同收信人的纸张不必挤在一起。空着的袋子仍留着名字，尚无回音。", "source": "平原藏物点；驿路商人护甲库存。"},
	"gale_runner_accessory": {"name": "晴野路哨", "slot": "accessory", "set_id": "gale_runner", "stats": {"speed": 8}, "effect": "每天第一次走进平原且能省精力时，你少花 1 点精力，最低花 1 点。", "story": "路哨没有召风的能力，只能让远处同行者听见短促回应。磨亮的吹口来自很多个没能准时抵达的傍晚。", "source": "平原藏物点；驿路商人饰品库存。"},
	"stone_vow_weapon": {"name": "验层短锤", "slot": "weapon", "set_id": "stone_vow", "stats": {"attack": 4}, "effect": "在山地战斗时，你主动打出的土直接伤害提高 10%。", "story": "锤柄刻着矿工辨认空层时的敲击次序。后来的持有者仍先听回声，再决定是否让同行人靠近。", "source": "山地藏物点；矿道商人武器库存。"},
	"stone_vow_armor": {"name": "承梁铆甲", "slot": "armor", "set_id": "stone_vow", "stats": {"defense": 3}, "effect": "攻击开始时你已在防御，你受到的直接伤害再降低 8%。灼烧和额外触发的伤害照旧。", "story": "铆甲沿用了旧矿架的受力线，却比木梁轻得多。内衬写着同伴的警语：能撑一时，不是能撑永远。", "source": "山地藏物点；矿道商人护甲库存。"},
	"stone_vow_accessory": {"name": "回响铅垂", "slot": "accessory", "set_id": "stone_vow", "stats": {"speed": 8}, "effect": "普通攻击、施放技能、使出终结技或防御后，若你行动前已有护盾且还活着，回复 2 点魔力。每场最多两次。", "story": "铅垂被磨得很短，放在掌心也能辨认微小摇摆。矿工用它确认支架是否还值得信任，而不是测量神意。", "source": "山地藏物点；矿道商人饰品库存。"},
	"dune_keeper_weapon": {"name": "刻量汲水杖", "slot": "weapon", "set_id": "dune_keeper", "stats": {"attack": 4}, "effect": "在沙漠战斗时，你主动打出的水直接伤害提高 8%。沙漠本身的水伤削弱照旧。", "story": "杖身每一道刻痕都代表一次允许分出的水量。最下方留着一段空白，提醒领路人给未到的人留份额。", "source": "沙漠藏物点；沙路商人武器库存。"},
	"dune_keeper_armor": {"name": "双层遮砂袍", "slot": "armor", "set_id": "dune_keeper", "stats": {"defense": 3}, "effect": "在沙漠战斗时，你受到的火直接伤害降低 10%。灼烧伤害照旧。", "story": "外层挡细砂，内层留出透气间隙，都是商旅多次改针的结果。袍角仍有没能完全洗掉的盐迹。", "source": "沙漠藏物点；沙路商人护甲库存。"},
	"dune_keeper_accessory": {"name": "划额水囊扣", "slot": "accessory", "set_id": "dune_keeper", "stats": {"speed": 8}, "effect": "在沙漠战斗时，你原本要花超过 1 点魔力的水技能少花 1 点，最低花 1 点。每场最多省两次，按减免后的费用判断能否施放。", "story": "囊扣上串着能逐个移动的小环，分水人每天亲手归位。它防的是慌乱中的浪费，不是沙漠本身。", "source": "沙漠藏物点；沙路商人饰品库存。"},
	"grove_mender_weapon": {"name": "分枝诊杖", "slot": "weapon", "set_id": "grove_mender", "stats": {"attack": 4}, "effect": "你用治疗技能给自己或选中的存活队友治疗时，治疗量提高 8%。药品、额外治疗和战后恢复照旧。", "story": "分叉处绑着量取药汁的窄布条，杖身并不藏有神谕。医者说，先量清楚才能知道还有多少可以分给别人。", "source": "森林藏物点；草药商人武器库存。"},
	"grove_mender_armor": {"name": "青衬换药衣", "slot": "armor", "set_id": "grove_mender", "stats": {"defense": 3}, "effect": "在森林战斗时，你受到的治疗提高 8%，也包括装备给你的额外治疗。", "story": "衣上的系带便于伤者自己换药，布面有许多不同颜色的补丁。每一块都来自物资短缺时仍被留下的小份余布。", "source": "森林藏物点；草药商人护甲库存。"},
	"grove_mender_accessory": {"name": "余药枝匣", "slot": "accessory", "set_id": "grove_mender", "stats": {"speed": 8}, "effect": "你的治疗技能把人治满且还有剩余时，给第一个符合条件的目标加盾。护盾为剩余治疗量的一半，最多为目标生命上限的 3%，持续全场接下来四次行动。每场最多两次。", "story": "匣子内侧分成很小的格子，只够保存一次敷药的余量。盖上写着“先问伤者”，没有替他人承诺痊愈。", "source": "森林藏物点；草药商人饰品库存。"},
	"grave_wayfarer_weapon": {"name": "稳载配重杖", "slot": "weapon", "set_id": "grave_wayfarer", "stats": {"attack": 4}, "effect": "你主动打出的重力直接伤害提高 8%。冥河吞噬伤害照旧。", "story": "配重杖曾用于抬稳坍塌门楣，让搬运者不被骤然偏移的重量拉倒。杖尾没有神徽，只有几道检查松脱的划线。", "source": "废墟藏物点；旧道商人武器库存。"},
	"grave_wayfarer_armor": {"name": "渡途束载衣", "slot": "armor", "set_id": "grave_wayfarer", "stats": {"defense": 3}, "effect": "在废墟战斗，或在攻击前已防御时，你受到的重力直接伤害降低 12%。两项同时满足也只减一次。冥河伤害照旧。", "story": "绑带把沉重物件分摊到肩背，便于普通人离开不稳的旧屋。穿戴说明特意把“承重”与“挡住死亡”写成两件不同的事。", "source": "废墟藏物点；旧道商人护甲库存。"},
	"grave_wayfarer_accessory": {"name": "未尽归途牌", "slot": "accessory", "set_id": "grave_wayfarer", "stats": {"speed": 8}, "effect": "防御开始时若迟缓还剩至少两次行动，先额外缩短一次，至少留一次，再照常扣去本次行动。每场最多两次。同一次迟缓最多被装备额外缩短一次。", "story": "牌面只记录等待确认的名字，不把失踪者直接算作亡者。送行人将它挂在衣内，提醒自己还有必须问清的路。", "source": "废墟藏物点；旧道商人饰品库存。"},
	"frontier_guard_weapon": {"name": "护沿短戟", "slot": "weapon", "set_id": "frontier_guard", "stats": {"attack": 4}, "effect": "普通攻击开始时你有护盾，这次普攻直接伤害提高 8%。", "story": "短戟刻意缩短了刃外的突起，免得在拥挤营门勾住同伴衣物。旧持有人教的第一件事是给撤回的人让路。", "source": "平原藏物点；边境商人武器库存。"},
	"frontier_guard_armor": {"name": "补钉门卫甲", "slot": "armor", "set_id": "frontier_guard", "stats": {"defense": 3}, "effect": "敌人出手前你的生命不足一半时，这次攻击对你的第一段直接伤害降低 12%。每场最多三次。", "story": "补钉的位置绕开旧伤，而不是把伤痕遮得看不见。铠甲主人仍在招募名册旁留着空行，等待离散的人回来。", "source": "废墟藏物点；边境商人护甲库存。"},
	"frontier_guard_accessory": {"name": "交岗铜扣", "slot": "accessory", "set_id": "frontier_guard", "stats": {"speed": 8}, "effect": "防御后，你额外获得 5 点能量，最高 100。每场最多两次。", "story": "铜扣相碰的轻响曾是交岗时确认彼此还在的暗号。它没有调遣他人的权力，只约束佩戴者记得回应。", "source": "平原藏物点；边境商人饰品库存。"},
	"road_surveyor_weapon": {"name": "试路折刃", "slot": "weapon", "set_id": "road_surveyor", "stats": {"attack": 4}, "effect": "每场战斗第一次打中出手前满血的敌人时，对它的直接伤害提高 10%。群攻只给第一个符合条件的目标加伤。", "story": "折刃常先用来挑开无人检查的旧绳结。勘路人不愿让同行者用身体去试一条尚未确认的路。", "source": "平原藏物点；旧驿商人武器库存。"},
	"road_surveyor_armor": {"name": "图袋夹层衣", "slot": "armor", "set_id": "road_surveyor", "stats": {"defense": 3}, "effect": "每场战斗，你首次受到的敌方直接伤害降低 15%。灼烧和额外触发的伤害照旧。", "story": "衣内夹层原是给怕雨的纸张准备的，后来也垫住了几次仓促躲避中的冲击。图册里仍有大片留白，没有被装备替人走完。", "source": "废墟藏物点；旧驿商人护甲库存。"},
	"road_surveyor_accessory": {"name": "待核里程盘", "slot": "accessory", "set_id": "road_surveyor", "stats": {"speed": 8}, "effect": "你首次从一个野外藏物点领到装备时，回复 3 点魔力。每天最多在两处触发。满魔力时不扣次数，那处藏物也只能领一回。", "story": "盘上的指针只能由人拨动，背面写着上次确认过的路段。它记录的是已经付出的脚程，不冒充预知前路的仪器。", "source": "平原藏物点；旧驿商人饰品库存。"},
	"oath_witness_weapon": {"name": "未开锋誓刃", "slot": "weapon", "set_id": "oath_witness", "stats": {"attack": 4}, "effect": "如果你出手时，第一个被你打中的敌人就已迟缓，而且被打后还活着，这个敌人下一次有效行动的直接伤害降低 10%。每场最多两次。同类效果只取较强的一项，较弱或相同效果不会刷新时间。", "story": "誓刃保留了一小段未开锋处，用来提醒持有者仍有收手的选择。它见证过签字，也见证过签字未能守住的夜晚。", "source": "废墟藏物点；旧约商人武器库存。"},
	"oath_witness_armor": {"name": "证词护心衣", "slot": "armor", "set_id": "oath_witness", "stats": {"defense": 3}, "effect": "敌人出手前你已迟缓时，这次攻击对你的第一段直接伤害降低 8%。每场最多三次。", "story": "护心衣内夹着抄写过多次的旧条款，破损处并未被涂去。见证者宁愿让后来人知道约定有多脆弱。", "source": "平原藏物点；旧约商人护甲库存。"},
	"oath_witness_accessory": {"name": "双名见证章", "slot": "accessory", "set_id": "oath_witness", "stats": {"speed": 8}, "effect": "防御后，给同场活着的其他队员中剩余生命比例最低的一人加盾。护盾为其生命上限的 3%，持续全场接下来四次行动。每场最多两次，独自出战时不触发。", "story": "见证章留着两个刻名位置，只有互相听见承诺的人才会填满。空着的一侧不是已经兑现的和平。", "source": "平原藏物点；旧约商人饰品库存。"},
	"trail_blade": {"name": "巡路短刃", "slot": "weapon", "set_id": "", "stats": {"attack": 4}, "effect": "提高攻击力。", "story": "刃背磨平，方便切开捆扎旅物的细绳。巡路人留下它，是希望后来者少在琐事上受伤，并非承诺道路安全。", "source": "既有初始装备/初始库存及既有商人装备渠道，不追送新副本。"},
	"padded_coat": {"name": "夹棉旅衣", "slot": "armor", "set_id": "", "stats": {"defense": 3}, "effect": "提高防御力。", "story": "夹层棉絮来自几次不同的修补，衣角留有赶路时蹭出的灰。它保护的是凡人的身体，不把伤势当作已经治愈。", "source": "既有初始装备/初始库存及既有商人装备渠道，不改旧解锁条件。"},
	"lamp_charm": {"name": "旧灯护符", "slot": "accessory", "set_id": "", "stats": {"speed": 8}, "effect": "提高速度。", "story": "护符里的小灯早已熄灭，外壳却被握得很亮。维洛丹的旅人有时留着它，只为记得仍要找到愿意听见自己名字的人。", "source": "既有初始装备/初始库存及既有商人装备渠道，不变成任务奖励放大器。"},
}

const SETS = {
	"ember_warden": {"name": "灰烬守望", "terrain": ["forest"], "story": "维洛丹的林工把火钩、隔热衣和封口炭筒配成一套，交给夜里看火的人。去森林的藏物点或找林边商人，有机会凑齐。", "two": "二件「识火」。你的火直接伤害提高 10%，受到的灼烧伤害降低 10%。与这套装备的武器和护甲合用时，分别是 18% 和 25%。同类效果与遗器合计最多 50%。", "three": "三件「限燃开口」。森林没下雨时，主动打出火直接伤害可以在命中后去掉湿润。战场必须原本湿润，没有冰面、导电和冥河。每场最多两次。这一击照样按湿润算，也不能顺手点燃。要点火，得等下一次有点燃效果的火技能。"},
	"tide_weaver": {"name": "潮痕编织", "terrain": ["swamp"], "story": "渡口帮工把旧水袋拆开，重新缝成护具。沼泽藏物点和渡口商人那里有机会找到。", "two": "二件「顺流施术」。你的水直接伤害提高 8%。有湿润效果的水技能照常打湿战场，已经点起的火不会因此熄灭。", "three": "三件「递出湿布」。战场正在燃烧且原本干燥时，若你的水技能命中并使战场湿润，给自己和剩余生命比例最低的一名存活队友各加一层盾，为各自生命上限的 4%。护盾持续全场接下来四次行动。每场和每天都最多两次。独自出战时只给自己加盾。刷新已有的湿润不会触发。"},
	"rime_path": {"name": "霜径行者", "terrain": ["mountain", "swamp"], "story": "高地搬运工把带齿的工具和防寒绑带借给雨季赶路的人。山地和沼泽藏物点、山道商人那里有机会找到。", "two": "二件「借水结面」。你的冰直接伤害提高 8%。战场已湿润且没有燃烧或冥河时，你的冰直接伤害命中后可以结冰或刷新冰面，持续全场接下来四次行动。每场最多三次。湿润和导电仍保留。刷新冰面不会让所有人再迟缓一次。", "three": "三件「破面留水」。出手前已有冰面，这次冰直接伤害再提高 10%。命中后可以打碎冰面，保留湿润和导电，并使第一个被打中且仍活着的敌人迟缓两次行动。每场最多破冰两次。同一击不能破冰后再结冰。"},
	"storm_conductor": {"name": "引雷测绘", "terrain": ["ruins", "swamp"], "story": "废墟里测路的人把导线、绝缘垫和计数铃配在一起。废墟、沼泽藏物点和测绘商人那里有机会找到。", "two": "二件「把湿润接成电荷」。你的雷直接伤害提高 8%。战场已湿润且没有燃烧或冥河时，雷直接伤害命中后可以让战场导电或刷新导电，持续全场接下来四次行动。每场最多三次。导电期间湿润至少会保留到导电结束，双方的雷伤环境倍率都增加 0.10。", "three": "三件「标定第二落点」。出手前战场已导电，你这次主动打出的雷直接伤害再提高 10%。每场最多两次，群攻或多段只算一次。"},
	"gale_runner": {"name": "逐风信使", "terrain": ["plains"], "story": "平原信使会在随身的衣具上缝进风标和信袋。平原藏物点和驿路商人那里有机会找到。", "two": "二件「暂借背风」。你的风直接伤害提高 8%。没有冥河时，主动打出的风直接伤害命中后可以立起或刷新风障，持续全场接下来四次行动。每场最多三次。双方的远程直接伤害都降低 10%。", "three": "三件「收帆再走」。有风障时防御，你会撤掉风障并获得生命上限 6% 的护盾。全场接下来四次行动内，你下一次主动打出的风直接伤害提高 12%。每场最多两次，未用掉的效果不会刷新。"},
	"stone_vow": {"name": "山根誓约", "terrain": ["mountain"], "story": "矿工把支架的尺寸写进誓词，提醒彼此先查清承重，再让人下井。山地藏物点和矿道商人那里有机会找到。", "two": "二件「托住山根」。你获得的护盾提高 10%。森林、山地或沼泽没有燃烧和冥河时，土直接伤害命中后可以升起或刷新根掩，持续全场接下来四次行动。每场最多三次。根掩期间双方受到的直接伤害都降低 5%。", "three": "三件「先立支架」。有根掩时防御，你会获得生命上限 8% 的护盾，持续全场接下来四次行动。每场最多两次。"},
	"dune_keeper": {"name": "沙海留泉", "terrain": ["desert"], "story": "护送商旅的人在水具上刻痕，记清一路喝了多少水。沙漠藏物点和沙路商人那里有机会找到。", "two": "二件「留给下一程」。在沙漠战斗时，你的水直接伤害再提高 8%。每天头两次走进沙漠且能省精力时，各少花 1 点精力，最低花 1 点。", "three": "三件「只开一囊」。在沙漠用水直接伤害命中后，你会获得生命上限 3% 的护盾，持续全场接下来四次行动，每场一次。在湿润的沙漠战场防御后，你回复生命上限的 5%，每场最多两次。两项各算次数。"},
	"grove_mender": {"name": "青枝医者", "terrain": ["forest"], "story": "林边的医者在难民营之间交换草药和包扎办法，也把没回来的人记在药袋一角。森林藏物点和草药商人那里有机会找到。", "two": "二件「林间续敷」。你的治疗技能给存活目标回复的生命提高 10%，加上诊杖就是 18%。森林没有燃烧和冥河时，治疗技能实际回血后可以升起或刷新根掩，持续全场接下来四次行动。每场最多三次。根掩期间双方受到的直接伤害都降低 5%。", "three": "三件「递药而不夺命」。你在已有根掩时用治疗技能实际回血后，再给除自己以外剩余生命比例最低的一名受伤队友回复其生命上限的 3%。每场最多两次。额外治疗不会再引出其他装备或遗器的效果。"},
	"grave_wayfarer": {"name": "渡途行者", "terrain": ["ruins"], "story": "送行人会带上配重、护额和记名片，好把遗物搬回去，记得自己是替谁走的这一趟。废墟藏物点和旧道商人那里有机会找到。", "two": "二件「凡人的承载」。在废墟战斗时，你受到的普攻直接伤害降低 8%。你的重力技能少花 1 点魔力，每场最多省两次。原本要花魔力的技能最低花 1 点，原本免费的照旧免费。", "three": "三件「不越界的支撑」。你的重力技能若本来会让敌人迟缓，第一个被打中且还活着的敌人迟缓多一次行动，最多加到三次。已有更长的迟缓照旧，每场最多触发两次。防御后还能获得生命上限 6% 的护盾，持续全场接下来四次行动，每场最多两次。冥河中两项都不触发。"},
	"frontier_guard": {"name": "边境守备", "terrain": ["plains", "ruins"], "story": "边境守卫常把检修过的扣带交给刚来的队员。平原、废墟的藏物点和边境商人那里有机会找到。", "two": "二件「先护自身」。你获得的护盾提高 10%，与遗器合计最多提高 30%。每次防御后可以获得生命上限 4% 的护盾，持续全场接下来四次行动。每场最多三次。", "three": "三件「破后补钉」。敌人打破你的护盾而你还活着时，全场接下来四次行动内，你下次防御会额外获得生命上限 8% 的护盾。护盾再持续四次行动。每场最多准备两次，未用掉的效果不会刷新。"},
	"road_surveyor": {"name": "旧驿勘路", "terrain": ["plains", "ruins"], "story": "勘路人习惯把绕路的原因写在地图角上。平原、废墟的藏物点和旧驿商人那里有机会找到。", "two": "二件「少走虚步」。每天头两次在陆地上移动且能省精力时，你各少花 1 点精力，最低花 1 点。", "three": "三件「归档再走」。你首次从一个野外藏物点领到装备时，回复 1 点精力。每天最多触发一次。精力已满时不扣次数，那处藏物也只能领一回。"},
	"oath_witness": {"name": "停战见证", "terrain": ["ruins", "plains"], "story": "旧停战见证人随身带着各方签过字的约定。有些约定只守了一夜，那些纸却留了下来。平原、废墟的藏物点和旧约商人那里有机会找到。", "two": "二件「一人一份援护」。防御后，给剩余生命比例最低的一名存活队友援护。这名队友下次受到敌人的直接伤害时，那次攻击对他的所有直接伤害降低 12%。若没挨打，援护会在这名队友下一次有效行动结束后消失。每场最多两次，同类效果取较强的一项，自己的援护未用时不能再给。", "three": "三件「约束而非宰制」。如果你出手时，第一个被你打中的敌人就已迟缓，而且被打后还活着，这个敌人下一次有效行动的直接伤害降低 15%。每场最多两次，与武器效果取较强的一项。防御后若成功给一名迟缓至少还剩两次行动的队友加上二件援护，迟缓再缩短一次，至少留一次。每场最多两次，两项各算次数。"},
}

const SLOTS = ["weapon", "armor", "accessory"]
const QUALITIES = ["common", "fine", "rare", "epic", "legendary"]
const QUALITY_NAMES = ["普通", "精良", "稀有", "史诗", "传说"]
const QUALITY_MULTIPLIERS = [1.0, 1.15, 1.35, 1.60, 2.0]
const QUALITY_WEIGHTS = [45, 30, 15, 8, 2]
const COST_MULTIPLIERS = [1.0, 1.25, 1.50, 1.75, 2.0]
const PRICE_MULTIPLIERS = [1, 2, 3, 5, 8]
const SLOT_PRICES = {"weapon": 18, "armor": 21, "accessory": 24}
const LEGACY_PRICES = {"trail_blade": 12, "padded_coat": 15, "lamp_charm": 18}
const MAX_LEVEL = 5

static func roll_quality(roller: RandomNumberGenerator) -> String:
	var roll = roller.randi_range(0, 99)
	for i in QUALITIES.size():
		roll -= QUALITY_WEIGHTS[i]
		if roll < 0:
			return QUALITIES[i]
	return QUALITIES[0]

static func roll_definition(terrain: String, roller: RandomNumberGenerator, allowed_slots: Array = SLOTS, supplies: Array = []) -> String:
	var pool = supplies.duplicate()
	for id in DATA:
		var definition = DATA[id]
		if definition.slot not in allowed_slots:
			continue
		pool.append(id)
		if terrain in SETS.get(definition.set_id, {}).get("terrain", []):
			pool.append(id)
	return pool[roller.randi_range(0, pool.size() - 1)]

static func bonus(instance: Dictionary, stat: String, level: int = -1) -> int:
	var definition = DATA[instance.definition_id]
	var base: int = definition.stats.get(stat, 0)
	var multiplier: float = QUALITY_MULTIPLIERS[QUALITIES.find(instance.quality)]
	if level < 0:
		level = int(instance.enhance_level)
	return roundi(base * multiplier * (1.0 + 0.20 * level))

static func upgrade_price(instance: Dictionary) -> int:
	var level = int(instance.enhance_level) + 1
	return ceili(4.0 * COST_MULTIPLIERS[QUALITIES.find(instance.quality)] * level * level)

static func price(instance: Dictionary) -> int:
	var id: String = instance.definition_id
	var quality: int = QUALITIES.find(instance.quality)
	var base: int = LEGACY_PRICES.get(id, SLOT_PRICES[DATA[id].slot])
	return base * PRICE_MULTIPLIERS[quality] + floori(float(instance.upgrade_paid) * 0.25)

static func label(instance: Dictionary) -> String:
	return "%s · %s +%d" % [DATA[instance.definition_id].name, QUALITY_NAMES[QUALITIES.find(instance.quality)], instance.enhance_level]
