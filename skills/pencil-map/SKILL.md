---
name: pencil-map
description: 为当前项目建立或更新设计稿到代码页面的映射表 .pencil-bridge/design-map.yaml。当用户说「建映射」「关联设计稿和页面」「这个页面在哪个设计稿里」「初始化设计映射」时使用。
metadata:
  version: "1.0.0"
  suite: pencil-bridge
---

# /pencil-map（Codex: $pencil-map）

## 何时使用

首次为项目建立设计稿到代码页面的映射，或设计稿 / 代码页面变动后更新映射时。

## 先读这些

- `../pencil-bridge/references/design-map.md`（**本命令的全部细节都在这里**：`design-map.yaml` 的 schema、八步建立流程与重跑语义）
- `../pencil-bridge/references/document-routing.md`（会话启动检查单、哨兵范式、`filePath` 路由与静默回退）
- 与探测到的栈对应的那一份分栈 reference（**按探测到的栈只读对应那一份**）：`../pencil-bridge/references/stack-flutter.md` / `../pencil-bridge/references/stack-kotlin.md` / `../pencil-bridge/references/stack-web.md`

## 输入

无必填参数。可选：用户指定的设计文件、既有映射清单路径、或用户主动输入的节点名 / 页面名清单。

## 流程

建立与更新流程**逐条**执行 `../pencil-bridge/references/design-map.md` §3「建立流程八步」与 §4「重跑语义」；本命令不复述这两节，避免两处漂移。

进命令先按 `../pencil-bridge/references/document-routing.md` §7 跑**会话启动检查单**与哨兵校验（`pencil-sync` / `pencil-assets` 同样要求）。

其中与本命令强绑定的三个决策点（其余细节见上述两节）：

1. 栈探测命中多个时**记为多栈**，并加载对应的多份分栈 reference。但**栈的宿主/平台壳目录**（Flutter 的 `android/` / `ios/` / `macos/` / `linux/` / `windows/` / `web/`）属于其父栈，**不计入 `stacks`**；**依赖目录**（`node_modules/` / `.dart_tool/` / `Pods/`）与**构建产物目录**（`build/` / `dist/`）一律**不参与探测**（不要扫进去）；**仓库内自带的工具链 / 第三方源码副本**（如 `tools/<sdk>/`、`vendor/`、`third_party/`）与 **`.gitignore` 忽略目录**同样不参与探测（判据是它是不是本项目的应用代码；忽略目录可用 `git check-ignore -q <目录>` 判定）。命中数明显异常多（例如几十到上百）时，先怀疑扫进了 vendored 副本或忽略目录，**收敛后**再出候选配对表。
2. 候选配对表**必须经用户确认后才写文件**。
3. 两种模式都要支持：导入既有清单（作为导入源读取，不取代它），或用户**主动输入节点名与页面名**逐条建映射。

## 输出契约

`<projectRoot>/.pencil-bridge/design-map.yaml`（项目根 = 含 `.git` 的最近祖先；无 `.git` 则回落 cwd）。写完后给出：写入路径 + 本次新增 / 更新的条目摘要 + 仍待确认的候选。

**本设计不规定 `.pencil-bridge/` 的 git 待遇**（spec 对此留白）：建议把 `design-map.yaml` 纳入版本控制共享，`backups/` 与 `assets/` 按需忽略。

## 铁律

- **用户确认前不写文件** —— 先出候选配对表，绝不自动落盘。
- 节点定位**优先用 id**（名字可能不唯一）。
- 哨兵不符 ⇒ **停机报告，不重试**；静默回退没有错误信号。
- 重跑**原地更新**，不重建文件，不丢用户手加字段。
