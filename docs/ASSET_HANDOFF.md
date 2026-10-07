# 已交白模的接口核对

只读来源：`E:\PROJECTS\04_COMPETITIONS_竞赛\人偶之心\00_资产库_待上传\20261007_三关最小独立资产包\v001`。2026-10-07实际读取README、三关manifest/assembly，原样本地复制到`inputs/asset_delivery`，hash见`inputs/source-copies.json`。只复制接入所需的规格JSON，不改源资产；GLB接入由三关各自负责，本公共primitive场不重复集成场景。

公共版本、level_id、flags和device_id相符。生产原始模板仍关闭测试码；任何运行入口启用测试码必须单独声明。

| 关卡 | 与primitive场不同，接手时必须更换 |
|---|---|
| 桥 | 模型沿X，18m长；资产断口代理5.5m。本公共场前进-Z，断口7.8m。公共场通过跳跃测试**不能证明**资产5.5m断口通过。入口ANCHOR_ENTRY，检查点ANCHOR_SAFE_RETURN_ENTRY，出口ANCHOR_EXIT。 |
| 阀门 | imported_rotation_axis=local_negative_Z，主手轮MOV_Handwheel_L；次手轮MOV_Handwheel_R保留不绑定。隔离门PIVOT_IsolationGate沿+X行程2.65m，碰撞PIVOT_IsolationGate_Proxy/COL_IsolationGate要同步。不能把公共场临时wheel.rotation.x或z向侧门位移直接复用。 |
| 配电箱 | 入口MARKER_ENTRY_PROPOSAL，检查点MARKER_SAFE_RETURN_PROPOSAL，出口MARKER_EXIT_PROPOSAL。PIVOT_START_BUTTON沿-Z行程0.025m；PIVOT_EXIT_DOOR沿+X行程1.85m，与COL_EXIT_DOOR同步。本场临时向上开门仅验证接口。 |

GLB已做一次 `(x,y,z)Blender -> (x,z,-y)Godot` 米制Y-up转换，原生导入不要再次-90°或×100。primitive采用Godot原生BoxMesh，不牵涉源轴转换。保留源场景局部原点；正式城市city_placement仍null。

COL代理生成实体；AREA/PROXY危险/触发区域只能作为触发范围，不能生成走得过的空气块。静态导入证据属于资产会话报告；本程序包不将其记作自己完成的三关模型运行验收。
