extends RefCounted
## 界面文案表（UI 负责人维护）。只管“怎么说”，不判定机关成败：
## 成败一律以公共程序 state_service 的状态和 reason 为准。
##
## 写法（参照商业游戏的界面文本惯例，10-08 定）：
## - 任务追踪：任务名用名词（与视频字幕的关卡名一致），每一步写“动词＋对象”的祈使短句，进度另列
## - 交互提示：［键］＋两字动词＋对象名；不能用时写“需在××操作”这类条件，不写口语解释
## - 系统提示：先说状态（密码错误、距离过远、条件未满足），不用“你”、不用语气词，单句不加句号
## - 同一概念只用一个词：时代＝现在／过去；切换＝戴上眼镜／摘下眼镜；交互键＝E
## 主角称“我／上校”只出现在对白里，系统文本保持中性。正式密码 0427（用户 10-07 定）。

const ERA_NAME := {"present": "现在", "past": "过去"}
const ERA_ALIAS := {"present": "α", "past": "β"}
## 按 Q 会做的动作（按当前时代取）
const ERA_HINT := {"present": "戴上眼镜", "past": "摘下眼镜"}

const LEVEL_NAME := {
	"mvp_bridge": "断桥",
	"mvp_valve": "检修通道",
	"mvp_cabinet": "配电小院",
}

const DEVICE_NAME := {
	"valve": "蒸汽阀门",
	"plaque": "铭牌",
	"cabinet": "配电箱",
	"start_button": "启动按钮",
	"isolation_gate": "隔离门",
	"exit_trigger": "出口",
	"far_landing": "对岸",
	"relay_lever": "拉杆",          # 第 2 关继电器柜的三档拉杆（10-08 加）
}

## 交互提示里的动词（按 E 之后发生的事）
const ACTION_VERB := {
	"close": "关闭",
	"read": "调查",
	"submit_code": "打开",
	"press": "按下",
	"inspect": "调查",
	"enter": "进入",
	"pull": "扳动",
}

## 任务追踪：标题＝关卡名；每一步对应一个 flag，flag 变 true 即完成。
const OBJECTIVES := {
	"mvp_bridge": {
		"title": "断桥",
		"steps": [
			["在过去走过桥面", "bridge_crossed_past"],
			["前往出口", "exit_reached"],
		],
	},
	"mvp_valve": {
		"title": "检修通道",
		"steps": [
			["在过去关闭蒸汽阀门", "valve_closed_past"],
			["锁定转运平台", "platform_locked_past"],
			["穿过检修通道", "exit_reached"],
		],
	},
	"mvp_cabinet": {
		"title": "配电小院",
		"steps": [
			["在过去调查铭牌", "clue_seen"],
			["输入配电箱密码", "cabinet_unlocked"],
			["按下启动按钮", "power_on"],
			["前往出口", "exit_reached"],
		],
	},
}

## flag 第一次变成 true 时的提示：[种类, 标题, 说明]（说明可为空）
const FLAG_NOTE := {
	"bridge_crossed_past": ["success", "已抵达对岸", ""],
	"valve_closed_past": ["success", "蒸汽阀门已关闭", "隔离门已闭合"],
	"platform_locked_past": ["success", "转运平台已锁定", ""],
	"clue_seen": ["info", "获得线索", "配电箱密码：0427"],
	"cabinet_unlocked": ["success", "密码正确", "启动按钮已解锁"],
	"power_on": ["success", "电源已接通", "出口已开启"],
}

const COMPLETED_NOTE := ["success", "通路已恢复", ""]

## 掉落或进入蒸汽后，由主场景触发检查点恢复
const RECOVERED_NOTE := ["warn", "已返回检查点", ""]

## 换关后左下角的一行说明
const START_NOTICE := "点击画面开始"

## state_service 拒绝请求时的提示：[种类, 标题, 说明]。不在表里的 reason 不提示（如 input_blocked）。
const REASON_NOTE := {
	"unsafe_switch": ["blocked", "无法切换时代", "目标时代此处无立足点"],
	"wrong_era": ["blocked", "当前时代无法操作", ""],
	"out_of_range": ["blocked", "距离过远", ""],
	"prerequisites_unmet": ["blocked", "条件未满足", ""],
	"wrong_code": ["error", "密码错误", ""],
	"config_missing": ["error", "密码未配置", "检查关卡配置"],
	# 第 2 关机关（主蒸汽廊组件的原因码，10-08 加）：现在时代拉杆、阀门锈住；已锁上再扳给一句确认，免得像没反应
	"seized": ["blocked", "已锈死", ""],
	"already_locked": ["info", "已锁定", ""],
}

## 物件只在某个时代可用、玩家在另一个时代时，提示里写的条件（按物件可用的时代取）
const ONLY_IN_ERA := {"past": "需在过去操作", "present": "需在现在操作"}

## 配电箱面板
const PANEL_TAG := "DISTRIBUTION BOX · 配电箱"
const PANEL_TITLE := "配电箱"
const PANEL_NOTE_TITLE := "输入 %d 位密码"
const PANEL_NOTE_BODY := ""
const PANEL_SHORT := "密码位数不足"


static func device_name(device_id: String) -> String:
	return DEVICE_NAME.get(device_id, device_id)


static func action_verb(action: String) -> String:
	return ACTION_VERB.get(action, action)


static func level_name(level_id: String) -> String:
	return LEVEL_NAME.get(level_id, level_id)
