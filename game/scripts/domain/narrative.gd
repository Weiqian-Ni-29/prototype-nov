extends RefCounted

const Catalog = preload("res://scripts/domain/catalog.gd")
const Nodes = preload("res://scripts/domain/map_nodes.gd")
const LegacyOutcomes = preload("res://scripts/domain/legacy_companion_outcomes.gd")

const CHARACTER_BEHAVIOR = {
	"cen": ["话少，护短，宁愿丢掉军职也不肯只救本族", "我跟你走。到时候要是得撤，先告诉我出了什么事。", "先找一条能撤的路。", "往旁边站站。事情办完了，也得让后面的人有路走。"],
	"lorne": ["机智健谈的老信使，拿官威取乐，对河口旧友放心不下", "成。路上要是碰见从河口来的人，叫我一声。我有个老朋友还困在那儿。", "干粮分开装，免得一摔全没了。", "歇够了就接着找路。将军坐着等人来抬，咱们送信的可没那个福气。"],
	"eve": ["耐心，诊断时直言，敢违抗军令", "我跟你走。说好了，治伤得听我的。伤员是哪边的人，我都照样治。", "有伤就说，别拿披风盖着。", "先看看还有没有人需要止血。别光顾着听谁吵得响。伤得重的人，有时连喊都喊不出来。"],
	"grit": ["寡言记仇，珍视使者与龙族声望，不肯轻易放过敌人", "我跟你去。碰上黑旗军，叫我。他们杀了我的使者，我还没跟他们算账。", "重物我来扛，仇我自己记。", "活下来的未必肯道谢。以前挡过我的人，别以为停了战就能和我做朋友。"],
	"ember": ["守约索价，以战火炫耀力量，想独占火源与军炉", "可以。同行归同行，哪天要我烧城，咱们得另谈。", "取暖和烧城是两个价。", "火熄了，报酬可不会跟着消失。许过什么，我记得。"],
	"tide": ["熟悉河道，尖锐不让步，善用闸工与船家的交情", "一起走吧。沿河的路听我的，水可不会因为谁嗓门大就绕着走。", "扎营别贴着河岸。", "先离开低处。水还没退呢。让那些人争功去，咱们先上高处。"],
	"frost_archer": ["固执记仇，护着供养弓队的四村，把粮食也看作权力", "我跟你走。不过给我送粮的那四个村子，我还得管。别指望我把他们丢下。", "答应别人的干粮，别饿了就忘。", "要分东西，先看看手里的东西够几个人。我不会拿自己人的饭，换所有人一句好话。"],
	"storm_caller": ["自负好胜，迷恋破舰雷术，既想遇见对手又不肯被超过", "好，路上有硬茬先叫我。可别拿劈柴这种事来试我的雷。", "别碰杖尖，火花有时会乱窜。", "收手倒容易。难的是下回还能不能劈得更准、更狠。"],
	"wind_runner": ["爱赌爱出风头，擅长伪装诱敌，不甘心做稳妥的后手", "我跟你。真要有人先跑出去，让我来。", "找我就朝上风处喊。", "趁敌人还没反应过来，咱们先看看哪条路能走。"],
	"stone_guard": ["倔强，护工匠的命，绝不许军官把工人当爆破耗材", "我去。要我撑住出口可以，要我把人封在里面不行。", "绳子起毛就换。", "先检查脚下。争功的人踩塌支架，也不会比别人摔得轻。"],
	"ironforge": ["好胜暴躁，仍爱造兵器，想亲手胜过自己最出名的破城弩", "我跟你走。捡到刻了我印记的兵器，先留给我看看。", "别拿好刀撬石头。", "坏了能修，拆了也能再造。可别拿外行的敲法糟蹋好铁。"],
	"granite": ["严肃守旧，偏袒城内士族，也想握住自己的守门兵", "我可以跟你走。可城门该交给谁管，我们迟早得谈。", "守门的人得知道听谁的。", "门内的人要安稳，门外的人要进来。真轮到我选，我先顾城里。"],
	"mistleaf": ["冷静寡言，善算撤离时辰，危急时敢舍弃未撤出的队伍", "走吧。我替你看后路，到了非撤不可的时候，可别等所有人都赞成。", "过桥前，先找找哪儿水浅。", "别都挤在同一个出口。哪怕只剩最后几个人，也得有人看着后面。"],
	"willow": ["和气精明，偏袒本族，惯于拿旧盟友的信任换利益", "一起走吧。山口那几位商人，你有认识的吗？路上说不定得找他们帮忙。", "先吃饭，再谈价。", "朋友多不是坏事。只是下回求人之前，最好想想对方想从你这儿拿什么。"],
	"ashhorn": ["彬彬有礼，把粮食和人的困境用来买兵争权", "乐意同行。路上有什么买卖，记得也让我听听。", "粮车的去向，比军旗有意思。", "现在谈价，通常比开打以前贵。你看，我并不总是催人动手。"],
	"oathguard": ["寡言严苛的恶魔，按原话履约，寸步不让报酬与关门权", "这一路我答应护着你们。谁掉队了，我会回头找。要我守一座城，那得另谈。", "说清守多久，临时加的事另算。", "先前答应的，我不会少做。没答应的，别用一句应该就添进来。"],
	"highdrake": ["庄重自负，愿护山下盟友，也想推翻长老的禁令争席位", "我跟你走。山下有人来求援，我还是会去，不管长老怎么说。", "帐篷别挨着搭，留块能落脚的地方。", "别替别人决定该不该谢我。肯一起守山口，比说好话有用。"],
	"cloudscale": ["热烈好奇，享受护航声望，也珍惜随时飞走的自由", "好啊，一起走。先说好，别替我答应给哪支军队办事。", "听见铜铃急响，我就想去河边。", "地上绕路太慢了。可真要我带人飞，也得先问对方敢不敢睁眼。"],
	"longroad": ["圆滑幽默，善于两面交易，遇到灭口威胁先保自己", "一起走吧。关口要是有人乱收钱，让我先跟他聊聊。", "问路我在行，信不信你自己定。", "别因为做成一桩买卖，就以为下一桩也是同一个价。"],
	"fieldmedic": ["严厉的战地医师，敢从军官手里抢伤员，憎恶把病人当兵器", "走。有人拿军衔插队，我骂起来你别劝。", "手发抖就来找我。", "能说话的伤员，就问本人想去哪儿。旁人替他答，我可不听。"],
	"siltguard": ["多疑护城，明知自己有罪，仍拿秘密谋兵权和活路", "我跟你去。城里的事，别替我答应任何人。", "水声一变，就往高处走。", "别急着问谁该受赏。先看看谁还带着兵，谁已经没得选了。"],
	"seasons": ["四季神的化身，慷慨任性，既赐收成也肯让一谷挨冻", "我借这副模样走一段。嫌路长了，可不一定陪你走到底。", "唱一段田里的歌吧。", "你们盼着雪化，可路一通，兵车也能上山。来求我之前，先想想这事。"],
	"earth_god": ["大地神的化身，沉默专断，肯给退路，也会把不服从者留在山外", "我沿这条路走一段。哪座山要动，由我决定。", "脚下的石头正在动。", "人走得急，山可不急。催我，不会让路短一寸。"],
	"sky_god": ["天空神的化身，骄傲任性，愿赐顺风，也会因遭欺骗迁怒整条河", "我就用这副样子跟你走一段。风想转向时，你会先听见。", "旗杆挪开，我要看云。", "顺风可以给，下一次却不一定。别把我的一时高兴当成你们的规矩。"],
	"snowforge": ["强硬敢赌，护旧部，反对军官专权，也想有自己的工坊和追随者", "走吧。兵器能再打，人死了可不能拿铁补上。", "把重东西放低，跑起来稳些。", "活人先走，兵器后搬。舍不得放手的，叫他自己来背。"],
}

