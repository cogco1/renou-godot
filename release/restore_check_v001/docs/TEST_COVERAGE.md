# 公共验收规格与本次实际测试的关系

来源 `inputs/reference_contracts/公共验收.tests.json` 是12条规格，未当作已经执行的JSON脚本。此次实际运行 `tests/runtime_tests.gd`，调用同一核心与真实adapter；以下为等义行为覆盖，不声称给定JSON逐事件重放。

| 来源规格 | 实际报告test_id |
|---|---|
| C01_past_change_survives_switch | valve_persists、valve_route_1/2 |
| C02_wrong_era_rejected | era_before_range、exit_wrong_era_priority |
| C03_repeat_is_idempotent | idempotent_close、same_frame_debounce |
| C04_switch_without_safe_ground | airborne_rejected、no_target_ground |
| C05_switch_target_occupied | capsule_wall_rejected |
| C06_restart_clears_puzzle | restart_clears |
| C07_checkpoint_restores_snapshot | checkpoint_snapshot、steam_failure_recovery |
| C08_puzzle_ui_blocks_world_interaction | ui_blocks_world、ui_blocks_interact、escape_ui_focus |
| C09_exit_before_solution_not_complete | unsolved_exit |
| C10_solved_and_exit_completes | bridge_route_1/2、valve_route_1/2、cabinet_route |
| C11_direct_completion_is_not_player_input | output_only |
| C12_no_checkpoint_falls_back_to_initial | reset_cancels_ui |

语义测试会将角色置于明确测试位置，不凭此证明行走可达；`engine_player_route`项目单列真实Input+角色物理、触发和失败流程。安全测试在真实Godot空间执行射线/capsule查询，没有注入context bool。

后续必须补：三关已交GLB导入后的真实碰撞、5.5m桥断口跳跃、阀/门真实轴心与代理、实际密码UI人工键入和鼠标手感、导出程序和赛事交付格式。录像秒数为内部剪辑目标，未核实正式赛事要求。
