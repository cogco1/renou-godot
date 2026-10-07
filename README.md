# 人偶之心 · Godot 正式工程

《人偶之心》Godot 工程的代码仓库，2026-10-07 建立。

起点是“机关接入测试工程 v001”：玩家、时代切换、交互、检查点和三关（断桥、阀门、配电箱）都可以单独跑。它是正式工程的骨架，还不是完整游戏。旧版说明见 `README_MVP集成说明.md`。

## 分工：Git 放代码，Drive 放素材

| 放哪 | 放什么 |
|---|---|
| **本仓库（Git）** | Godot 工程：脚本（.gd）、场景（.tscn / .tres）、项目配置、测试、实际用到的导出 GLB 和贴图（走 Git LFS） |
| **Google Drive「项目共享文件 / 游戏GOGOGO」** | 资产库（打好包的模型）、合并场地 .blend、设定、方案、视效样片 |

- **Drive 链接和素材导入规则：见 [docs/DRIVE_LINKS.md](docs/DRIVE_LINKS.md)**（素材版本记在 `assets/manifest.json`，用 `tools/verify_assets.ps1` 核对）。
- 资产入口：Drive 上的 `资产库/`，每个资产一个文件夹，ZIP 里有 GLB 和 README。
- 评审入口：Drive 上的 `技术评审_20261007/00_说明.md`。
- 关卡方案：Drive 上的 `人偶之心_E盘工作区/20261007_红区关卡拆分与合并方案/publish/红区三关合并方案.html`。
- 坐标换算：Blender (x, y, z) → Godot (x, z, −y)，yaw 不变；单位米。

## 运行

- Godot 4.7.2（4.x 都行，以 4.7.2 实测为准）。
- 打开 `project.godot`，主场景是 `res://scenes/integration_lab.tscn`。
- PowerShell 下：`.\Run.ps1 -Level 1`（1/2/3 分别是断桥、阀门、配电箱），`.\Test.ps1` 跑无界面测试。
- 接口说明在 `docs/API.md`，资产接入在 `docs/ASSET_HANDOFF.md`。

## 约定

- 不提交 `.godot/` 缓存（已写进 .gitignore）。
- 大文件（glb、png、jpg、wav 等）走 Git LFS（见 .gitattributes）。第一次 clone 前先运行 `git lfs install`。
- 改动走分支加 PR，`main` 保持能运行。
- 美术资产不在这里改：模型改动回到 Drive 资产库出新版本，再把导出的 GLB 拷进本仓库。
