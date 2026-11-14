extends RefCounted

const DATA = {
	"ember_warden_weapon": {"attack_delivery": "melee", "name": "截焰林钩", "slot": "weapon", "set_id": "ember_warden", "stats": {"attack": 4}, "effect": "行动开始时战场正在燃烧，你这次主动打出的火直接伤害提高 8%。灼烧和额外触发的伤害照旧。", "story": "林工原先拿它拖开燃烧的树枝。黑旗来抢木料那天，老工头把钩刃卡进对方的马缰，连人带鞍拖下了山坡。钩背从那以后就缺了一块，再也修不平。", "source": "森林藏物点；林缘商人武器库存。"},
	"ember_warden_armor": {"name": "炭衬守夜衣", "slot": "armor", "set_id": "ember_warden", "stats": {"defense": 3}, "effect": "你受到的战场灼烧伤害降低 15%。", "story": "林边作坊把炭毡夹在两层粗布之间，烧穿了就拆开换。衣领内侧绣着三个姓：借衣的人都说干完这趟就还，最后一个再也没回来。", "source": "森林藏物点；林缘商人护甲库存。"},
	"ember_warden_accessory": {"name": "封口余炭筒", "slot": "accessory", "set_id": "ember_warden", "stats": {"speed": 8}, "effect": "主动打出的火直接伤害击倒敌人后，你回复 3 点魔力。每次行动只算一次，每场最多两次。灼烧或额外触发的伤害击倒敌人时不算。", "story": "筒盖得拧两圈才会松开。一个守林人嫌麻烦，赶路时只扣了一圈，险些把整包干粮烘着；后来他给每只筒都加上了短链。", "source": "森林藏物点；林缘商人饰品库存。"},
	"tide_weaver_weapon": {"attack_delivery": "ranged", "name": "分汊导流杖", "slot": "weapon", "set_id": "tide_weaver", "stats": {"attack": 4}, "effect": "行动开始时战场湿润，你这次主动打出的水直接伤害提高 8%。", "story": "杖头分成两股，原来是疏通水槽用的铁叉。闸兵封住下游时，灌田的人拿它撬开了旁边的小渠，夜里轮流守着，不许巡兵再来堵。", "source": "沼泽藏物点；渡口商人武器库存。"},
	"tide_weaver_armor": {"name": "浸线短披", "slot": "armor", "set_id": "tide_weaver", "stats": {"defense": 3}, "effect": "攻击开始时战场湿润，你受到的火直接伤害降低 10%。灼烧伤害照旧。", "story": "渡工下水解缆前会把短披浸透，回来就搭在炉边。一次火油顺水烧过渡口，几个穿着湿披的人带着灼伤爬上岸；渡头老板第二天就把短披的价钱翻了一倍。", "source": "沼泽藏物点；渡口商人护甲库存。"},
	"tide_weaver_accessory": {"name": "回潮结绳", "slot": "accessory", "set_id": "tide_weaver", "stats": {"speed": 8}, "effect": "在湿润的战场上防御后，你回复生命上限的 3%。每场最多两次。满血时不扣次数。", "story": "同船的人每人打一个结，散伙时自己解开。最深的一道结已经泡硬，原主人下水去捞一袋工钱，此后没人再见过他。", "source": "沼泽藏物点；渡口商人饰品库存。"},
	"rime_path_weapon": {"attack_delivery": "melee", "name": "刻霜短镐", "slot": "weapon", "set_id": "rime_path", "stats": {"attack": 4}, "effect": "行动开始时战场有冰面，你这次主动打出的冰直接伤害提高 8%。", "story": "挑夫用短镐敲开路边积冰，也用镐尖把滑落的货箱拖回来。有只山兽拦过路，在镐柄上咬出了一圈齿印，主人每次喝酒都把它说得更大一些。", "source": "山地藏物点；山道商人武器库存。"},
	"rime_path_armor": {"name": "钉纹行霜袄", "slot": "armor", "set_id": "rime_path", "stats": {"defense": 3}, "effect": "当你将受到至少持续两次行动的迟缓时，持续时间缩短一次行动，至少保留一次。每场最多两次。同一次迟缓最多缩短一次，减速幅度照旧。", "story": "高地裁衣人把皮条与碎甲片缝在袄摆，挡住扑上来的冰碴。挑夫嫌它重，便自己剪短半截；回村时，他的小腿冻得裂了好几道口子。", "source": "山地藏物点；山道商人护甲库存。"},
	"rime_path_accessory": {"name": "霜纹记步扣", "slot": "accessory", "set_id": "rime_path", "stats": {"speed": 8}, "effect": "如果你打中的第一个目标在你出手前就已迟缓，你在这次行动结束后回复 2 点魔力。每场最多两次。", "story": "搬运队走过三处风口便拨一下扣片，找背风处歇脚。一个抢头功的领队曾把扣片拨回原位，多赶了两里，最后只好花自己的钱请人背伤员。", "source": "湿地藏物点；山道商人饰品库存。"},
	"storm_conductor_weapon": {"attack_delivery": "ranged", "name": "分流测杆", "slot": "weapon", "set_id": "storm_conductor", "stats": {"attack": 4}, "effect": "行动开始时战场湿润或导电，你这次主动打出的雷直接伤害提高 8%。两个条件都满足时也只加一次。", "story": "旧塔遭雷击后，测绘学徒用它探查散落的导线。找回来多少铜，就拿多少工钱，手烧伤了也没钱拿。后来的人见杆尾上还有烧黑的指印，都知道得先戴厚手套。", "source": "废墟藏物点；测绘商人武器库存。"},
	"storm_conductor_armor": {"name": "断环绝缘衣", "slot": "armor", "set_id": "storm_conductor", "stats": {"defense": 3}, "effect": "攻击开始时战场导电，你受到的雷直接伤害降低 20%。与其他装备和遗器共用减伤上限，战场本身的雷伤加成照旧。", "story": "引雷工坊把树脂垫缝在铜环之间，穿起来总有股松脂味。师傅不肯给学徒用便宜的薄垫，两人为这笔钱吵了一整天，最后各付一半。", "source": "废墟藏物点；测绘商人护甲库存。"},
	"storm_conductor_accessory": {"name": "记闪小铃", "slot": "accessory", "set_id": "storm_conductor", "stats": {"speed": 8}, "effect": "主动打出雷直接伤害后，你额外获得 5 点能量。每场最多两次。能量满时不扣次数。", "story": "小铃挂在测杆下方，雷声震过旧塔时，铃舌会接着轻颤。负责报数的学徒后来上了战船，别人听见雷就伏倒，他却还会下意识数到三。", "source": "湿地藏物点；测绘商人饰品库存。"},
	"gale_runner_weapon": {"attack_delivery": "melee", "name": "折羽引风刃", "slot": "weapon", "set_id": "gale_runner", "stats": {"attack": 4}, "effect": "防御后，全场接下来四次行动内，你下一次主动打出的风直接伤害提高 10%。每场最多准备两次，未用掉的效果不会刷新。", "story": "刃脊的折片原是驿站屋顶的风标。信使拆下来磨成短刃那天，驿长骂他毁东西；三日后，他用这把刃割断绳网，带回了被扣住的两名驿夫。", "source": "平原藏物点；驿路商人武器库存。"},
	"gale_runner_armor": {"name": "夹信轻斗篷", "slot": "armor", "set_id": "gale_runner", "stats": {"defense": 3}, "effect": "攻击开始时战场有风障，你受到的远程直接伤害再降低 8%。风障本身另算，两项合用时受到原伤害的 82.8%。", "story": "信袋缝在斗篷内侧，最里面那只留给出价最高的雇主。上一任主人曾把两封互相催兵的急信一起送到，收完钱就骑马出了城。", "source": "平原藏物点；驿路商人护甲库存。"},
	"gale_runner_accessory": {"name": "晴野路哨", "slot": "accessory", "set_id": "gale_runner", "stats": {"speed": 8}, "effect": "提高速度。", "story": "驿路上的短哨原只用来叫人开门。后来关口收了黑旗的钱，熟悉的两短一长反倒招来弩箭；逃出去的信使从此换了哨音。", "source": "平原藏物点；驿路商人饰品库存。"},
	"stone_vow_weapon": {"attack_delivery": "melee", "name": "验层短锤", "slot": "weapon", "set_id": "stone_vow", "stats": {"attack": 4}, "effect": "在山地战斗时，你主动打出的土直接伤害提高 10%。", "story": "老矿工拿短锤敲岩壁，回声不对便叫人退开。矿主有一回明知敲起来不对，还让他报一声安全，他把锤子拍在工钱袋上，叫矿主自己先下去。", "source": "山地藏物点；矿道商人武器库存。"},
	"stone_vow_armor": {"name": "承梁铆甲", "slot": "armor", "set_id": "stone_vow", "stats": {"defense": 3}, "effect": "攻击开始时你已在防御，你受到的直接伤害再降低 8%。灼烧和额外触发的伤害照旧。", "story": "胸前的铆板取自断裂的矿架，内衬却是精细的羊皮。守山的佣兵宁可省下两顿买肉的钱来换内衬，也不想让甲片再把肩膀磨破。", "source": "山地藏物点；矿道商人护甲库存。"},
	"stone_vow_accessory": {"name": "回响铅垂", "slot": "accessory", "set_id": "stone_vow", "stats": {"speed": 8}, "effect": "普通攻击、施放技能、使出终结技或防御后，若你行动前已有护盾且还活着，回复 2 点魔力。每场最多两次。", "story": "塌方后，领班把铅垂挂在临时支架上，铅垂一晃，他就叫人加一根木头撑住。救援结束时，库房的好木料全用光了，矿主直到开春还在追着算钱。", "source": "山地藏物点；矿道商人饰品库存。"},
	"dune_keeper_weapon": {"attack_delivery": "ranged", "name": "刻量汲水杖", "slot": "weapon", "set_id": "dune_keeper", "stats": {"attack": 4}, "effect": "在沙漠战斗时，你主动打出的水直接伤害提高 8%。沙漠本身的水伤削弱照旧。", "story": "领路人用杖探沙，也用杖身的刻痕量水。有人趁夜磨浅了一道刻痕，多领走半碗；第二天杖上添了铜箍，水改由两个人一起分。", "source": "沙漠藏物点；沙路商人武器库存。"},
	"dune_keeper_armor": {"name": "双层遮砂袍", "slot": "armor", "set_id": "dune_keeper", "stats": {"defense": 3}, "effect": "在沙漠战斗时，你受到的火直接伤害降低 10%。灼烧伤害照旧。", "story": "外层挡细砂，内层留着透气的空隙。商队裁工坚持把袖口做宽，说自己走过那条路；伙计不信，收紧袖口赶了一天，回来时肘弯全磨破了。", "source": "沙漠藏物点；沙路商人护甲库存。"},
	"dune_keeper_accessory": {"name": "划额水囊扣", "slot": "accessory", "set_id": "dune_keeper", "stats": {"speed": 8}, "effect": "在沙漠战斗时，你原本要花超过 1 点魔力的水技能少花 1 点，最低花 1 点。每场最多省两次，按减免后的费用判断能否施放。", "story": "每分出去一袋水，分水的人就拨一下小环。旧主人曾把自己的那只环藏起来，骗队伍说水还够，夜里却去偷喝驮兽的份额。", "source": "沙漠藏物点；沙路商人饰品库存。"},
	"grove_mender_weapon": {"attack_delivery": "ranged", "name": "分枝诊杖", "slot": "weapon", "set_id": "grove_mender", "stats": {"attack": 4}, "effect": "你用治疗技能给自己或选中的存活队友治疗时，治疗量提高 8%。药品、额外治疗和战后恢复照旧。", "story": "诊杖撑着一面褪色的布旗，难民看见它就知道药棚挪到了哪里。上一任医者腿脚不好，争吵的人堵住路时，便拿杖尾敲他们的靴子。", "source": "森林藏物点；草药商人武器库存。"},
	"grove_mender_armor": {"name": "青衬换药衣", "slot": "armor", "set_id": "grove_mender", "stats": {"defense": 3}, "effect": "在森林战斗时，你受到的治疗提高 8%，也包括装备给你的额外治疗。", "story": "系带都缝在前面，独自养伤的人也能松开换药。做这件衣服的裁工原想只卖给军官，后来发现难民营里要的人更多，便又赶了三十件。", "source": "森林藏物点；草药商人护甲库存。"},
	"grove_mender_accessory": {"name": "余药枝匣", "slot": "accessory", "set_id": "grove_mender", "stats": {"speed": 8}, "effect": "你的治疗技能把人治满且还有剩余时，给第一个符合条件的目标加盾。护盾为剩余治疗量的一半，最多为目标生命上限的 3%，持续全场接下来四次行动。每场最多两次。", "story": "药匣只够放几份敷伤的药。医者留了一格给糖块，来换药的孩子总先盯着那一格，她便把最苦的药粉挪到了旁边。", "source": "森林藏物点；草药商人饰品库存。"},
	"grave_wayfarer_weapon": {"attack_delivery": "ranged", "name": "稳载配重杖", "slot": "weapon", "set_id": "grave_wayfarer", "stats": {"attack": 4}, "effect": "你主动打出的重力直接伤害提高 8%。冥河吞噬伤害照旧。", "story": "配重杖曾撑起过半扇倒塌的门，好让屋里的人爬出来。主人此后总把杖带在身边，邻居借去搬石磨，他也站在旁边盯着。", "source": "废墟藏物点；旧道商人武器库存。"},
	"grave_wayfarer_armor": {"name": "渡途束载衣", "slot": "armor", "set_id": "grave_wayfarer", "stats": {"defense": 3}, "effect": "在废墟战斗，或在攻击前已防御时，你受到的重力直接伤害降低 12%。两项同时满足也只减一次。冥河伤害照旧。", "story": "肩背的绑带能固定沉重的箱子。一个送遗物的人替别人走了许多趟路，自己父亲的箱子却一直压在床下，迟迟没有打开。", "source": "废墟藏物点；旧道商人护甲库存。"},
	"grave_wayfarer_accessory": {"name": "未尽归途牌", "slot": "accessory", "set_id": "grave_wayfarer", "stats": {"speed": 8}, "effect": "防御开始时若迟缓还剩至少两次行动，先额外缩短一次，至少留一次，再照常扣去本次行动。每场最多两次。同一次迟缓最多被装备额外缩短一次。", "story": "牌上刻着一个名字和旧渡口的位置。送牌的女人说，找着本人就交还，找不着也别扔；她还要去下一个渡口问。", "source": "废墟藏物点；旧道商人饰品库存。"},
	"frontier_guard_weapon": {"attack_delivery": "melee", "name": "护沿短戟", "slot": "weapon", "set_id": "frontier_guard", "stats": {"attack": 4}, "effect": "普通攻击开始时你有护盾，这次普攻直接伤害提高 8%。", "story": "戟刃外侧被锉短了，方便在狭窄门道里转身。军官嫌不威风，老门卫就请他披上长斗篷，一起来窄门里试试。", "source": "平原藏物点；边境商人武器库存。"},
	"frontier_guard_armor": {"name": "补钉门卫甲", "slot": "armor", "set_id": "frontier_guard", "stats": {"defense": 3}, "effect": "敌人出手前你的生命不足一半时，这次攻击对你的第一段直接伤害降低 12%。每场最多三次。", "story": "甲片补了又补，唯独左肩那枚新钉始终亮着。那是一个逃兵临走前替同伴打的，同伴后来接到追捕令，也没把它换掉。", "source": "废墟藏物点；边境商人护甲库存。"},
	"frontier_guard_accessory": {"name": "交岗铜扣", "slot": "accessory", "set_id": "frontier_guard", "stats": {"speed": 8}, "effect": "防御后，你额外获得 5 点能量，最高 100。每场最多两次。", "story": "夜里换岗，来人先敲两下铜扣，岗上的人再回一下。边军欠饷那个月，有一夜只听见了前两声，整座营门随后被悄悄打开。", "source": "平原藏物点；边境商人饰品库存。"},
	"road_surveyor_weapon": {"attack_delivery": "melee", "name": "试路折刃", "slot": "weapon", "set_id": "road_surveyor", "stats": {"attack": 4}, "effect": "每场战斗第一次打中出手前满血的敌人时，对它的直接伤害提高 10%。群攻只给第一个符合条件的目标加伤。", "story": "探路的人用折刀拨开灌木。回来的时候，他把自己留在路上的记号削掉了。他把通向好水源的近路卖给商队，却不愿让收过路钱的兵也跟过来。", "source": "平原藏物点；旧驿商人武器库存。"},
	"road_surveyor_armor": {"name": "图袋夹层衣", "slot": "armor", "set_id": "road_surveyor", "stats": {"defense": 3}, "effect": "每场战斗，你首次受到的敌方直接伤害降低 15%。灼烧和额外触发的伤害照旧。", "story": "夹层里原本藏着两套地图，一套给雇主，一套留给自己。主人死后，收遗物的人发现两套图在同一处岔口画向了不同方向。", "source": "废墟藏物点；旧驿商人护甲库存。"},
	"road_surveyor_accessory": {"name": "待核里程盘", "slot": "accessory", "set_id": "road_surveyor", "stats": {"speed": 8}, "effect": "你首次从一个野外藏物点领到装备时，回复 3 点魔力。每天最多在两处触发。满魔力时不扣次数，那处藏物也只能领一回。", "story": "每走完一段路，就拨一格指针。老信使发现长官少算了他走过的路，把里程盘钉在饭桌上，叫收信的人一个个来认自己走过的路。", "source": "平原藏物点；旧驿商人饰品库存。"},
	"oath_witness_weapon": {"attack_delivery": "melee", "name": "未开锋誓刃", "slot": "weapon", "set_id": "oath_witness", "stats": {"attack": 4}, "effect": "如果你出手时，第一个被你打中的敌人就已迟缓，而且被打后还活着，这个敌人下一次有效行动的直接伤害降低 10%。每场最多两次。同类效果只取较强的一项，较弱或相同效果不会刷新时间。", "story": "刀根留着一截钝口。停战会面时，见证人握住那里，把刀横在桌上；有人越过刀刃去抓对方衣领，他便先用刀柄敲了那只手。", "source": "废墟藏物点；旧约商人武器库存。"},
	"oath_witness_armor": {"name": "证词护心衣", "slot": "armor", "set_id": "oath_witness", "stats": {"defense": 3}, "effect": "敌人出手前你已迟缓时，这次攻击对你的第一段直接伤害降低 8%。每场最多三次。", "story": "这件护心衣的内袋里装过两军换俘虏的协议。约定执行到一半，箭从城墙上飞下来；见证人拽着离自己最近的俘虏滚进壕沟，纸和衣都被泥浸透了。", "source": "平原藏物点；旧约商人护甲库存。"},
	"oath_witness_accessory": {"name": "双名见证章", "slot": "accessory", "set_id": "oath_witness", "stats": {"speed": 8}, "effect": "防御后，给同场活着的其他队员中剩余生命比例最低的一人加盾。护盾为其生命上限的 3%，持续全场接下来四次行动。每场最多两次，独自出战时不触发。", "story": "两位守将把名字刻在铜章两侧，约定日落前各退一里。第二天，一方的旗仍插在原地，另一方把铜章钉在箭上射了回去。", "source": "平原藏物点；旧约商人饰品库存。"},
	"trail_blade": {"attack_delivery": "melee", "name": "巡路短刃", "slot": "weapon", "set_id": "", "stats": {"attack": 4}, "effect": "提高攻击力。", "story": "短刃是村里铁匠拿断刀改的，刀背磨平，握柄缠着粗布。买不起长剑的巡路人用了七年，最后把它和没花完的工钱一起留给了徒弟。", "source": "既有初始装备/初始库存及既有商人装备渠道，不追送新副本。"},
	"padded_coat": {"name": "夹棉旅衣", "slot": "armor", "set_id": "", "stats": {"defense": 3}, "effect": "提高防御力。", "story": "旅衣的棉絮拆洗过许多次，左边袖口总比右边短一点。补衣的人说是料不够，穿衣的人却记得，那块布曾拿去给同行者包过手。", "source": "既有初始装备/初始库存及既有商人装备渠道，不改旧解锁条件。"},
	"lamp_charm": {"name": "旧灯护符", "slot": "accessory", "set_id": "", "stats": {"speed": 8}, "effect": "提高速度。", "story": "灯芯早就烧完了，灯壳被人摸得发亮。主人曾靠它照着路回家；如今村子搬空了，他还是习惯天黑后把它挂在胸前。", "source": "既有初始装备/初始库存及既有商人装备渠道，不变成任务奖励放大器。"},
}

