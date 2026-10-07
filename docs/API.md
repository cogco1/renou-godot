# 公共 Godot 接入候选 1.0

本目录仅是独立 primitive 集成候选，正式主工程未确认。公共维护范围：`core/`、`project.godot`、`scenes/integration_lab.*`；三个关卡会话各自维护自己的场景/资源/adapter，不直接编辑上述文件。

路径：`E:\PROJECTS\04_COMPETITIONS_竞赛\人偶之心\tmp\20261007_Godot_MVP_Integration`。

## 最小接入

```gdscript
var service = preload("res://core/state_service.gd").new()
add_child(service)
var registered = service.register_level(manifest_dictionary)
assert(registered.accepted)
service.activate("mvp_valve", level_adapter)
service.request({"event_type":"interact.request", "level_id":"mvp_valve", "device_id":"valve", "action":"close"})
```

共享服务不要求事件总线或通用JSON解析器；参考测试场从JSON加载固定三关manifest，正式接入也可提供同义Dictionary。`register_level` 检查版本、关卡ID、重复device/level ID。五个anchors是相对关卡根节点的路径，必须真实存在；未定值保留null。参考测试场在 `Level/Anchors/*` 建临时节点，城市位置仍null。

只读：`snapshot(level_id="")`、`manifest()` 均返回深复制。`world_enabled()` 在gameplay/completed返回true。不直接改 `_states` / `_checkpoints`。

事件：`request(Dictionary)` 返回 `{accepted: bool, reason: null|string}`，字段与公共1.0一致。checkpoint的device_id为实际路径 `Anchors/Checkpoint`，由adapter验证。`level.completed` 仅输出，直接请求一律 `output_only_event`。成功交互每物理帧最多一个；长按处理由玩家入口 `is_action_just_pressed` 完成。未知事件/动作/关卡、重复注册另用 `unknown_event` / `unknown_action` / `inactive_level` / `unknown_level` / `duplicate_device` / `duplicate_level` / `contract_mismatch`。

信号：`state_changed(level_id,state_copy)`、`level_completed(level_id)`、`feedback(result)`。completed不冻结移动、合法切时代和幂等互动。每次通关通知一次，restart后可再次发出。

UI：先 `open_puzzle_ui("cabinet")`，成功后再显示UI。UI提交走cabinet.submit_code；取消走 `cancel_puzzle_ui()`。错误码关闭UI并释放输入，可以E立刻重试。不要通过公开事件value伪造UI状态。生产模板 `test_mode=false,final_code=null` 返回config_missing；本地测试manifest明确 `test_mode=true,test_code="0427"`。

## 关卡 adapter 必须提供

| 方法 | 责任 |
|---|---|
| `in_range(device_id)->bool` | 真实空间距离/视线或触发体重叠；不能信任事件传来的范围bool |
| `switch_safety(target_era)->bool` | 当前站地、目标支撑及人物体积无实体占据；失败不改状态、不移动玩家 |
| `at_far_landing()->bool` | 断桥对岸安全区域真实重叠，仅用于摘镜观察flag |
| `valid_checkpoint(node_path)->bool` | 检查实际检查点ID |
| `checkpoint_in_range(node_path)->bool` | 检查实际检查点重叠 |
| `rebuild(state_copy)` | 同步重建全部可见性、物理碰撞、危险效果、动件终态和提示 |
| `reset_player(checkpoint_id_or_null)` | null使用spawn，有ID使用检查点锚点；清速度 |
| `cancel_transients()` | 关闭密码UI、释放输入、kill tweens/旧回调；临时动画不能回写flag |

`rebuild` 和 `cancel_transients` 必须同步完成；此版原子切时代在一个调用内经过switching再返回gameplay/completed，未引入异步动画。若以后加过场，需总程序统一，三关不要自行延迟flags写入。实体mesh和collision挂在同一moving父节点一起移动。

## 物理约定

- Godot局部Y向上、前方-Z、1单位=1米。角色胶囊高1.8m、半径0.3m、视点1.62m。源GLB轴向未测，不新增盲目旋转；导入负责人集中处理一次。
- 游戏实体层1，角色层4（mask=1）。保留查询层17=common、18=present、19=past，**仅供目标时代安全预检**。隐藏时代去掉实体层1并隐藏网格，不能被玩家实体碰撞；查询层永远不放进玩家mask。危险效果独立判定当前era和flags，不能从隐藏mesh推断。
- 参考实现以五条足底射线和完整capsule intersect_shape测试目标空间，查询在切换旧时代之前完成。失败不使用safe_return偷传送。
- 参考primitive triggers为真实玩家位置对局部AABB检测，无远程enter捷径；关卡可替换为Area3D实际重叠。范围不足先报out_of_range，再检查机关前置。
- 断桥只靠真实桥面与断口；无隐形出口锁，bridge_returned_present不是completion前置。
- 阀门隔离叶片始终在通道侧边；蒸汽hazard与实体门分开。配电箱past门原态未确认，测试场临时设为关闭并单独建体，不受present的power_on影响。

## 接手边界

交自己的节点/资源/manifest和适配器；先拿此核心只读比对。不得把此候选当正式主工程，不得将primitive坐标说成城市落点。未有总程序确认前不复制后各改一套core。

actual运行结果见 `evidence/runtime-results.json`（若文件尚未出现则仍在测试），不是manifest里的历史verification字段。`inputs/*.manifest.functional.json` 是所转交manifest的功能字段整理，未冒充原始完整源文档；配置保持false/null。`contracts/*.json` 是显式本地测试变体。