const BACKGROUNDS = {
	"cen": "议会只准我带精灵出城。我打开城门，丢了军职。",
	"lorne": "我替赫辛送过求援信。援兵没来，他还守着河口。",
	"eve": "守军只肯给自己人药。我把两边的伤兵都抬进了医院。",
	"grit": "黑旗杀了我的使者。我报复时也压塌了难民的堡。",
	"ember": "我收下祖火替守军解围，连俘虏也烧了。",
	"tide": "我亲眼见泽栅开闸。洪水淹了俘虏营，城主却怪天上的风。",
	"frost_archer": "霜谷缺粮时，我抢了军粮，先分给供养弓队的四个村子。",
	"storm_caller": "我为一桩渡河买卖试雷，沉了三艘船。",
	"wind_runner": "我用假军令送走了主力，也把殿后的队伍留给了追兵。",
	"stone_guard": "军官要我炸山路。矿里还有人，我先把他们带了出来。",
	"ironforge": "黑旗的破城弩是我造的。射中我弟弟的箭也有我的印。",
	"granite": "我从备用门接进士族家属，门外的守军不知道那条路。",
	"mistleaf": "为了挡追兵，我下令断桥。另一头还有自己人。",
	"willow": "我熟悉山下的猎径，也知道城邦愿拿什么换它们。",
	"ashhorn": "我用粮买通赫罗，让他放弃了城外防线。",
	"oathguard": "城邦把堡给我换守到休战。约我守完了，堡归我。",
	"highdrake": "我违令下山救人，也压塌了几户人家的屋子。",
	"cloudscale": "我给翻船的人找了条小河道，用铜铃指路。",
	"longroad": "围城时，我把各缺一段的真消息卖给三个领主，再拿钱出城。",
	"fieldmedic": "战鼓逼伤兵再上阵。我废了下令的将军一只手。",
	"siltguard": "我开闸淹死了俘虏。城主怪风，我收下了守备的职位。",
	"seasons": "我让冬天提早，冻死粮虫，也冻坏了邻谷的庄稼。",
	"earth_god": "他们挖穿山腹还来求我挡兵。我震塌了山，也困住了矿工。",
	"sky_god": "军舰冒挂白布骗我停风。我让风回来，也掀翻了民船。",
	"snowforge": "我用军械库的兵器换困在矿道的人先走，旧部也被追罚。",
}

