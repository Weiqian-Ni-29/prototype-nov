extends RefCounted

const DATA = {
	"ember_warden_weapon": {"name": "截焰林钩", "slot": "weapon", "set_id": "ember_warden", "stats": {"attack": 4}, "effect": "沿火修枝：动作开始已有 burning 时，佩戴者该动作原生火直接伤害 +8%；每个主伤害包只计一次，不加强火 tick 或追加包。无燃烧时不生效。", "story": "林工用钩刃拖开着火的枝条，让火舌离避难队伍远一些。刃背刻的是风向记号，不是神名。", "source": "森林藏物点；林缘商人武器库存。"},
	"ember_warden_armor": {"name": "炭衬守夜衣", "slot": "armor", "set_id": "ember_warden", "stats": {"defense": 3}, "effect": "隔炭夹层：佩戴者承受的 burning 环境伤害减少 15%，每个有效火 tick 生效；不减冥河剧情伤害，不替同伴抵火。", "story": "衣襟里缝着可替换的炭毡，旧针脚来自不同村落。它能缓一缓灼痛，却从未许诺穿衣人不会烧伤。", "source": "森林藏物点；林缘商人护甲库存。"},
	"ember_warden_accessory": {"name": "封口余炭筒", "slot": "accessory", "set_id": "ember_warden", "stats": {"speed": 8}, "effect": "收束余温：佩戴者用原生火主命中击杀至少一敌后回复本人 MP 3，最多 2 次/战、每根动作一次；火 tick 及其他装备/遗器次生击杀不触发。", "story": "守林人把火种装进能锁住的筒里，才肯走进难民歇脚的棚屋。筒底仍压着一张尚未送达的巡林路线。", "source": "森林藏物点；林缘商人饰品库存。"},
	"tide_weaver_weapon": {"name": "分汊导流杖", "slot": "weapon", "set_id": "tide_weaver", "stats": {"attack": 4}, "effect": "顺槽引流：动作开始有 wet 时，本人原生水直接伤害 +8%；没有 wet、不造成水直接伤害或只治疗时不增加伤害。", "story": "杖首的分汊原是疏通水槽的工具。使用它的人相信，让水走对地方比把浪卷得更高更重要。", "source": "沼泽藏物点；渡口商人武器库存。"},
	"tide_weaver_armor": {"name": "浸线短披", "slot": "armor", "set_id": "tide_weaver", "stats": {"defense": 3}, "effect": "湿线隔热：动作开始有 wet 时，本人受到原生火主动作直接伤害减少 10%；不减少 burning tick，也不保护其他队员。", "story": "披衣缝线吸水后会变沉，穿戴者不得不放慢脚步。渡口账本把这份负担当作保住皮肤的交换。", "source": "沼泽藏物点；渡口商人护甲库存。"},
	"tide_weaver_accessory": {"name": "回潮结绳", "slot": "accessory", "set_id": "tide_weaver", "stats": {"speed": 8}, "effect": "拧水歇息：本人完成 guard，且开始快照有 wet 时，回复本人最大 HP 的 3%，最多 2 次/战；本人必须存活，满血不消耗额度。", "story": "结绳原本用于标记水袋轮流领取的次序。最深的一道结留给仍未归队的人，没有人擅自解开。", "source": "沼泽藏物点；渡口商人饰品库存。"},
	"rime_path_weapon": {"name": "刻霜短镐", "slot": "weapon", "set_id": "rime_path", "stats": {"attack": 4}, "effect": "顺纹凿击：动作开始有 frozen 时，本人原生冰直接伤害 +8%；不把普通攻击改成冰，也不追加冰面伤害。", "story": "短镐的齿距来自挑夫辨认薄冰裂纹的经验。它先是保命工具，后来才被用来挡住追兵。", "source": "山地藏物点；山道商人武器库存。"},
	"rime_path_armor": {"name": "钉纹行霜袄", "slot": "armor", "set_id": "rime_path", "stats": {"defense": 3}, "effect": "撑稳步幅：本人将收到一次时长至少 2 的 slow 申请时，将该申请减少 1、最低 1，最多 2 次/战；同次减时遵守总计最多减 1，不减少 slow 的速度惩罚。", "story": "袄摆缀着细小配重，提醒穿衣人不要在湿滑处跨得太大。修补者仍在每件衣领写下“薄冰不可托命”。", "source": "山地藏物点；山道商人护甲库存。"},
	"rime_path_accessory": {"name": "霜纹记步扣", "slot": "accessory", "set_id": "rime_path", "stats": {"speed": 8}, "effect": "读出停顿：本人主命中的首个有效目标在动作开始时已有 slow>0，则该根动作结束后本人回复 MP 2，最多 2 次/战；同动作新加的 slow 不满足条件。", "story": "扣面一格一格刻着需要歇脚的间隔。一个信使将它留下，只说别把沉默当作前方安全。", "source": "湿地藏物点；山道商人饰品库存。"},
	"storm_conductor_weapon": {"name": "分流测杆", "slot": "weapon", "set_id": "storm_conductor", "stats": {"attack": 4}, "effect": "沿湿测压：动作开始有湿润或 charged 时，本人原生雷直接伤害 +8%，两条件同时成立也只加一次；不作用任何次生伤害。", "story": "测杆上的刻度原用于记录旧塔导线的残余震颤。每个被划去的刻度都提醒学徒不要凭声音判断安全。", "source": "废墟藏物点；测绘商人武器库存。"},
	"storm_conductor_armor": {"name": "断环绝缘衣", "slot": "armor", "set_id": "storm_conductor", "stats": {"defense": 3}, "effect": "旁路隔离：动作开始 charged 有效时，本人承受的原生雷主动作直接伤害减少 20%，纳入装备/遗器共享减伤桶；无 charged 不生效，不取消湿润/导电环境修正，不抵消火 tick 或 river。", "story": "衣上铜环故意没有闭合，边缘垫着厚树脂。旧说明最醒目的一行是“绝缘会磨损，勿把自己当避雷针”。", "source": "废墟藏物点；测绘商人护甲库存。"},
	"storm_conductor_accessory": {"name": "记闪小铃", "slot": "accessory", "set_id": "storm_conductor", "stats": {"speed": 8}, "effect": "数清雷拍：本人正常原生雷主动作至少产生一个有效命中后，额外获得能量 5，最多 2 次/战，不超过既有 100；proc 不触发，满能量不记成功次数。", "story": "铃舌被布包住，只在掌中传来轻响。测绘员用它数两阵雷之间的间隙，避免催促同行人冒进。", "source": "湿地藏物点；测绘商人饰品库存。"},
	"gale_runner_weapon": {"name": "折羽引风刃", "slot": "weapon", "set_id": "gale_runner", "stats": {"attack": 4}, "effect": "等风启程：本人完成 guard 后登记一个 4 全局行动标记，下一次原生风主动作直接伤害 +10%，使用即清；最多成功登记 2 次/战，同标记不重复登记/刷新。", "story": "刃脊曾是一片可收起的风向板。信使宁愿等风转向，也不愿把同行的伤者留在路边。", "source": "平原藏物点；驿路商人武器库存。"},
	"gale_runner_armor": {"name": "夹信轻斗篷", "slot": "armor", "set_id": "gale_runner", "stats": {"defense": 3}, "effect": "贴风收襟：动作开始有 wind_barrier 时，本人受到 delivery=ranged 的正常主动作直接伤害额外减少 8%，进入装备/遗器共享减伤桶；公共风障另乘 0.90，只有两项时为 0.90×0.92=0.828。覆盖远程普攻、技能和终结技，不作用近战或环境伤害。", "story": "斗篷内侧分成几个窄袋，让不同收信人的纸张不必挤在一起。空着的袋子仍留着名字，尚无回音。", "source": "平原藏物点；驿路商人护甲库存。"},
	"gale_runner_accessory": {"name": "晴野路哨", "slot": "accessory", "set_id": "gale_runner", "stats": {"speed": 8}, "effect": "平原熟路：本人每日第一次能够实际省费的、目的地为 plains 的合法移动 AP 成本 -1，最低 1；最多省 1 AP/日，不扩散给同行人。", "story": "路哨没有召风的能力，只能让远处同行者听见短促回应。磨亮的吹口来自很多个没能准时抵达的傍晚。", "source": "平原藏物点；驿路商人饰品库存。"},
	"stone_vow_weapon": {"name": "验层短锤", "slot": "weapon", "set_id": "stone_vow", "stats": {"attack": 4}, "effect": "听岩下锤：战斗所在地图格为 mountain 时，本人原生土直接伤害 +10%；在其他生态不生效，不改变地图地形。", "story": "锤柄刻着矿工辨认空层时的敲击次序。后来的持有者仍先听回声，再决定是否让同行人靠近。", "source": "山地藏物点；矿道商人武器库存。"},
	"stone_vow_armor": {"name": "承梁铆甲", "slot": "armor", "set_id": "stone_vow", "stats": {"defense": 3}, "effect": "守住支点：本人在根动作开始时已有 guard=true，则该动作对本人的直接伤害额外减少 8%；不延长 guard，不作用火 tick/次生包/river。", "story": "铆甲沿用了旧矿架的受力线，却比木梁轻得多。内衬写着同伴的警语：能撑一时，不是能撑永远。", "source": "山地藏物点；矿道商人护甲库存。"},
	"stone_vow_accessory": {"name": "回响铅垂", "slot": "accessory", "set_id": "stone_vow", "stats": {"speed": 8}, "effect": "确认余撑：本人完成 attack/skill/ultimate/guard 后，若开始快照 shield>0 且结算后仍存活，回复本人 MP 2，最多 2 次/战；本动作刚得到护盾不满足快照条件。", "story": "铅垂被磨得很短，放在掌心也能辨认微小摇摆。矿工用它确认支架是否还值得信任，而不是测量神意。", "source": "山地藏物点；矿道商人饰品库存。"},
	"dune_keeper_weapon": {"name": "刻量汲水杖", "slot": "weapon", "set_id": "dune_keeper", "stats": {"attack": 4}, "effect": "一线不散：战斗地图格为 desert 时，本人原生水直接伤害 +8%；仍先保留沙漠水伤 ×0.8 基础惩罚，不适用治疗。", "story": "杖身每一道刻痕都代表一次允许分出的水量。最下方留着一段空白，提醒领路人给未到的人留份额。", "source": "沙漠藏物点；沙路商人武器库存。"},
	"dune_keeper_armor": {"name": "双层遮砂袍", "slot": "armor", "set_id": "dune_keeper", "stats": {"defense": 3}, "effect": "隔开热浪：沙漠战斗中，本人受到原生火主动作直接伤害减少 10%；不减少 burning tick，不抗冥河，也不免除探索成本。", "story": "外层挡细砂，内层留出透气间隙，都是商旅多次改针的结果。袍角仍有没能完全洗掉的盐迹。", "source": "沙漠藏物点；沙路商人护甲库存。"},
	"dune_keeper_accessory": {"name": "划额水囊扣", "slot": "accessory", "set_id": "dune_keeper", "stats": {"speed": 8}, "effect": "按口取水：沙漠战斗中，本人原生水技能原 MP 成本>1 时，可在可支付判断前试算成本 −1、最低 1，最多成功 2 次/战；实际减费、技能合法提交才记双账本。原价 0 保持 0，不返 MP；例如原价 3、当前 MP 2，剩余额度有效时可以合法施放并支付 2。", "story": "囊扣上串着能逐个移动的小环，分水人每天亲手归位。它防的是慌乱中的浪费，不是沙漠本身。", "source": "沙漠藏物点；沙路商人饰品库存。"},
	"grove_mender_weapon": {"name": "分枝诊杖", "slot": "weapon", "set_id": "grove_mender", "stats": {"attack": 4}, "effect": "量好药力：本人现有治疗技能对自己或明确选中的存活队友的主治疗量 +8%；不提高药品、装备追加治疗或战后恢复，不治疗倒地目标。", "story": "分叉处绑着量取药汁的窄布条，杖身并不藏有神谕。医者说，先量清楚才能知道还有多少可以分给别人。", "source": "森林藏物点；草药商人武器库存。"},
	"grove_mender_armor": {"name": "青衬换药衣", "slot": "armor", "set_id": "grove_mender", "stats": {"defense": 3}, "effect": "留住药敷：森林战斗中，本人作为接收者获得的有效治疗量 +8%，含明确允许的装备追加治疗；不向同队其他接收者扩散，不反向增强施法者。", "story": "衣上的系带便于伤者自己换药，布面有许多不同颜色的补丁。每一块都来自物资短缺时仍被留下的小份余布。", "source": "森林藏物点；草药商人护甲库存。"},
	"grove_mender_accessory": {"name": "余药枝匣", "slot": "accessory", "set_id": "grove_mender", "stats": {"speed": 8}, "effect": "不弃余敷：本人主治疗技能对存活目标实际恢复正量HP且产生溢出治疗时，按结果顺序只选第一个溢出目标，给该自己/队友 min(溢出量×50%, 目标最大HP×3%) 的装备护盾，4 行动，最多 2 次/战；不再触发治疗或护盾事件链。", "story": "匣子内侧分成很小的格子，只够保存一次敷药的余量。盖上写着“先问伤者”，没有替他人承诺痊愈。", "source": "森林藏物点；草药商人饰品库存。"},
	"grave_wayfarer_weapon": {"name": "稳载配重杖", "slot": "weapon", "set_id": "grave_wayfarer", "stats": {"attack": 4}, "effect": "稳住既有重压：本人已经拥有且实际使用的原生 gravity 主动作直接伤害 +8%；不授予 gravity、不改普通攻击，不强化 river 环境吞噬包。", "story": "配重杖曾用于抬稳坍塌门楣，让搬运者不被骤然偏移的重量拉倒。杖尾没有神徽，只有几道检查松脱的划线。", "source": "废墟藏物点；旧道商人武器库存。"},
	"grave_wayfarer_armor": {"name": "渡途束载衣", "slot": "armor", "set_id": "grave_wayfarer", "stats": {"defense": 3}, "effect": "分摊牵坠：本人在废墟战斗，或本人开始快照已有 guard 时，所受原生 gravity 主动作直接伤害减少 12%；两个条件同中仍只减一次。绝不减免冥河/剧情包或保证免疫。", "story": "绑带把沉重物件分摊到肩背，便于普通人离开不稳的旧屋。穿戴说明特意把“承重”与“挡住死亡”写成两件不同的事。", "source": "废墟藏物点；旧道商人护甲库存。"},
	"grave_wayfarer_accessory": {"name": "未尽归途牌", "slot": "accessory", "set_id": "grave_wayfarer", "stats": {"speed": 8}, "effect": "重新系紧：本人完成 guard，若动作开始 slow>=2，则在本人正常消耗旧 slow 前额外减少 1、最低保留 1 个尚待消费的旧次数，最多 2 次/战；同一次装备减时总计最多 1。随后正常行动消费依 A.2 执行，不清其他状态。", "story": "牌面只记录等待确认的名字，不把失踪者直接算作亡者。送行人将它挂在衣内，提醒自己还有必须问清的路。", "source": "废墟藏物点；旧道商人饰品库存。"},
	"frontier_guard_weapon": {"name": "护沿短戟", "slot": "weapon", "set_id": "frontier_guard", "stats": {"attack": 4}, "effect": "依盾出手：本人动作开始时总 shield>0，则本人的普通攻击主伤害 +8%；只作用 attack，不提升技能、反应或护盾伤害。", "story": "短戟刻意缩短了刃外的突起，免得在拥挤营门勾住同伴衣物。旧持有人教的第一件事是给撤回的人让路。", "source": "平原藏物点；边境商人武器库存。"},
	"frontier_guard_armor": {"name": "补钉门卫甲", "slot": "armor", "set_id": "frontier_guard", "stats": {"defense": 3}, "effect": "护住伤处：敌方根动作开始时本人 HP<50% 最大值，该动作首个对本人的主伤害包减少 12%，最多 3 次/战；后续多段不重复，火 tick/次生包不占额度也不获此事件减伤。", "story": "补钉的位置绕开旧伤，而不是把伤痕遮得看不见。铠甲主人仍在招募名册旁留着空行，等待离散的人回来。", "source": "废墟藏物点；边境商人护甲库存。"},
	"frontier_guard_accessory": {"name": "交岗铜扣", "slot": "accessory", "set_id": "frontier_guard", "stats": {"speed": 8}, "effect": "报过平安：本人成功 guard 后额外获得能量 5，最多 2 次/战，不超过 100；不改变 guard 的原有能量，也不让道具/换人触发。", "story": "铜扣相碰的轻响曾是交岗时确认彼此还在的暗号。它没有调遣他人的权力，只约束佩戴者记得回应。", "source": "平原藏物点；边境商人饰品库存。"},
	"road_surveyor_weapon": {"name": "试路折刃", "slot": "weapon", "set_id": "road_surveyor", "stats": {"attack": 4}, "effect": "先试一步：本人每战首次主命中一个在动作开始时满 HP 的敌人，该首目标主伤害 +10%，最多 1 次/战；群攻只选首个符合目标，未遇满血目标不消耗。", "story": "折刃常先用来挑开无人检查的旧绳结。勘路人不愿让同行者用身体去试一条尚未确认的路。", "source": "平原藏物点；旧驿商人武器库存。"},
	"road_surveyor_armor": {"name": "图袋夹层衣", "slot": "armor", "set_id": "road_surveyor", "stats": {"defense": 3}, "effect": "先护图册：每战本人首次实际承受的敌方主命中伤害减少 15%，最多 1 次/战；不作用火 tick/次生包，不因预览、完全无效的攻击或换装刷新。", "story": "衣内夹层原是给怕雨的纸张准备的，后来也垫住了几次仓促躲避中的冲击。图册里仍有大片留白，没有被装备替人走完。", "source": "废墟藏物点；旧驿商人护甲库存。"},
	"road_surveyor_accessory": {"name": "待核里程盘", "slot": "accessory", "set_id": "road_surveyor", "stats": {"speed": 8}, "effect": "清点余力：本人作为实际交互者首次领取既有 field_cache（当前 cache），且基础结果确为装备时，回复本人 MP 3，每日最多成功 2 个不同藏物点。须通过佩戴者/实例日限额和双方地块 claim；非装备结果、MP 已满不发奖励，但合法访问 claim 照记，之后换人、转手或重载不能补领。", "story": "盘上的指针只能由人拨动，背面写着上次确认过的路段。它记录的是已经付出的脚程，不冒充预知前路的仪器。", "source": "平原藏物点；旧驿商人饰品库存。"},
	"oath_witness_weapon": {"name": "未开锋誓刃", "slot": "weapon", "set_id": "oath_witness", "stats": {"attack": 4}, "effect": "留下一次退让：本人首个主命中目标在开始 slow>0 且命中后仍活着，对其申请战意压低 10%，最多成功 2 次/战。降低目标下一次有效根动作全部直接主包出伤，动作结束移除；与三件 15% 取强不叠，等强/较弱不刷新、不记成功，不影响环境伤害或强制丢行动。", "story": "誓刃保留了一小段未开锋处，用来提醒持有者仍有收手的选择。它见证过签字，也见证过签字未能守住的夜晚。", "source": "废墟藏物点；旧约商人武器库存。"},
	"oath_witness_armor": {"name": "证词护心衣", "slot": "armor", "set_id": "oath_witness", "stats": {"defense": 3}, "effect": "不让恐惧催促：敌方根动作开始时本人 slow>0，则该动作首个对本人的主伤害包减少 8%，最多 3 次/战；不解除 slow、不改变其速度惩罚，不对同伴生效，不削减火 tick/次生包/river。", "story": "护心衣内夹着抄写过多次的旧条款，破损处并未被涂去。见证者宁愿让后来人知道约定有多脆弱。", "source": "平原藏物点；旧约商人护甲库存。"},
	"oath_witness_accessory": {"name": "双名见证章", "slot": "accessory", "set_id": "oath_witness", "stats": {"speed": 8}, "effect": "给旁人留盾：本人完成 guard 后，给一名最低血量比例存活队友最大 HP 3% 的装备护盾，4 行动，最多 2 次/战；明确排除本人，无队友不改为自盾，不延伸到异地/候补。", "story": "见证章留着两个刻名位置，只有互相听见承诺的人才会填满。空着的一侧不是已经兑现的和平。", "source": "平原藏物点；旧约商人饰品库存。"},
	"trail_blade": {"name": "巡路短刃", "slot": "weapon", "set_id": "", "stats": {"attack": 4}, "effect": "无套装、无新增特性、无触发；只保留既有攻击加值，不算任何新套的一件。", "story": "刃背磨平，方便切开捆扎旅物的细绳。巡路人留下它，是希望后来者少在琐事上受伤，并非承诺道路安全。", "source": "既有初始装备/初始库存及既有商人装备渠道，不追送新副本。"},
	"padded_coat": {"name": "夹棉旅衣", "slot": "armor", "set_id": "", "stats": {"defense": 3}, "effect": "无套装、无新增特性、无触发；只保留既有防御加值，不获得免费减伤事件或护盾。", "story": "夹层棉絮来自几次不同的修补，衣角留有赶路时蹭出的灰。它保护的是凡人的身体，不把伤势当作已经治愈。", "source": "既有初始装备/初始库存及既有商人装备渠道，不改旧解锁条件。"},
	"lamp_charm": {"name": "旧灯护符", "slot": "accessory", "set_id": "", "stats": {"speed": 8}, "effect": "无套装、无新增特性、无触发；只保留既有速度加值，不自动安魂、回复、照亮地图或生成灯铢。", "story": "护符里的小灯早已熄灭，外壳却被握得很亮。维洛丹的旅人有时留着它，只为记得仍要找到愿意听见自己名字的人。", "source": "既有初始装备/初始库存及既有商人装备渠道，不变成任务奖励放大器。"},
}

