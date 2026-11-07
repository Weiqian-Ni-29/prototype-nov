extends RefCounted

const TITLE = "第一章 · 地图上没有的驿站"
const BEATS = {
	"road": {
		"scene": "opening-road", "location": "白栎边境 · 旧灯路", "speaker": "旁白",
		"text": "天刚亮，你随商队进入白栎边境。委托是重走旧灯路，记下还能通行的路段，再把登记副本带到归航站。\n车辙没入河谷的雾里，渡桥的灯还亮着。",
		"options": [{"id": "bridge", "text": "随商队过桥"}],
	},
	"bridge": {
		"scene": "opening-bridge", "location": "河谷 · 断桥", "speaker": "旁白",
		"text": "刚踏上对岸，脚下的石阶就震了起来。桥面折进河里，绳索打着旋消失在水雾中。\n等你绕过滑落的山石，路上已经看不见商队。",
		"options": [{"id": "shelter", "text": "去路边的废棚避一避"}],
	},
	"shelter": {
		"scene": "opening-shelter", "location": "断桥废棚", "speaker": "旅人",
		"text": "桥是回不去了。登记副本还在，棚外也有一点灯光。\n先确认下一段路该怎么走吧。",
		"options": [
			{"id": "order", "text": "先看看登记副本"},
			{"id": "lamps", "text": "看看外面还有没有灯"},
		],
	},
	"order": {
		"scene": "opening-shelter", "location": "断桥废棚", "speaker": "旅人",
		"text": "归航站在河谷另一端，接应船照常往来。找到码头，就还有一条回去的路。\n先把副本收好，路上看到的情况也一并记下来。",
		"options": [{"id": "depart", "text": "走出废棚"}],
	},
	"lamps": {
		"scene": "opening-shelter", "location": "断桥废棚", "speaker": "旅人",
		"text": "雾里那盏灯还在亮，灯下的石路有新脚印。也许前面还有人走这条路。\n先沿灯路去看看，再循登记副本上的方向找归航站。",
		"options": [{"id": "depart", "text": "走出废棚"}],
	},
}