# Only the traveler receives these hints. The identity remains unknown until the final battle.
const HERO_LINES = {
	"ember": "你那样抬手，我在冥界见过。",
	"storm_caller": "你脚步轻得很，像我在冥界见过的人。",
	"ashhorn": "你让我想起冥界的一位贵人。",
	"oathguard": "我在冥界等过一个像你的人。",
	"seasons": "从前也有人问我，雪底下还有谁。",
	"earth_god": "从前有人在山摇之前叫住我，声音像你。",
	"sky_god": "我见过能叫神停手的人。你像他。",
}

const PERSONAL_QUESTS = {
	"cen": {
		"title": "岑枝 · 最后一队从哪里走",
		"text": "再有人困在城里，我们是分队走小巷，还是留一队守北门？",
		"personal_a": {"label": "我陪你探两条小巷。", "response": "两声短哨，各队就撤。", "ending": "岑枝准备分两队护送城里的人。"},
		"personal_b": {"label": "你守北门，我接应。", "response": "最后一队过门就吹哨。", "ending": "岑枝打算亲自守到最后一人出城。"},
		"pending": "岑枝仍在寻找当年的弓手。",
	},
	"lorne": {
		"title": "洛恩 · 河口的缺角灯",
		"text": "赫辛和伤员困在磨坊。先找援手，还是先撤能走的人？",
		"personal_a": {"label": "先去找老兵。", "response": "往南坡走，他们认得我。", "ending": "洛恩准备去南坡找老兵救援。"},
		"personal_b": {"label": "先撤能走的人。", "response": "我带路，你看着队尾。", "ending": "洛恩打算先沿河撤人，再想办法接伤员。"},
		"pending": "磨坊的缺角灯还亮着，洛恩还没定下怎么救人。",
	},
	"eve": {
		"title": "伊芙 · 药棚外的枪",
		"text": "守军愿护医院，却要带走伤愈的人。村里的药棚能接人，只是床少。",
		"personal_a": {"label": "谈护卫，只守院外。", "response": "谁要进来抓人，我拦着。", "ending": "伊芙准备请守军守在院外，同时拦下征兵。"},
		"personal_b": {"label": "教人抬担架，送去药棚。", "response": "我先教他们怎么抬伤得最重的人。", "ending": "伊芙开始筹备人手，把伤员分送到村里的药棚。"},
		"pending": "伊芙还在为医院找帮手。",
	},
	"grit": {
		"title": "砾牙 · 先飞向哪座堡",
		"text": "杀我使者的人可能在北堡。旧堡也有人等我搬开石头。",
		"personal_a": {"label": "先去旧堡帮忙。", "response": "让他们指给我看哪块石头能搬。", "ending": "砾牙先去清理旧堡，凶手可能已经离开北堡。"},
		"personal_b": {"label": "先找弩手问线索。", "response": "问清他亲眼看见了什么。", "ending": "砾牙先去追查凶手，旧堡的人仍在等。"},
		"pending": "砾牙还在犹豫先往哪座堡飞。",
	},
	"ember": {
		"title": "弥烬 · 祖火还是军炉",
		"text": "守军想赎回祖火。我可以留下它，也可以拿它换军炉。",
		"personal_a": {"label": "留下祖火。", "response": "我毁掉引火印，只卖点火的本事。", "ending": "弥烬决定独占祖火，靠替人引火挣钱。"},
		"personal_b": {"label": "拿祖火谈军炉。", "response": "先看看那座炉子值不值。", "ending": "弥烬留下引火印，打算用祖火换军炉。"},
		"pending": "弥烬还没决定怎么用那支祖火。",
	},
	"tide": {
		"title": "澄汐 · 下一次水涨以前",
		"text": "原来的闸兵还守着绞盘。先锁住水闸，还是先把下游的人带上高地？",
		"personal_a": {"label": "先去锁绞盘。", "response": "我认识能带我们上闸楼的人。", "ending": "澄汐准备请工匠帮她控制水闸。"},
		"personal_b": {"label": "先撤下游的人。", "response": "去找船家，先把人送上坡。", "ending": "澄汐先去接下游居民，水闸仍由城主的人把守。"},
		"pending": "澄汐还在打听下游的水势。",
	},
	"frost_archer": {
		"title": "霜弦 · 一仓粮换多少弓",
		"text": "四村肯派弓手，但要优先分粮。用公仓分粮能多帮几个村，山口却少人守。",
		"personal_a": {"label": "按旧约，请弓手守山口。", "response": "答应四村的粮，我会留着。", "ending": "霜弦准备履行旧约，换四村派弓手来。"},
		"personal_b": {"label": "用公仓谈分粮。", "response": "我出粮，他们出车，分法当面谈。", "ending": "霜弦准备和公仓合运粮食，暂缓增援山口。"},
		"pending": "山口缺弓手，霜弦还没定怎么分粮。",
	},
	"storm_caller": {
		"title": "闻霆 · 谁敢接第二道雷",
		"text": "我想教人破舰雷术。学会的人或许比我强，也可能拿它打民船。",
		"personal_a": {"label": "收学徒，到空水面练。", "response": "谁能胜过我，我认。", "ending": "闻霆打算找学徒，在空水面试雷。"},
		"personal_b": {"label": "先把雷术留在手里。", "response": "想破封锁的人，来跟我谈价。", "ending": "闻霆决定独占破舰雷术，按战事收费。"},
		"pending": "闻霆还没决定是否收徒。",
	},
	"wind_runner": {
		"title": "岚翎 · 这回谁当诱饵",
		"text": "我想把搜粮队引去采石场。他们认得我，得找生面孔，或者我直接露面。",
		"personal_a": {"label": "找愿意假扮信使的人。", "response": "先把风险说清，再安排接应。", "ending": "岚翎准备找自愿的诱饵，用假军令引敌。"},
		"personal_b": {"label": "你露面引敌，我接应。", "response": "我往采石场跑，你看好退路。", "ending": "岚翎准备亲自引开搜粮队。"},
		"pending": "搜粮队还在往村里走，岚翎尚未定下诱饵。",
	},
	"stone_guard": {
		"title": "石垣 · 把出口撑住",
		"text": "城邦肯修主路，军官却还要炸山。修旧出口得向营地借梁。",
		"personal_a": {"label": "回主路，先拦军官。", "response": "矿里的人没走完，谁也别点火。", "ending": "石垣准备留在主路，护着工匠撤出来。"},
		"personal_b": {"label": "借梁，修旧出口。", "response": "先给借梁的人另搭个棚。", "ending": "石垣决定借梁修旧出口，也帮营地另搭棚子。"},
		"pending": "石垣还在找能撤出矿工的路。",
	},
	"ironforge": {
		"title": "铎火 · 拆弩还是争炉",
		"text": "旧搭档肯教人拆弩。城里愿给我炉子，条件是替他们再造一架。",
		"personal_a": {"label": "先教人拆旧弩。", "response": "我做钩锤，从旧弩上练。", "ending": "铎火准备收徒，教人拆自己的旧弩。"},
		"personal_b": {"label": "去谈独立的工坊。", "response": "炉子得归我管，否则不开工。", "ending": "铎火打算争取自己掌管工坊和买卖。"},
		"pending": "铎火还没选新炉还是拆弩。",
	},
	"granite": {
		"title": "岩钉 · 谁守备用门",
		"text": "议会愿还我门卫，仍要士族先走。城南军官也愿给兵，却要先占门楼。",
		"personal_a": {"label": "找旧门卫，讲清谁先走。", "response": "士族优先，我会明说。", "ending": "岩钉打算找回旧门卫，维持士族优先的规矩。"},
		"personal_b": {"label": "见城南军官，谈妥守门的人。", "response": "先谈谁管钥匙，再让他们过门。", "ending": "岩钉打算借城南的兵与议会争门楼。"},
		"pending": "岩钉还没决定把门交给谁守。",
	},
	"mistleaf": {
		"title": "沐叶 · 桥头留下谁",
		"text": "守桥能挡追兵，可断桥会留下人。改用船渡，就得多留人护岸。",
		"personal_a": {"label": "留哨手，再准备断桥。", "response": "三声急哨，就是还有人没过。", "ending": "沐叶准备在桥两头布哨，保留断桥的手段。"},
		"personal_b": {"label": "找船工，改用绳渡。", "response": "靠船撤，岸边得有人守。", "ending": "沐叶打算先架绳渡，增加护岸人手。"},
		"pending": "沐叶还在想下一次该怎么守桥。",
	},
	"willow": {
		"title": "暮柳 · 借你们的威风换地",
		"text": "我把猎径卖给城邦，换精灵免征兵。现在想拿另一条猎径换回林地。",
		"personal_a": {"label": "拒绝担保，提醒守路人。", "response": "他们住旧磨棚旁，你自己去说。", "ending": "暮柳没拿到担保，山下的守路人有了示警的机会。"},
		"personal_b": {"label": "撤掉猎径，用木料谈。", "response": "木料和商路都能谈，地不能少。", "ending": "暮柳准备改用木料和商路换林地。"},
		"pending": "暮柳还在拿猎径当换地的筹码。",
	},
	"ashhorn": {
		"title": "灰角 · 用粮买来的边军",
		"text": "赫罗又缺粮了。我想拿粮换他一半的兵，你肯替我担保吗？",
		"personal_a": {"label": "拒绝替赫罗担保。", "response": "那我多付一些，自己筹粮。", "ending": "灰角准备独自去筹粮买兵。"},
		"personal_b": {"label": "支持谈判，公开旧账。", "response": "让他带能派的人来谈。", "ending": "灰角带着有条件的担保去谈粮，也得公开赫罗的旧账。"},
		"pending": "灰角正在盘算兵和粮的价钱。",
	},
	"oathguard": {
		"title": "契岑 · 过堡要付粮",
		"text": "两军都想借道，旧雇主还想拿回堡。收费开门，还是闭门等他们承认归属？",
		"personal_a": {"label": "卸重弩，交粮过堡。", "response": "一批一车粮，两军同价。", "ending": "契岑打算按批收粮，亲自查过门的武器。"},
		"personal_b": {"label": "闭门，先谈归属。", "response": "那就先吃自己的存粮。", "ending": "契岑决定继续闭门，等旧雇主认账。"},
		"pending": "契岑仍握着要塞的钥匙。",
	},
	"highdrake": {
		"title": "铅翼 · 山口和长老席",
		"text": "长老不准龙下山。我能去争席位，也能留下来守山口。",
		"personal_a": {"label": "带村民去争席位。", "response": "先找人接守，村民的账当面谈。", "ending": "铅翼准备带村民去见长老。"},
		"personal_b": {"label": "留下来守山口。", "response": "我找年轻的龙轮守，再选烟火能被看见的地方。", "ending": "铅翼决定留在山口，筹备两处求援火台。"},
		"pending": "铅翼还没给长老答复。",
	},
	"cloudscale": {
		"title": "霁鳞 · 铜铃响到哪一季",
		"text": "船家请我护航一整个冬天。我得留下找龙轮值，也可以只把河道告诉他们。",
		"personal_a": {"label": "留下护航，找龙轮换。", "response": "两下慢铃开船，急铃救人。", "ending": "霁鳞答应筹备一季护航，等轮值人手到齐。"},
		"personal_b": {"label": "告诉船家河道，不接长约。", "response": "我会告诉他们怎么走，我自己哪天飞走还说了算。", "ending": "霁鳞留下河道指引，拒绝整个冬天护航。"},
		"pending": "船家还在等霁鳞答复。",
	},
	"longroad": {
		"title": "长路 · 买家也要杀我",
		"text": "我把营地消息卖给黑旗。他们在废秤房等着杀我。",
		"personal_a": {"label": "告诉全队，停止私下接头。", "response": "可以，以后接头先过大家这一关。", "ending": "长路同意让队友知道旧事，暂不再私下接头。"},
		"personal_b": {"label": "暂不公开，先查买家。", "response": "我告诉你废秤房的口令，也能陪你认人。", "ending": "长路交出接头情报，向队友暂时保密。"},
		"pending": "长路还在躲黑旗的买家。",
	},
	"fieldmedic": {
		"title": "苏茅 · 把人从战鼓旁带走",
		"text": "伤兵又被赶去打仗。先找军医教助手，还是现在就带担架去营里？",
		"personal_a": {"label": "先找军医教助手。", "response": "先学护伤口，再学抬人。", "ending": "苏茅打算先教助手，以后能接更多人。"},
		"personal_b": {"label": "先用担架接伤兵。", "response": "问清谁愿走，能抬几个就抬几个。", "ending": "苏茅准备先接走愿意离营的伤兵。"},
		"pending": "营里还有伤兵，苏茅还在找帮手。",
	},
	"siltguard": {
		"title": "泽栅 · 握闸的人要多少兵",
		"text": "城主肯用粮和兵换我闭嘴。我也能向码头守军认账，再去争闸楼。",
		"personal_a": {"label": "向码头守军认账。", "response": "我亲口说是我拔的闸销。", "ending": "泽栅准备承认开闸，再和码头守军谈。"},
		"personal_b": {"label": "去和城主谈粮和兵。", "response": "只谈内城，下游的人不在这笔账里。", "ending": "泽栅打算用沉默换内城的粮和兵。"},
		"pending": "泽栅还留着旧闸销。",
	},
	"seasons": {
		"title": "梅文娜 · 麦苗和山道",
		"text": "谷里求回暖，山口求霜拦兵。一回暖，麦苗能长，兵车也能过山。",
		"personal_a": {"label": "让谷地回暖。", "response": "暖风会化开山道，你们自己拦兵。", "ending": "梅文娜答应让谷地回暖，守路的人得自己拦兵。"},
		"personal_b": {"label": "再留三天霜。", "response": "三天之后我收霜，冻坏的麦苗也回不来。", "ending": "梅文娜答应再留三天霜，让守路人搬石堵路。"},
		"pending": "麦田和山口都在等梅文娜回话。",
	},
	"earth_god": {
		"title": "多兰克 · 铁撑立起来以前",
		"text": "深井还在挖。先停工补支柱，或者我只开一条小路让担架进去。",
		"personal_a": {"label": "停深井，先补支柱。", "response": "深处还在敲，我就不开口。", "ending": "多兰克等深井停工、矿口撑好，才会开山。"},
		"personal_b": {"label": "给担架队开路。", "response": "只给三天，军队和矿车不准进。", "ending": "多兰克答应让担架队进山三天。"},
		"pending": "矿口仍在等多兰克打开。",
	},
	"sky_god": {
		"title": "莱文索 · 一夜风，还是一面旗",
		"text": "船工求一夜静风找亲人。也有人认出了冒挂白布的军舰。",
		"personal_a": {"label": "先让民船出发。", "response": "风停一夜，天亮前回来。", "ending": "莱文索答应给民船一夜静风。"},
		"personal_b": {"label": "先追查冒挂白布的舰队。", "response": "带证人来，我要听他认的是哪面旗。", "ending": "莱文索先去查军舰，找亲人的船仍在等风。"},
		"pending": "船工和证人都在等莱文索回话。",
	},
	"snowforge": {
		"title": "砧雪 · 旧部与新炉",
		"text": "钱只够做一件事：回城救工匠，或在山外搭炉，让逃出来的人有活干。",
		"personal_a": {"label": "先回城接工匠。", "response": "肯回去的跟我走，接应车留在城外。", "ending": "砧雪把钱留给接应车，准备回城救人。"},
		"personal_b": {"label": "先搭炉，接纳流亡工匠。", "response": "炉子归工匠管，军官要用就付钱。", "ending": "砧雪决定先搭新炉，仍要另找路接城里的工匠。"},
		"pending": "砧雪还在犹豫把钱用在哪里。",
	},
}