const SETS = {
	"ember_warden": {"name": "灰烬守望", "terrain": ["forest"], "story": "森林控火，先处理湿润才可依自然规则点燃，承担持续火焰同样伤及己方的代价。维洛丹林工曾将可拆火钩、隔热衣和封口炭筒一起交给守夜人；它们留下的是控火经验，不是免焚的祝福。主要来源为森林主题藏物点与林缘商人装备库存。", "two": "二件「识火」：本人原生火直接伤害 +10%；本人 burning 环境伤害额外减少 10%。与林钩/守夜衣分别加算为 +18% 火增伤、25% 火 tick 减免，再与遗器合入各自共享 50% 桶；不把全队变成耐火者。", "three": "三件「限燃开口」：非雨森林的本人正常火实际命中后，若开始有显式 wet、无 frozen/charged 且无剧情 river，可移除 wet，最多成功清湿 2 次/战；本次仍用湿润快照，且明确禁止同动作点燃。已有 frozen 时先按自然火融冰保留湿润，不执行清湿；charged 存活时不清湿。三件不创建有限燃烧、不缩短旧火场，也不对普通火的合法点燃计套装次数；后续带点燃效果的火技能满足干燥森林条件时，才按原规则点燃并持续到战斗结束。"},
	"tide_weaver": {"name": "潮痕编织", "terrain": ["swamp"], "story": "佩戴者用水技能让仍在燃烧的战场变得湿润后，可提供有每日和每战限额的小额援护。渡口帮工和迁徙者将旧水袋布重新织成装备，目的只是争取撤离时间；故事不判定任何具体救援已经成功。主要来源为沼泽/湿地主题藏物点与渡口商人装备库存。", "two": "二件「顺流施术」：本人原生水直接伤害 +8%。带湿润效果的水技能照常建立/刷新 wet，已有燃烧保留；湿润本身无需装备，也不消耗套装次数或物品造场名额。", "three": "三件「递出湿布」：本人用带湿润效果的正常水技能实际命中，行动开始已有 burning 且无 wet，本次水技能实际施加 wet 后，给本人及一名最低血量比例存活队友各最大 HP 4% 的装备护盾，四个完整后续行动；最多 2 次/战且 2 次/日，两套周期内均须通过佩戴者与所有参与 UID 的双账本。无队友只给本人，不合并两份；刷新已有湿润、他人施加湿润、proc 或无燃烧时不触发。双方均得到 0 盾时不记成功次数；盾额耗尽不妨碍本人继续施加湿润。"},
	"rime_path": {"name": "霜径行者", "terrain": ["mountain", "swamp"], "story": "在湿润底层上叠加双方都有代价的短时冰面，再选择破面保水，而不是凭空冻结整张地图。高地搬运者将有齿工具和防寒绑带借给雨季赶路人，用有限控制交换稳定输出。主要来源为山地/湿地主题藏物点与山道商人装备库存。", "two": "二件「借水结面」：本人原生冰直接伤害 +8%；正常冰动作实际主命中，开始已有湿润、无 burning 且river=false时，提出 frozen 四行动新建/刷新，最多成功 3 次/战。保留 wet、charged 和其他合法标记；与全部装备/遗器提案共同仲裁。刷新维持同一 episode_id，不额外给全员 slow。", "three": "三件「破面留水」：本人正常冰主命中开始已有 frozen，该动作冰直接伤害额外 +10%；命中后可移除 frozen、保留仍有效 wet/charged，并向首个仍存活的主命中目标申请 slow=2，最多成功破面 2 次/战。若无有效命中不破面，无存活目标则仅移除冰；不把 slow 叠成 +2。破面不重新设湿润寿命，同一根动作不再提出二件结面。"},
	"storm_conductor": {"name": "引雷测绘", "terrain": ["ruins", "swamp"], "story": "在湿润上建立双方共用的短时导电环境，借个人雷击防护与有限增伤应对敌方同样获益的代价。废墟测量员把导线、绝缘垫与计数铃配成一组，用来摸清危险，不是代表天空的权柄。主要来源为废墟/湿地主题藏物点与测绘商人装备库存。", "two": "二件「把湿润接成电荷」：本人原生雷直接伤害 +8%；正常雷实际主命中，开始已有湿润、无 burning 且river=false时，提出 charged 四行动新建/刷新，最多成功 3 次/战。wet 不被消费，其原期限不被改成一次新施加，但有效湿润至少托底至 charged 退去；charged 有独立到期；双方后续雷电环境桶均 +0.10，不因命中取消。", "three": "三件「标定第二落点」：本人正常雷动作开始已有 charged 时，本根动作雷直接伤害额外 +10%，最多成功 2 次/战；该组确有有效直接伤害变化时记一次，群体/多段不多记。仅佩戴者受益，队友与敌人只享公共环境修正；不生成第二目标或额外伤害包。"},
	"gale_runner": {"name": "逐风信使", "terrain": ["plains"], "story": "平原省力、用双方远程直接减伤换取准备时间，再撤下风障转成自己的下一次风技窗口。平原信使把可折的风标和信函夹层做进随身装备，不保证道路通畅或信件已经送达。主要来源为平原主题藏物点与驿路商人装备库存。", "two": "二件「暂借背风」：本人原生风直接伤害 +8%；正常风实际主命中后、river=false时提出 wind_barrier 四行动新建/刷新，最多成功 3 次/战。双方远程直接伤害公共 ×0.90，敌人同样获益；近战、火 tick、治疗不受影响。", "three": "三件「收帆再走」：本人 guard 开始已有 wind_barrier，则完成后移除该全场标记，获得本人最大 HP 6% 装备护盾，并登记本人下次原生风主动作增伤 +12% 的四行动标记，最多 2 次/战。已有未消费三件标记不重登/刷新；二件只被正常风命中触发，guard 不会重建风障。护盾按新增比例 floor，0 不强制补 1；成功移除与登记仍为真实状态变化。"},
	"stone_vow": {"name": "山根誓约", "terrain": ["mountain"], "story": "山地土系与防守支撑，根掩为双方提供独立直接减伤，佩戴者再以既有 guard 组织个人护盾。矿工把支架尺寸写成誓约，要求每个人先确认承重再让别人下井；矿道遗器不证明某次被困者已经获救。主要来源为山地主题藏物点与矿道商人装备库存。", "two": "二件「托住山根」：本人获得护盾量 +10%；森林/山地/沼泽正常土实际主命中，开始无 burning、river=false且后置仍可承接时，提出 root_cover 四行动新建/刷新，最多成功 3 次/战。双方所有直接主包公共 ×0.95，无需 guard，不自动发盾、不附防御回血。", "three": "三件「先立支架」：本人 guard 开始已有 root_cover，完成后获得本人最大 HP 8% 装备护盾，四行动，最多 2 次/战。它不是全队土终结技，不改变其他人的 guard 或 shield。"},
	"dune_keeper": {"name": "沙海留泉", "terrain": ["desert"], "story": "有限缓和沙漠水资源与移动压力，湿润只影响当前战斗，不改变沙漠地貌。护送商旅的普通人将每次用水划在器具上，给后来者留下的是节制规则，而不是不竭之泉。主要来源为沙漠主题藏物点与沙路商人装备库存。", "two": "二件「留给下一程」：本人在沙漠的原生水直接伤害 +8%；本人每日前两次实际可省费的合法沙漠目的地移动 AP −1、最低 1，最多省 2 AP/日，佩戴者与参与实例双限，不影响同行者。", "three": "三件「只开一囊」：沙漠中本人正常水实际主命中后，获得本人最大 HP 3% 装备护盾，四行动，最多成功 1 次/战。带湿润效果的水技能照常建立/刷新 wet，无装备次数限制，已有 frozen/charged 不阻止保留湿润。另在沙漠 guard 且开始已有湿润时回复本人最大 HP 5%，最多 2 次/战；水后薄盾和 guard 回复分别记账。无原生水能力仍不能凭装备施法。"},
	"grove_mender": {"name": "青枝医者", "terrain": ["forest"], "story": "森林治疗和有限溢出护盾，通过现有治疗技能扶持存活队友；没有新治疗按钮，也没有起死回生。林缘医者在难民营间交换草药包和包扎办法，把未归者的名字记在袋角而非当作救治成功记录。主要来源为森林主题藏物点与草药商人装备库存。", "two": "二件「林间续敷」：本人主治疗技能对自己/存活队友治疗量 +10%，与诊杖合计 18%；森林主治疗实际恢复正量HP，开始无 burning、river=false且后置可承接时，提出 root_cover 四行动新建/刷新，最多成功 3 次/战。其公共直接伤害 ×0.95 同样保护敌人，无需 guard，不因防御回血。", "three": "三件「递药而不夺命」：本人主治疗开始已有 root_cover且实际恢复正量HP，主治疗后额外回复一名最低血量比例存活队友最大 HP 3%，最多 2 次/战。排除本人，无受伤合法队友不触发；不要求为主治疗原目标。追加为 proc，不能触发装备或遗器治疗、造场、返还监听，也不能触发枝匣。"},
	"grave_wayfarer": {"name": "渡途行者", "terrain": ["ruins"], "story": "废墟行走、普通重力承载稳定和有限防守；只增强角色原本拥有的重力技能，不赋予死神的身份或能力。送行人使用配重、护额和记名片搬运遗器、辨认归途，器具无权决定灵魂去向。主要来源为废墟主题藏物点与旧道商人装备库存。", "two": "二件「凡人的承载」：废墟战斗中本人承受普通攻击主伤害减少 8%；本人原生 gravity 技能 MP 成本 −1，在可支付判断前试算，正原价最低 1、原价 0 保持 0，最多成功减费 2 次/战；无实际少付不占额度，不产生返还。非重力角色仍可用废墟防护，不强迫获得元素。", "three": "三件「不越界的支撑」：本人原生 gravity 技能本就含 slow，且主命中后目标仍活着，可将首个有效目标本次技能的 slow 申请额外 +1、最高 3，最多 2 次/战；已有更长 slow 取 max，不降为 3，原来无 slow 不能添加。另本人 guard 后获最大 HP 6% 装备护盾、四行动、最多 2 次/战。两项分别记双账本；river=true 时三件新增触发全部停用，不干涉已有状态的正常存续。"},
	"frontier_guard": {"name": "边境守备", "terrain": ["plains", "ruins"], "story": "独立于元素环境的护盾维护，先 guard 建立薄盾，真正被敌方打破后才获得一次补盾机会。边境守卫把可反复检视的扣带交给新来者，让短暂守住队伍成为本领，而不是宣称边境已恢复和平。主要来源为平原/废墟主题藏物点与边境商人装备库存。", "two": "二件「先护自身」：本人护盾获得量 +10%；本人 guard 后获得最大 HP 4% 装备护盾，四行动，最多 3 次/战。只给本人，不给其他人 guard；增幅与遗器共享 +30% 桶。", "three": "三件「破后补钉」：敌方正常主动作使本人开始非零的总 shield 在整组结算后降至 0，且本人仍存活，登记一个四行动补钉标记，最多 2 次/战。后来本人下一次 guard 消费，获最大 HP 8% 装备护盾、独立四行动寿命；如该次二件也有额度，两份基础盾 4%+8%=12% HP，再对各独立来源按同一接收者增幅一次计算并 floor，不施加统一盾池上限。已有补钉不重登/刷新，过期不返还额度。"},
	"road_surveyor": {"name": "旧驿勘路", "terrain": ["plains", "ruins"], "story": "用个人移动折扣与既有藏物点基础装备结果的有限补给，支持探索路线规划，不新增箱节点、任务奖励、世界施法或全队免费行动。旧驿路勘测者把绕路原因和未查明地点记在图角，不因标记落笔就宣告道路已经安全。主要来源为平原/废墟主题藏物点与旧驿商人装备库存。", "two": "二件「少走虚步」：本人每日前两次实际可省费的合法陆地移动 AP −1、最低 1，最多省 2 AP/日。混搭平原/沙漠减免时仍按统一顺序逐人结算，各来源双重记账，不返还已付移动、不改变可达性。", "three": "三件「归档再走」：本人作为交互者首次领取既有 field_cache，且该节点基础结果是装备，恢复本人 AP 1，不超过 AP 上限，每日最多成功 1 次；佩戴者与本次参与的每个 UID 均受日限额与地块 claim。药品等非装备结果不触发，不增装备件数、品质或权重，也不降低交互费。满 AP 不发奖励、不耗成功次数，但角色/所有来源访问 claim 与节点永久领取结果仍提交。"},
	"oath_witness": {"name": "停战见证", "terrain": ["ruins", "plains"], "story": "对已有迟缓的敌人施加下一有效动作出伤减益，利用 guard 指定一名同场队友获得援护；不命令敌人停手，不读取命中、暴击或闪避系统。旧停战见证人携带的是会被违反的约定，力量来自有限自制与互助，而非战神对亡者的支配。主要来源为废墟/平原主题藏物点与旧约商人装备库存。", "two": "二件「一人一份援护」：本人 guard 后，给一名最低血量比例存活队友登记援护，最多成功 2 次/战。此后首次敌方根动作对其造成有效直接主伤害时，该动作整组对其主包减伤 12%，组尾消费一次；未受击则到该队友下一次有效动作结束移除。无伤害转移、不代替 guard、不减火 tick/proc/剧情包；同类取强不叠、不续期。本人已有未消费援护不重登或另选人；原来源离场/倒地只停止新触发，既有标记保留。", "three": "三件「约束而非宰制」：本人首个主命中目标开始 slow>0 且命中后存活，申请战意压低 15%，最多成功 2 次/战，目标下一有效动作结束移除；与武器取较强 15%，不是 25% 或两个回合。另本人 guard 后，若本次二件援护确实新登记且该队友开始 slow>=2，将其 slow 减 1、最低 1，最多 2 次/战；不清空、不降低 ×0.7 惩罚、不发免费行动。两项独立记账。"},
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
