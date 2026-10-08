extends RefCounted
## 界面文案表（UI 负责人维护）。只管“怎么说”，不判定机关成败：
## 成败一律以公共程序 state_service 的状态和 reason 为准。
## 用语对齐《视频脚本_v001》字幕；主角称“我／上校”；正式密码 0427（用户 10-07 定）。

const ERA_NAME := {"present": "现在", "past": "过去"}
const ERA_ALIAS := {"present": "α · 裸眼", "past": "β · 戴镜"}
## 按 Q 会去到的时代
const ERA_HINT := {"present": "戴镜看过去", "past": "摘镜回现在"}

const LEVEL_NAME := {
	"mvp_bridge": "断桥",
	"mvp_valve": "检修通道",
	"mvp_cabinet": "配电小院",
}

const DEVICE_NAME := {
	"valve": "阀门",
	"plaque": "铭牌",
	"cabinet": "配电箱",
	"start_button": "启动按钮",
	"isolation_gate": "隔离门",
	"exit_trigger": "出口",
	"far_landing": "对岸",
}

const ACTION_VERB := {
	"close": "关闭",
	"read": "查看",
	"submit_code": "输入密码",
	"press": "按下",
	"inspect": "检查",
	"enter": "进入",
}

## 目标：每关一个标题，若干步；某步对应的 flag 变 true 就算完成。
const OBJECTIVES := {
	"mvp_bridge": {
		"title": "到对岸去",
		"steps": [
			["过去：沿完整的桥面走到对岸", "bridge_crossed_past"],
			["现在：走进出口", "exit_reached"],
		],
	},
	"mvp_valve": {
		"title": "穿过检修通道",
		"steps": [
			["过去：关闭阀门，让隔离门闭合", "valve_closed_past"],
			["现在：穿过已经隔开蒸汽的通道", "exit_reached"],
		],
	},
	"mvp_cabinet": {
		"title": "恢复配电箱的电",
		"steps": [
			["过去：读清铭牌上的密码", "clue_seen"],
			["现在：在配电箱输入密码", "cabinet_unlocked"],
			["现在：按下启动按钮", "power_on"],
			["走出打开的大门", "exit_reached"],
		],
	},
}

## flag 第一次变成 true 时弹出的提示：[种类, 标题, 说明]
const FLAG_NOTE := {
	"bridge_crossed_past": ["success", "已到对岸", "回到现在，桥仍断着"],
	"valve_closed_past": ["success", "阀门已关闭", "隔离门闭合，蒸汽被隔在设备间"],
	"clue_seen": ["info", "铭牌上的密码", "0427"],
	"cabinet_unlocked": ["success", "密码正确", "启动按钮已解锁"],
	"power_on": ["success", "电源接通", "工作灯亮起，出口打开"],
}

const COMPLETED_NOTE := ["success", "通路已恢复", "可以自由走动，按 T 重来"]

## 掉下去或碰到蒸汽，由主场景触发检查点恢复时
const RECOVERED_NOTE := ["warn", "回到检查点", "从上一个检查点重新开始"]

## 换关后左下角的一行说明
const START_NOTICE := "点击画面开始操作 · Esc 释放鼠标"

## state_service 拒绝请求时的说法：[种类, 标题, 说明]。不在表里的 reason 不提示。
const REASON_NOTE := {
	"unsafe_switch": ["blocked", "此处无法切换", "另一个时代这里没有落脚处"],
	"wrong_era": ["blocked", "这个时代用不了它", "按 Q 换个时代看看"],
	"out_of_range": ["blocked", "离得太远", "再走近一点"],
	"prerequisites_unmet": ["blocked", "还不能用", "先完成前一步"],
	"wrong_code": ["error", "密码不对", "按 E 重试"],
	"config_missing": ["error", "配电箱没有配置密码", "请程序检查关卡配置"],
}

## 物件只在某个时代可用、而玩家在另一个时代时，提示里写的原因（按物件可用的时代取）
const ONLY_IN_ERA := {"past": "过去才能用", "present": "现在才能用"}


static func device_name(device_id: String) -> String:
	return DEVICE_NAME.get(device_id, device_id)


static func action_verb(action: String) -> String:
	return ACTION_VERB.get(action, action)


static func level_name(level_id: String) -> String:
	return LEVEL_NAME.get(level_id, level_id)