var run: RefCounted

func _init(expedition: RefCounted) -> void:
	run = expedition

func _choice(id: String, label: String) -> Dictionary:
	return {"id": id, "text": label, "enabled": true, "reason": "", "spoken": not run.data.has("journey")}

func encounter_intro(visitor: String, subject: String) -> Dictionary:
	var member = run.actor(visitor)
	var person = run.actor(subject)
	if member.is_empty() or person.is_empty() or not BACKGROUNDS.has(subject) or not run.data.story.has(subject):
		return {"ok": false, "message": "没有可以交谈的对象。", "beats": []}
	if not member.joined or member.hp <= 0 or subject == visitor or person.position != member.position or not run.data.tiles.has(person.position):
		return {"ok": false, "message": "要交谈，先让能行动的队员走到对方身边。", "beats": []}
	if not run.data.tiles[person.position].enemies.is_empty():
		return {"ok": false, "message": "这里还不安全。先把敌人赶走，再和对方交谈。", "beats": []}
	return {"ok": true, "beats": []}

func _personal_choice(subject: String) -> String:
	return run.data.story[subject].get("personal_choice", "")

func _recorded_personal_quest(subject: String, chosen: String) -> Dictionary:
	if chosen.begins_with("personal_"):
		return LegacyOutcomes.OUTCOMES[subject]
	if chosen.begins_with("war_"):
		return LegacyOutcomes.PREVIEW_OUTCOMES.get(subject, LegacyOutcomes.TRAVEL_OUTCOMES[subject])
	if chosen.begins_with("war2_"):
		return LegacyOutcomes.WAR_OUTCOMES.get(subject, LegacyOutcomes.TRAVEL_OUTCOMES[subject])
	if chosen.begins_with("god_"):
		return LegacyOutcomes.TRAVEL_OUTCOMES[subject]
	return PERSONAL_QUESTS[subject]

