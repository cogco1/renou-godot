# 人偶之心 Godot 公共程序接入候选 v001

本包是实际可运行的 **独立 primitive 测试工程**，不是已确认的正式主工程。程序入口为同目录 `project.godot`，主场景 `res://scenes/integration_lab.tscn`。共享玩家、时代状态、交互、检查点/重开和完成接口已一次实现。三关美术/独立场景由对应关卡会话接入，不并发修改公共core与项目配置。

实际输出根：`E:\PROJECTS\04_COMPETITIONS_竞赛\人偶之心\tmp\20261007_Godot_MVP_Integration`。已核实既有同步过滤 `tmp/**`，本包不会经该同步任务上传；未修改同步配置或源工程。

## 明天直接开做

1. 程序先读 `docs/API.md`。三个关卡各自按adapter方法接实际锚点、交互范围、目标时代安全碰撞、派生外观和失败恢复。
2. 美术/关卡先读 `docs/ASSET_HANDOFF.md`：资产节点、轴心、桥方向和断口宽度与primitive场不同，不得将测试场坐标当正式城市坐标。
3. 用 `Run.ps1 -Level 1/2/3` 启动。`Test.ps1` 重跑真实headless测试，`Test.ps1 -Capture` 为非headless自动操作截图；渲染时遵守现有 `bridge-render.lock` 协作规则。
4. 负责人姓名未指定，不填造人名。正式密码、城市落点、past柜门灯状态和正式主工程仍待确定。

## 本机核查与启动

E盘已执行 `--version`：`4.7.2.stable.official.ed1daf0bf`。主用现有便携版：

```powershell
$godotExe = 'E:\PROJECTS\04_COMPETITIONS_竞赛\人偶之心\tmp\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
$candidateRoot = 'E:\PROJECTS\04_COMPETITIONS_竞赛\人偶之心\tmp\20261007_Godot_MVP_Integration'
& $godotExe --headless --path $candidateRoot --editor --import --quit
& $godotExe --headless --path $candidateRoot --fixed-fps 60 -- --test
# 人工试玩（同一入口；1桥、2阀门、3柜）：
& $godotExe --path $candidateRoot -- --level=1
# 编辑器：导入本包project.godot，F6运行integration_lab.tscn，或F5运行main scene。
```

没有升级或安装引擎。D盘另有同名便携安装。首次只读深度7扫描未发现现有工程；再次在三个已知E/D/C项目根最大深度12、排除缓存与本候选、未达到目录上限的扫描找到三个**当轮各关新建LOCAL STUB**，清单/范围/时间见 `evidence/project-inventory.json`。这些都注明不是正式工程，不能据此擅选主项目。未启动或改写他人新工程。

本候选没有autoload或外部插件，service在main场景中创建。输入映射在 `integration_lab.gd::_setup_input()` 建立，三个入口共用同一player与state service。

## 操作和三个流程

WASD移动、鼠标视角、Space跳、E交互、Q时代、R检查点恢复、T整关重开、1/2/3换关。点击画面捕获鼠标，Escape释放；密码界面Escape取消、Enter/按钮提交。UI期间移动、视角、世界交互、Q都阻断，R/T测试快捷键也不抢密码输入；共享reset接口仍可由死亡或程序调用。

| 入口 | 操作流程 | 未定内容 |
|---|---|---|
| 1 / --level=1 断桥 | 出生Q到past，走过完整桥到对岸，Q回present，走进出口。两岸蓝色地块为实际临时检查点/安全平台。 | primitive断口7.8m通过跳跃失败测试；资产5.5m断口需关卡接入后再验。摘镜flag是观察项，不是隐形完成锁。 |
| 2 / --level=2 阀门 | 出生Q到past，接近左侧阀门E，Q回present，走过已安全蒸汽通道进出口。 | 侧门是临时primitive；最终资产的-Z阀轴、+X门行程单独绑定。 |
| 3 / --level=3 配电箱 | Q到past，靠近左侧柜E读码；Q回present，E打开输入，提交0427，靠近稍前方按钮E，门灯开启后进出口。 | **0427仅本地fixture，非确认剧情密码**。正式模板final_code=null/test_mode=false；past柜门临时关闭，不继承present电源结果。 |

三关均可按R/T恢复；completed仍允许自由移动、安全切时代、幂等互动和重开。没有跨程序存档、背包、武器、完整UI或UE实现。

## 验证与证据

- `evidence/runtime-results.json`：最终Godot headless **43/43通过**。分开标记engine_semantics、engine_physics、engine_player_route。对应完整日志 `runtime-final.log`。
- 断桥与阀门各两次出生到出口通过；配电箱一次完整路线通过。路线使用真实Input action、CharacterBody3D.move_and_slide、实体碰撞与真实位置触发；无路线传送/直接写flags。密码测试通过真实LineEdit提交信号，未伪称人工键盘测试。
- 测试覆盖：重复ID、不可写状态副本、错误时代优先、范围、同帧去抖、幂等、跨时代/跨关保留、安全地面/目标体积拒绝、快照恢复、重开、UI焦点取消/错误重试、生产缺码、未解锁按钮/出口、完成一次通知及重开、present断桥跳跃失败、蒸汽死亡恢复、门灯与碰撞派生。
- `evidence/schema-validation.json`：9/9 manifest静态schema通过；不算Godot运行测试。`inputs/reference_contracts/公共验收.tests.json`是来源规格，未声称逐条由通用JSON执行器重放；等义覆盖映射见 `docs/TEST_COVERAGE.md`。
- 首次导入有一个origin类型推断错误，已修复；最终运行无该错误。历史首轮日志留存，不混成最终版本结果。
- 实际渲染截图、冷启动回退验证的最终状态见 `evidence/delivery-status.json`。真人手动全流程、源GLB在本公共场的动态接入、正式主工程和导出exe均**未跑**。

## 修改和输入边界

新增所有文件只在本独立根目录；可执行文件为 `project.godot`、`core/state_service.gd`、`core/player.gd`、`scenes/integration_lab.gd/.tscn`、`tests/runtime_tests.gd`、`contracts/mvp_*.json`、`Run.ps1`、`Test.ps1`。文档/API、输入来源副本、日志、截图和ZIP另列于最终 `evidence/file-list.json`。

实际输入为本轮转交的公共1.0规格与三关manifest；`inputs/*.manifest.functional.json`是功能字段整理，未伪装为原始全文。随后从实际本机资产交付目录只读核对并原样复制 `manifest.json/assembly.json/test_config.json` 及公共schema/example/tests，hash见 `inputs/source-copies.json`。这些云端来源文档的原链接仅是来源信息，本会话未重新访问云端，也没把cloud/workspace当本机路径。

输出内没有源GLB模型；三个关卡会话各自接已交资产，公共层只做primitive接口验证。资产会话静态导入通过不当作本公共层的模型运行验收。

## 回退

`release/mvp_core_v001.zip` 为排除`.godot`缓存的完整独立可运行包。解压到新目录即可运行，`release-validation.json`记录对新解压目录的真实Godot导入、完整测试及第二次启动结果。包内含校验文件；ZIP的SHA256在旁边的 `.sha256`。恢复使用新解压副本，不覆盖未知正式工程。
