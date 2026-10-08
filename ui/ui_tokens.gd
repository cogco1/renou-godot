extends RefCounted
## A「检修图版」规范 v1 的颜色、尺寸和时长（与网页原型 src/styles/tokens.css 同值）。
## 脚本里要用颜色时从这里取，不要写死色值；控件外观尽量走 theme.tres。

const BASE_SIZE := Vector2(1920, 1080)  # 设计尺寸，UI 缩放 100%

const IRON := Color("141615")
const IRON_78 := Color(0.0784, 0.0863, 0.0824, 0.78)
const IRON_92 := Color(0.0784, 0.0863, 0.0824, 0.92)
const NIGHT := Color("0d0f0e")
const PAPER := Color("efe6cf")
const SHEET := Color("e6d9b8")
const INK := Color("1d1812")
const INK_SOFT := Color("554a3b")
const RULE := Color("c9b78f")
const GOLD := Color("e2b25e")
const GOLD_HOVER := Color("efc77d")
const GOLD_PRESS := Color("c79a45")
const OCHRE := Color("8a5a12")
const SIGNAL := Color("c8553d")
const SIGNAL_INK := Color("a8432f")
const ERROR_TEXT := Color("e58a73")
const MOSS := Color("8fae5a")
const MOSS_INK := Color("4f6b35")
const PAST := Color("5fa391")      # 铜绿：过去（显示别名 β）
const PRESENT := Color("c4692f")   # 锈橙：现在（显示别名 α）
const GRID := Color("cb5446")

const TEXT := PAPER
const TEXT_SECONDARY := Color(0.9373, 0.902, 0.8118, 0.80)
const TEXT_MUTED := Color(0.9373, 0.902, 0.8118, 0.64)
const BORDER := Color(0.9373, 0.902, 0.8118, 0.22)
const BORDER_STRONG := Color(0.9373, 0.902, 0.8118, 0.50)
const OVERLAY := Color(0.0314, 0.0353, 0.0353, 0.66)

# 动效（秒）
const T_HOVER := 0.12
const T_PRESS := 0.08
const T_PANEL := 0.20
const T_ERA := 0.48
const T_RESIDUAL_STEP := 0.06
const T_FADE := 0.12   # 减少动态效果时一律用这个淡入淡出


static func era_color(era: String) -> Color:
	return PAST if era == "past" else PRESENT


## 状态反馈的强调色：success / error / warn / info / blocked / busy
static func status_color(kind: String) -> Color:
	match kind:
		"success":
			return MOSS
		"error":
			return SIGNAL
		"warn", "busy":
			return GOLD
		"blocked":
			return TEXT_MUTED
	return PAPER