const SETS = {
	"ember_warden": {"name": "灰烬守望", "terrain": ["forest"], "story": "林边起火时，夜班林工先拿钩刃开出隔火带，再护着人撤离。村里凑钱替他们做了这套衣具，木料商也出了钱，却要他们先保住自己的堆场。", "two": "二件「识火」。你的火直接伤害提高 10%，受到的灼烧伤害降低 10%。与这套装备的武器和护甲合用时，分别是 18% 和 25%。同类效果与遗器合计最多 50%。", "three": "三件「限燃开口」。森林没下雨时，主动打出火直接伤害可以在命中后去掉湿润。战场必须原本湿润，没有冰面、导电和冥河。每场最多两次。这一击照样按湿润算，也不能顺手点燃。要点火，得等下一次有点燃效果的火技能。"},
	"tide_weaver": {"name": "潮痕编织", "terrain": ["swamp"], "story": "封河后，渡工白日替守军搬货，夜里偷偷开小船。短披、导流杖与结绳都湿了又干，他们收钱载客，也会为多带一个人争得脸红。", "two": "二件「顺流施术」。你的水直接伤害提高 8%。有湿润效果的水技能照常打湿战场，已经点起的火不会因此熄灭。", "three": "三件「递出湿布」。战场正在燃烧且原本干燥时，若你的水技能命中并使战场湿润，给自己和剩余生命比例最低的一名存活队友各加一层盾，为各自生命上限的 4%。护盾持续全场接下来四次行动。每场和每天都最多两次。独自出战时只给自己加盾。刷新已有的湿润不会触发。"},
	"rime_path": {"name": "霜径行者", "terrain": ["mountain", "swamp"], "story": "山口结冰，挑夫仍得替谷地运盐。领队把防寒衣具借给新人，押金先从工钱里扣。跑完第一趟，新人先问领队什么时候退押金。", "two": "二件「借水结面」。你的冰直接伤害提高 8%。战场已湿润且没有燃烧或冥河时，你的冰直接伤害命中后可以结冰或刷新冰面，持续全场接下来四次行动。每场最多三次。湿润和导电仍保留。刷新冰面不会让所有人再迟缓一次。", "three": "三件「破面留水」。出手前已有冰面，这次冰直接伤害再提高 10%。命中后可以打碎冰面，保留湿润和导电，并使第一个被打中且仍活着的敌人迟缓两次行动。每场最多破冰两次。同一击不能破冰后再结冰。"},
	"storm_conductor": {"name": "引雷测绘", "terrain": ["ruins", "swamp"], "story": "旧塔倒下后，工坊派学徒回收铜线。有人靠卖铜发了财，也有人拿着焦黑的测杆回来讨医药钱；这套护具正是在那些争吵之后改成的。", "two": "二件「把湿润接成电荷」。你的雷直接伤害提高 8%。战场已湿润且没有燃烧或冥河时，雷直接伤害命中后可以让战场导电或刷新导电，持续全场接下来四次行动。每场最多三次。导电期间湿润至少会保留到导电结束，双方的雷伤环境倍率都增加 0.10。", "three": "三件「标定第二落点」。出手前战场已导电，你这次主动打出的雷直接伤害再提高 10%。每场最多两次，群攻或多段只算一次。"},
	"gale_runner": {"name": "逐风信使", "terrain": ["plains"], "story": "驿路一断，信使便各找雇主。有人送求援信，有人替两边传军令；斗篷里的口袋越来越多，回到驿站能一起喝酒的人却越来越少。", "two": "二件「暂借背风」。你的风直接伤害提高 8%。没有冥河时，主动打出的风直接伤害命中后可以立起或刷新风障，持续全场接下来四次行动。每场最多三次。双方的远程直接伤害都降低 10%。", "three": "三件「收帆再走」。有风障时防御，你会撤掉风障并获得生命上限 6% 的护盾。全场接下来四次行动内，你下一次主动打出的风直接伤害提高 12%。每场最多两次，未用掉的效果不会刷新。"},
	"stone_vow": {"name": "山根誓约", "terrain": ["mountain"], "story": "矿主催着复工，工匠们却把锤子挂在井口，非要先换掉裂梁。争到第五天，附近的石匠抬来了第一车撑木，收的是工匠们凑出的私钱。", "two": "二件「托住山根」。你获得的护盾提高 10%。森林、山地或沼泽没有燃烧和冥河时，土直接伤害命中后可以升起或刷新根掩，持续全场接下来四次行动。每场最多三次。根掩期间双方受到的直接伤害都降低 5%。", "three": "三件「先立支架」。有根掩时防御，你会获得生命上限 8% 的护盾，持续全场接下来四次行动。每场最多两次。"},
	"dune_keeper": {"name": "沙海留泉", "terrain": ["desert"], "story": "沙路上的护卫起初只管挡劫匪，后来才明白，丢一头驮水的兽比挨一刀更难收场。他们给每件水具加了刻痕，轮流守夜，连雇主也不许私开水囊。", "two": "二件「留给下一程」。在沙漠战斗时，你的水直接伤害再提高 8%。", "three": "三件「只开一囊」。在沙漠用水直接伤害命中后，你会获得生命上限 3% 的护盾，持续全场接下来四次行动，每场一次。在湿润的沙漠战场防御后，你回复生命上限的 5%，每场最多两次。两项各算次数。"},
	"grove_mender": {"name": "青枝医者", "terrain": ["forest"], "story": "林边药棚常随着难民搬迁，诊杖上的布旗成了找人的记号。有钱的人就付药钱，没钱的人可以先欠着。有一年秋天，欠药钱的人给药棚送来了够过冬的柴。", "two": "二件「林间续敷」。你的治疗技能给存活目标回复的生命提高 10%，加上诊杖就是 18%。森林没有燃烧和冥河时，治疗技能实际回血后可以升起或刷新根掩，持续全场接下来四次行动。每场最多三次。根掩期间双方受到的直接伤害都降低 5%。", "three": "三件「递药而不夺命」。你在已有根掩时用治疗技能实际回血后，再给除自己以外剩余生命比例最低的一名受伤队友回复其生命上限的 3%。每场最多两次。额外治疗不会再引出其他装备或遗器的效果。"},
	"grave_wayfarer": {"name": "渡途行者", "terrain": ["ruins"], "story": "送遗物的人背着箱子穿过废村，有时带回一封家书，有时只带回一只鞋。雇主付钱求一个下落，他们便继续走，路上遇见还留在世上的亡魂，他们也只能绕开，或等有人来给亡魂带路。", "two": "二件「凡人的承载」。在废墟战斗时，你受到的普攻直接伤害降低 8%。你的重力技能少花 1 点魔力，每场最多省两次。原本要花魔力的技能最低花 1 点，原本免费的照旧免费。", "three": "三件「不越界的支撑」。你的重力技能若本来会让敌人迟缓，第一个被打中且还活着的敌人迟缓多一次行动，最多加到三次。已有更长的迟缓照旧，每场最多触发两次。防御后还能获得生命上限 6% 的护盾，持续全场接下来四次行动，每场最多两次。冥河中两项都不触发。"},
	"frontier_guard": {"name": "边境守备", "terrain": ["plains", "ruins"], "story": "边军的衣甲从库房发下去时就不是新的。新兵在营门练到深夜，老兵轮流教他们换岗、合门和守住狭道；欠饷时，同一批人也会堵着军官不让走。", "two": "二件「先护自身」。你获得的护盾提高 10%，与遗器合计最多提高 30%。每次防御后可以获得生命上限 4% 的护盾，持续全场接下来四次行动。每场最多三次。", "three": "三件「破后补钉」。敌人打破你的护盾而你还活着时，全场接下来四次行动内，你下次防御会额外获得生命上限 8% 的护盾。护盾再持续四次行动。每场最多准备两次，未用掉的效果不会刷新。"},
	"road_surveyor": {"name": "旧驿勘路", "terrain": ["plains", "ruins"], "story": "旧驿站烧毁后，几个驿夫合伙接下了勘路的生意。他们卖近路，也卖绕开关卡的办法；地图藏在衣里，价钱得见到买家才定。", "two": "", "three": ""},
	"oath_witness": {"name": "停战见证", "terrain": ["ruins", "plains"], "story": "停战见证人带着两军认得的章，站在双方交换俘虏、撤兵时都要经过的路口。他们手里没有兵。两边都想把自己的人接回去，才肯听他们说话。将军要是临时反悔，最先挨箭的常是他们。", "two": "二件「一人一份援护」。防御后，给剩余生命比例最低的一名存活队友援护。这名队友下次受到敌人的直接伤害时，那次攻击对他的所有直接伤害降低 12%。若没挨打，援护会在这名队友下一次有效行动结束后消失。每场最多两次，同类效果取较强的一项，自己的援护未用时不能再给。", "three": "三件「约束而非宰制」。如果你出手时，第一个被你打中的敌人就已迟缓，而且被打后还活着，这个敌人下一次有效行动的直接伤害降低 15%。每场最多两次，与武器效果取较强的一项。防御后若成功给一名迟缓至少还剩两次行动的队友加上二件援护，迟缓再缩短一次，至少留一次。每场最多两次，两项各算次数。"},
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


static func card(instance: Dictionary) -> Dictionary:
	var id: String = instance.definition_id
	var item: Dictionary = DATA[id]
	var level := int(instance.enhance_level)
	var slot: String = item.slot
	var theme: String = item.set_id
	var cost := 3 if slot == "accessory" else 1 if id == "trail_blade" or id == "padded_coat" else 2
	var card_data := {"kind": "equipment", "name": label(instance), "icon": id, "level": level, "cost": cost,
		"slot": slot, "element": "", "story": item.story}
	var text: Array[String] = []
	var tiers := floori(level / 2.0)
	if slot == "weapon":
		card_data.attack_delivery = item.attack_delivery
		var extends_reach := theme in ["frontier_guard", "gale_runner", "storm_conductor"]
		card_data.attack = (1 if extends_reach else 2) + tiers
		card_data.range = 2 if extends_reach else 0
		text.append("普通攻击 +%d" % card_data.attack)
		if extends_reach:
			text.append("横竖攻击射程至少 2，路径须畅通")
	elif slot == "armor":
		card_data.armor = 3 + tiers
		text.append("获得 %d 点护甲" % card_data.armor)
	else:
		card_data.hp_bonus = 1 + tiers
		text.append("本场生命上限和当前生命各 +%d" % card_data.hp_bonus)
	var quality := QUALITIES.find(instance.quality)
	var guard := int(level >= 1) + int(level >= 5) + int(quality >= 2)
	if guard > 0:
		card_data.equip_guard = guard
		text.append("装备时额外获得 %d 点护甲" % card_data.equip_guard)
	var heal := int(level >= 3) + int(quality >= 4)
	if heal > 0:
		card_data.heal = heal
		text.append("装备时回复 %d 点生命" % heal)
	var elements := {"ember_warden": "fire", "tide_weaver": "water", "rime_path": "ice",
		"storm_conductor": "lightning", "gale_runner": "wind", "stone_vow": "earth",
		"dune_keeper": "water", "grove_mender": "water", "grave_wayfarer": "ice"}
	card_data.element = elements.get(theme, "")
	if not card_data.element.is_empty():
		card_data.affinity_guard = 1
		text.append("装备给同属性棋子时再获得 1 点护甲")
	var target := "友方棋子"
	if slot == "weapon":
		target = "友方远程棋子" if item.attack_delivery == "ranged" else "友方近战棋子"
	card_data.trait = "装备给一枚%s。%s。" % [target, "；".join(text)]
	return card_data
