# ui/ · 游戏界面（A「检修图版」）

UI 负责人维护（交接规范第四节：`ui/` 归 UI 负责人）。视觉规范是 A「检修图版」v1，和网页原型 `src/styles/tokens.css` 同值，用户 10-07 已验收。

这里只有界面：**只读状态、只显示、只发请求**。机关成败、密码对错、能不能切时代，一律由公共程序 `core/state_service.gd` 判定。

## 文件

| 文件 | 是什么 |
|---|---|
| `theme.tres` | 主题：字体、字号、颜色、底板、按钮六态。所有 UI 场景都挂它 |
| `hud.tscn` / `hud.gd` | HUD：左上目标、右上时代标签（Q）、准星、交互提示、上方状态提示、右下按键提示 |
| `interaction_prompt.tscn` / `.gd` | 交互提示：［E］动词 物件名；不能用时 ⊘ + 原因。HUD 里已经放了一个 |
| `cabinet_panel.tscn` / `.gd` | 配电箱密码面板（纸底，4 位数字，键盘和鼠标都能输） |
| `residual_screen.tscn` / `.gd` | 残差率画面：黑屏 → 白底 → 数字跳动 → 结果（如 0.000021 → 0.000024） |
| `ui_text.gd` | 全部界面文案（物件名、动词、目标、提示）。改字只改这里 |
| `ui_tokens.gd` | 颜色和动效时长 |
| `ui_layer.gd` | 图层基类：按 1920×1080 设计，按窗口等比缩放（不改 project.godot） |
| `style/notch_style_box.gd` | 体素缺角底板（StyleBox） |
| `widgets/ui_glyph.gd` | 代码画的小图形：状态图标、眼镜符号、准星、刻度尺、时代切换效果 |
| `preview/ui_preview.tscn` | 预览：占位 3D 场景上的 10 个状态，按 1–0 切换 |
| `tests/ui_tests.gd` | 无界面自测（46 项），其中一组直接驱动真实的 `core/state_service.gd` |
| `tools/capture_ui.ps1` | 预览截图（拿共享 GPU 锁） |
| `screenshots/` | 10 个状态的截图 |

## 接到主场景（给公共程序 / 主集成）

```gdscript
const HudScene := preload("res://ui/hud.tscn")
const CabinetPanelScene := preload("res://ui/cabinet_panel.tscn")

var hud := HudScene.instantiate()
add_child(hud)
hud.bind_service(service)          # 跟随 state_changed / feedback / level_completed

var panel := CabinetPanelScene.instantiate()
add_child(panel)
panel.submitted.connect(func(code): interact("cabinet", "submit_code", code))
panel.cancelled.connect(func(): service.cancel_puzzle_ui())
# open_puzzle_ui("cabinet") 通过后：panel.open()；adapter.cancel_transients() 里：panel.close()
```

- **交互提示**：每帧算出最近的可交互物件后调 `hud.show_interaction(device_id, action, blocked_reason)`，没有物件时 `hud.hide_interaction()`。`blocked_reason` 为空表示能用；物件只在另一个时代可用时传 `Text.ONLY_IN_ERA[可用时代]`（“过去才能用”）。内容不变时重复调用不会闪。
- **自动显示的**（`bind_service` 之后不用再管）：时代标签和 480 ms 切换效果；目标和步数（按 flags）；flag 第一次变 true 时的提示（阀门已关闭、密码正确……）；被拒绝的请求（`wrong_code`、`wrong_era`、`unsafe_switch`……，`input_blocked` 不提示）；通关；`input_mode == "puzzle_ui"` 时收起探索 HUD。
- **其他方法**：`show_status(kind, title, body)`（kind = success / error / warn / info / blocked / busy）、`set_suppressed(reason, on)`（对话、过场时收起 HUD）、`reset_transients()`、`notice_label`（左下一行小字）、`set_debug_text()` + `debug_visible`。
- **残差率**：`$ResidualScreen.play(0.000021, 0.000024)`，播完发 `finished`。全屏盖住 HUD。
- **图层**：HUD 10、密码面板 20、残差率 30。
- **键位**：E 交互、Q 切时代、R 回检查点（按键提示里写的就是这三个）。Esc 由主场景的 `_input` 统一处理，面板自己不处理。

## 字体

用系统字体，按顺序找：宋体标题 Noto Serif SC → 思源宋体 → 华文宋体／宋体；黑体正文 Noto Sans SC → 思源黑体 → 微软雅黑；窄体标签 Barlow Condensed → Bahnschrift；数字 Cascadia Mono → Consolas。录制机上最好装 Noto Sans SC / Noto Serif SC（免费），否则会退到微软雅黑和宋体，排版不变、字形不同。

## 怎么测

```powershell
# 无界面自测（46 项）
& $godot --headless --path . --script res://ui/tests/ui_tests.gd
# 预览：编辑器里打开 ui/preview/ui_preview.tscn 按 F6，按 1–0 切状态
# 截图（1920×1080，写到 ui/screenshots/）
.\ui\tools\capture_ui.ps1
```

## 文案口径

- 用语对齐《视频脚本_v001》字幕；关卡名：断桥、检修通道、配电小院。
- 主角称“我／上校”；正式密码 0427（用户 10-07 定），面板里不写死，由关卡配置判定。
- 背包、装备、商店等预留页面这一轮不做（用户 10-07 定，初赛后再说）。
