# 仓库和 Google Drive 怎么配合

一句话：**代码放 Git，素材放 Drive。从 Drive 拿哪个版本，记在 `assets/manifest.json`。**

## 1. Drive 入口

Drive 链接要有项目共享权限才能打开，没有权限的人只能看到这些链接，打不开。

| 用途 | Drive 文件夹 |
|---|---|
| 项目根「游戏GOGOGO」 | https://drive.google.com/drive/folders/12WDue6MmxP1OMErUOYwnzaJQf0P9ez7G |
| 资产库：打包好的正式资产，每个资产一个文件夹，每个版本一个子文件夹 | https://drive.google.com/drive/folders/1zoyNYlk9QRCmHoj_DXgWnStPC9lUfehV |
| 最新版场地模型：全城合并场地 .blend，原地更新 | https://drive.google.com/drive/folders/19lfETaRdn-ccmQhFcoC_vMFuozc07MxV |
| 片区：PCG 片区文件，每个片区一个 .blend，索引是 README_片区.md | https://drive.google.com/drive/folders/1pEYfCWF7b06RdJ8NQCktTavRnCwVJ1e8 |
| 视效方案：光照和材质预设、Godot 视效样片 | https://drive.google.com/drive/folders/1Maz-jLRLSRLdbNfc4Gscjlp_pj8k2lZ_ |
| UIUX 交互原型协作 | https://drive.google.com/drive/folders/1w8XZzuGAEx5pz03OAAfOWIIxl5OGT9oB |
| 技术评审入口，先读 00_说明.md | https://drive.google.com/drive/folders/1CuobIAZcxhXd42IzuWjKv1gssTs_kg8P |

资产库的上传规则在资产库根目录，文件名是版本号最高的《00_资产上传规则》。命名格式是 `<前缀>_<名称>`，例如 `BLD_HillsideTypeKit`。版本文件夹叫 `v<NNN>_<日期>`，里面放 ZIP、轴测图和 README。

## 2. 资产怎么进仓库

1. 在 Drive 资产库里找到资产和版本，比如 `建筑/BLD_OfficeBlockKit/v002_20261007/`。下载 ZIP，核对它的 SHA-256 和该版本 README 里写的一致。
2. 解压后，只把 Godot 要用的导出件（`export/*.glb`，以及它们引用的贴图）拷到仓库：
   `assets/<类别>/<资产ID>/<版本>/…`
   例如 `assets/建筑/BLD_OfficeBlockKit/v002_20261007/export/…`。
   .blend 源文件不进仓库，留在 Drive。
3. 在 `assets/manifest.json` 里加一条，写清资产 ID、版本、Drive 文件夹链接、ZIP 的 SHA-256、拷进来的文件和各自的 SHA-256。
4. 运行 `tools/verify_assets.ps1`，核对仓库里的文件和 manifest 一致。
5. 提交。GLB 和图片会自动走 Git LFS（见 `.gitattributes`）。

## 3. 规则

- **仓库里的素材不改。** 模型要改，回到 Drive 出新版本 `v<NNN+1>`，再按第 2 节重新导入。旧版本可以留着回退，manifest 里标明当前用哪一版。
- **版本只往上走。** manifest 里一个资产同时只有一个“当前版本”。换版本请单独提一个 PR，PR 描述里写上 Drive 版本文件夹链接和“本版变化”。
- **不要把整个 ZIP 或 .blend 提交进来**，太大了，而且 Drive 上已经有。
- **合并场地和片区文件不进仓库。** 关卡要用的城市块，按片区导出 GLB 后，也照资产的方式导入。
- **坐标换算**：Blender (x, y, z) → Godot (x, z, −y)，yaw 不变，单位米。资产的原点在基底中心，正面朝 Blender 的 −Y。
- 碰撞、交互节点这类数据和 GLB 一起导入。它们以 Drive 资产包里的为准，仓库里不手改；要改就回 Drive 出新版本。

## 4. 谁负责什么

- Drive 资产库的打包和上传：项目里的协调会话（Claude）。
- 仓库代码和场景：程序同学，改动走 PR，`main` 要保持能运行。
- 某个资产在仓库里要换版本：谁用谁提 PR，按第 2 节做。