func _personal_outcome(subject: String, chosen: String) -> Dictionary:
	return _recorded_personal_quest(subject, chosen)["personal_" + chosen.right(1)]

func _personal_speech(subject: String, chosen: String) -> String:
	var response: String = _personal_outcome(subject, chosen).response
	if not response.contains("「"):
		return response
	# Historical outcomes interleave the actor's lines with descriptions of their gestures.
	var lines = PackedStringArray()
	for passage in response.split("「").slice(1):
		var line = passage.get_slice("」", 0)
		if line.ends_with("。") or line.ends_with("？") or line.ends_with("！"):
			lines.append(line)
	return "\n\n".join(lines)

func hero_identity_known() -> bool:
	return run.data.status == "won" or run.data.flags.get("hero_identity_revealed", false) == true

func character_records(id: String) -> Array[Dictionary]:
	if id == "hero":
		var records: Array[Dictionary] = [{"title": "村庄醒来",
			"body": "你从战场上被救回，忘了自己的名字。村民送了你一副牌。"}]
		if hero_identity_known():
			records.append({"title": "记忆回来了",
				"body": "你是引渡亡魂的死神伊文洛。决战时，你想起卡德兰曾杀过你。"})
		return records
	var record: Dictionary = run.data.story.get(id, {})
	var finished: bool = run.data.status in ["won", "failed"]
	if not run.actor(id).get("joined", false):
		if finished and record.get("met", false):
			return [{"title": "尾声", "body": character_ending(id).text}]
		return []
	var records: Array[Dictionary] = []
	var chosen = _personal_choice(id)
	if record.get("codex_past_read", false) and (chosen.is_empty() or chosen.begins_with("journey_")):
		records.append({"title": "过去的事", "body": BACKGROUNDS[id]})
	else:
		records.append({"title": "过去的事", "hint": "和这位伙伴聊过往事后收录。"})
	if chosen.is_empty():
		records.append({"title": "同行以后", "hint": "一起作出决定后，这里会记下本次远征的选择。"})
	else:
		var outcome = _personal_outcome(id, chosen)
		records.append({"title": "同行以后", "body": str(outcome.response)})
	if finished:
		records.append({"title": "尾声", "body": character_ending(id).text})
	return records

