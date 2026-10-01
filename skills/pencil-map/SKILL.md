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

1. **探测项目栈**：按 `pubspec.yaml` / `build.gradle(.kts)` + `AndroidManifest.xml` / `package.json` 判定；命中多个则记为多栈，加载对应的多份分栈 reference。
2. **定位设计文件**：优先读 `design-map.yaml`；不存在则询问用户，或用只读手段给出候选（只作建议、不作判定）。
3. **建立哨兵**：读设计文件顶层节点名，挑该项目独有的 1–3 个作为 `sentinel`。
4. **提取设计结构**：用 visitor 收集顶层 frame（`context` 属性里的设计说明一并留存）。
5. **扫描代码页面**：按分栈 reference 的约定找页面入口。
6. **候选配对表 → 用户确认**：先给候选配对表，**用户确认后才写文件**。
7. **支持两种模式**：导入既有清单（如项目里已有的映射清单文件，作为导入源读取、不取代它），或用户**主动输入节点名与页面名**逐条建映射。
8. **重跑**：已存在的条目**原地更新**，不重建文件；用户手工添加的字段（注释、自定义键）**保留**。

## 输出契约

`<projectRoot>/.pencil-bridge/design-map.yaml`（项目根 = 含 `.git` 的最近祖先；无 `.git` 则回落 cwd）。写完后给出：写入路径 + 本次新增 / 更新的条目摘要 + 仍待确认的候选。

## 铁律

- **用户确认前不写文件** —— 先出候选配对表，绝不自动落盘。
- 节点定位**优先用 id**（名字可能不唯一）。
- 哨兵不符 ⇒ **停机报告，不重试**；静默回退没有错误信号。
- 重跑**原地更新**，不重建文件，不丢用户手加字段。
