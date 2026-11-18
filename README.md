# 宇宙银河机甲 · UrhoX 发布包（v1.1.2）

[UrhoX](https://www.tapTap.cn) / TapTap 嵌入式容器平台的 Lua 版发布包，可直接作为 UrhoX 工程导入。

- 版本号以仓库根目录 `VERSION` 文件为准：**1.1.2**
- 入口脚本：`scripts/main.lua`
- 说明：包内 `docs/RELEASE_NOTES.md` 的正文仍写作 v1.1.0（内容为累积发布说明），本仓库未改动其原文件。

## 目录

| 路径 | 内容 |
|---|---|
| `scripts/` | 游戏脚本：`cosmic/`（GameApp、GameUI、Hub、Sdk、Sound）、`game/`、`jsrt/`（由网页版源码转换的运行库）、`voxeldata/`（含 `models/` 体素模型数据） |
| `assets/Sounds/` | 音效与 BGM，19 个 `.ogg`，路径引用为 `Sounds/xxx.ogg` |
| `store/` | 商店素材：512×512 图标、6 张 1920×1080 截图、宣传片 mp4（1920×1080 / H.264 / 约 30 秒） |
| `docs/` | 发布说明、提审清单、UrhoX 移植说明、网页版一致性对照、TapTap 制造接入指南、隐私政策与用户协议模板 |
| `.project/` | UrhoX 工程元数据（`resources.json` / `settings.json`） |
| `VERSION` | 版本号文件 |

## 玩法概览

6 台体素 Q 版机甲（S / SS / SSR / SSSR 四档）、6 位驾驶员；3 个章节（每章 6 个星域，含 6 种目标 + 首领）、危险等级 1~10、无尽模式、每日挑战；1080 张技能卡牌 + 天赋芯片 + 元素反应 + 卡牌进化；召唤、每日登录、任务与成就。

## 使用前请注意

1. 本包在模拟引擎中完整跑通，**尚未在真正的 UrhoX 编辑器 / 真机上验证**。首次导入后请先试跑，并核对 `docs/UrhoX移植说明.md` 的「未验证」清单（旋转方向、枪口位置、触控坐标、性能、SDK 行为）。
2. Lua 版在水平面上飞行，特效较网页版简化。
3. `docs/隐私政策模板.md`、`docs/用户协议模板.md` 仅为模板，提审前必须补全运营主体并经法务审核。

## 相关仓库

- 完整工程（源码 + 构建工具）：<https://github.com/mmb9w48ff7/GalaxyMecha>
- 网页版单文件可玩版：<https://github.com/mmb9w48ff7/GalaxyMecha-Web>