func _personal_context(visitor: String, subject: String) -> Dictionary:
	var intro = encounter_intro(visitor, subject)
	if not intro.ok:
		return intro
	var person = run.actor(subject)
	if not PERSONAL_QUESTS.has(subject) or not person.joined or person.hp <= 0:
		return {"ok": false, "message": "这件事要等对方入队后再谈。两个人都得在场，也都得能行动。"}
	if run.data.status != "exploring" or not run.data.pending_battle.is_empty():
		return {"ok": false, "message": "等眼前的战斗打完、继续远征时，再来谈这件事。"}
	return {"ok": true}

func personal_quest(visitor: String, subject: String) -> Dictionary:
	var context = _personal_context(visitor, subject)
	if not context.ok:
		return context
	var quest: Dictionary = PERSONAL_QUESTS[subject]
	var chosen = _personal_choice(subject)
	if not chosen.is_empty():
		var title: String = _recorded_personal_quest(subject, chosen).title
		return {"ok": true, "title": title, "text": _personal_speech(subject, chosen), "options": [_choice("leave", "回头再聊。")], "pose": "friendly"}
	return {"ok": true, "title": quest.title, "text": quest.text, "options": [_choice("personal_a", quest.personal_a.label), _choice("personal_b", quest.personal_b.label), _choice("leave", "再想想。")], "pose": "serious"}

