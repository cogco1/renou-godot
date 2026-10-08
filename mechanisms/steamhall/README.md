# mechanisms/steamhall — 主蒸汽廊的两个机关

第 2 关（mvp_valve）城市版，红框⑤主蒸汽廊。行为规格：`主蒸汽廊_机关行为规格_v001.md`（关卡已对齐，Drive「Godot_三关MVP交接/03_阀门/接口对齐_大门与转运平台_v001_20261008.md」）。
只用 Godot 4.7.2 自带节点和 GDScript；**不改** `core/`、`project.godot`、`scenes/integration_lab.*`、`contracts/`。

| 文件 | 内容 |
|---|---|
| `big_sliding_gate.gd` / `.tscn` | `BigSlidingGate`：40 m 伸缩式大推拉隔离门（5 扇 × 8 m，高 7 m，门中门 2.4 × 2.7 只是布景）+ 蒸汽粒子 + `AREA_SteamCorridor` |
| `transfer_platform.gd` / `.tscn` | `TransferPlatform`：导轨转运平台（3.6 × 6.0 m，行程 13.85 m）+ 三档拉杆 + 锁销 + 继电器柜 + 系统卷帘 + `AREA_FallReset` |
| `demo/demo_steamhall.tscn` | 能单独跑的演示：约 90 m 检修通道、阀站、大门、吊装井、平台、卷帘 |
| `tests/test_steamhall_mechanisms.gd` | 无头验收测试，共 38 项 |

## 状态规则（只从 flags + era 推出来）

- 门：`closed = valve_closed_past`；`hazard_active = era == "present" and not valve_closed_past`。
- 平台：对位和锁销 = `platform_locked_past`；拉杆档位 = 3（锁定）或 1（停放）；卷帘只在现在 α 且已锁时落下。现在 α 下，玩家第一次踩上平台时，卷帘播 3 s 下落动画。
- 动画都是过渡。`apply_state()` 和 `cancel_transients()` 直接把机关放到终态；动画不会回写 flag。
- 隐藏时代的碰撞会去掉 layer 1（卷帘只在现在有碰撞），不用 `process_mode = DISABLED`。

## Kevin 的 adapter 怎么接

```gdscript
# rebuild(state)
gate.apply_state(state.flags.valve_closed_past, state.era)
platform.apply_state(state.flags.get("platform_locked_past", false), state.era)
# cancel_transients()
gate.cancel_transients(); platform.cancel_transients()
# in_range(device_id)
"relay_lever": return platform.lever_in_range(player.global_position)
# 公共层接受 valve/close 之后（flag 已写）：
gate.play_close()                     # 6.0 s，对上 V2
# 公共层接受 relay_lever/pull 之后（flag 已写）：
platform.play_lock_sequence()         # 约 5.8 s：拉杆 ①→②、平台 4.0 s、拉杆 ②→③、锁销 0.8 s
# 危险
gate.steam_body_entered.connect(回检查点)
platform.fell_into_gap.connect(回检查点)
# T 整关重开：flag 回到 false 后照常 apply_state，卷帘的"已落下"记忆会自动清掉；reset_shutter_memory() 一般不用调
```

拉杆被拒绝的原因：`platform.lever_request(era)` 先判时代，现在 α 一律返回 `seized`（"锈死了"）；只有在过去 β 且已锁时才返回 `already_locked`。顺序和 core 一致。

城市落位（Blender 世界坐标 → Godot (x, z, −y)）：
- **大门**：原点在南端 (−430.7, 1025.0, 9.70)，`rotation_degrees.y = 90`（局部 +X 朝北，+Z 朝东侧通道），`stack_at_end = true`（门叶叠在北端）。
- **平台**：原点 = 对位后平台中心的顶面 (−426.55, 1006.5, 9.70)，不旋转。

## 运行

```powershell
$G = 'D:\PROJECTS\07_SOFTWARE_INSTALLERS_安装包与软件\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $G --path . res://mechanisms/steamhall/demo/demo_steamhall.tscn                       # 试玩：WASD/鼠标/空格，E 交互，Q 切时代，R 检查点，T 重开
& $G --headless --path . --script res://mechanisms/steamhall/tests/test_steamhall_mechanisms.gd   # 38 项，退出码 0 = 全过
& $G --headless --path . res://mechanisms/steamhall/demo/demo_steamhall.tscn -- --demo-smoke
& $G --path . --resolution 1280x720 res://mechanisms/steamhall/demo/demo_steamhall.tscn -- --demo-capture=<目录>   # 自动截 8 张验收图
```

## 还要别人做的（本 PR 不碰）

- `contracts/mvp_valve.json`：加 flag `platform_locked_past`、加设备 `relay_lever`（动作 `pull`），完成条件改成三个都满足。由 Benson、Kevin 定。
- `core/state_service.gd`：加 `mvp_valve/relay_lever/pull`（现在 α 返回 `seized`，已锁返回 `already_locked`）；`exit_trigger/enter` 的前置改成阀门已关且平台已锁。由 Benson 做。
- `ui/ui_text.gd`：加 `relay_lever` 的文案"[E] 扳动 拉杆""锈死了"。由交互做。
- 美术：门叶、平台、柜子、卷帘现在都是盒子占位，换皮时保持节点名和轴心不变。