func _choose_personal(visitor: String, subject: String, option_id: String) -> Dictionary:
	if option_id not in ["personal_a", "personal_b"]:
		return {"ok": false, "message": "这里没有这个选项。"}
	var context = _personal_context(visitor, subject)
	if not context.ok:
		return context
	var chosen = _personal_choice(subject)
	if not chosen.is_empty():
		return {"ok": false, "message": "这件事已经定了。", "response": _personal_outcome(subject, chosen).response}
	# UI option IDs stay stable; the saved prefix separates new plans from old acts.
	run.data.story[subject]["personal_choice"] = "journey_" + option_id.trim_prefix("personal_")
	return {"ok": true, "response": PERSONAL_QUESTS[subject][option_id].response}

func dialogue(visitor: String, subject: String) -> Dictionary:
	var intro = encounter_intro(visitor, subject)
	if not intro.ok:
		return intro
	var person = run.actor(subject)
	if not person.joined:
		return {"ok": false, "message": "招募后可以和这位伙伴聊聊。"}
	var identity: String = person.get("race", "旅人")
	if Catalog.COMPANIONS[subject].race == "神":
		identity = Catalog.COMPANIONS[subject].title + "的化身"
	var title = "%s · %s" % [person.name, identity]
	var speaker: String = person.name
	var body: String = CHARACTER_BEHAVIOR[subject][2]
	var choices: Array = []
	if person.hp <= 0:
		speaker = run.actor(visitor).name
		body = "还有呼吸，但现在没法交谈。"
	else:
		if _personal_context(visitor, subject).ok:
			var chosen = _personal_choice(subject)
			choices.append(_choice("quest", "重听决定" if not chosen.is_empty() else "接下来呢？"))
			# Historical saves revisit their own facts, never the rewritten backstory.
			if chosen.is_empty() or chosen.begins_with("journey_"):
				choices.append(_choice("past", "问起往事"))
			if visitor == "hero" and HERO_LINES.has(subject):
				choices.append(_choice("echo", "你认得我吗？"))
	choices.append(_choice("leave", "先聊到这儿。"))
	var pose := "grief" if person.hp <= 0 else "friendly"
	return {"ok": true, "title": title, "speaker": speaker, "text": body, "options": choices, "pose": pose}

func choose(visitor: String, subject: String, option_id: String) -> Dictionary:
	if option_id.begins_with("personal_"):
		return _choose_personal(visitor, subject, option_id)
	var d = dialogue(visitor, subject)
	if not d.ok:
		return d
	if not d.options.any(func(option): return option.id == option_id):
		return {"ok": false, "message": "现在无法这样做。"}
	match option_id:
		"quest":
			return {"ok": true, "quest": true}
		"past":
			return {"ok": true, "response": BACKGROUNDS[subject]}
		"echo":
			return {"ok": true, "response": HERO_LINES[subject]}
	return {"ok": true, "close": true}

func main_ending() -> Dictionary:
	if run.data.status == "won":
		return {"title": "鼓声止了", "text": "卡德兰倒下。你把亡魂领回冥河。"}
	return {"title": "这次没能走到最后", "text": run.data.flags.get("failure_reason", "远征在这里中断了。")}

func character_ending(id: String) -> Dictionary:
	var person = run.actor(id)
	if person.is_empty() or not PERSONAL_QUESTS.has(id):
		return {"name": person.get("name", id), "text": "没有这位同行者的个人记录。"}
	var quest: Dictionary = PERSONAL_QUESTS[id]
	var chosen = _personal_choice(id)
	var result: String = quest.pending
	if person.joined and not chosen.is_empty():
		result = _personal_outcome(id, chosen).ending
	if person.hp <= 0:
		var injured_subject: String = person.name + "的化身" if Catalog.COMPANIONS[id].race == "神" else person.name
		result += "\n%s还在养伤。" % injured_subject
	return {"name": person.name, "text": result}
