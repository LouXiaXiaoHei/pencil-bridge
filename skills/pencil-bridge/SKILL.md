---
name: pencil-bridge
description: 通过 pencil MCP 连接 Pen.app 的设计稿，把设计同步到代码、提取素材、或把代码改动反写回设计稿。当用户提到设计稿、pen 文件、Pen.app、设计同步、设计变量、图标、提取素材时使用本技能；它会引导你选用 /pencil-init、/pencil-map、/pencil-sync、/pencil-assets 中的一条。
metadata:
  version: "1.0.0"
  suite: pencil-bridge
---

# pencil-bridge

## When to Use This Skill

用户提到设计稿 / `.pen` / Pen.app / 设计同步 / 设计变量 / 提取图标素材时进入。
**先判断该用哪条命令**，不要自己临场拼流程：

| 用户想做什么 | 用哪条 | Codex 里写 |
|---|---|---|
| 连不上、检查配置 | `/pencil-init` | `$pencil-init` |
| 建立/更新设计与页面的映射 | `/pencil-map` | `$pencil-map` |
| 按设计改代码，或把代码改动写回设计 | `/pencil-sync` | `$pencil-sync` |
| 导出位图/矢量/图标引用/变量 token | `/pencil-assets` | `$pencil-assets` |

用户没指明时，按这个顺序问：项目里有 `.pencil-bridge/design-map.yaml` 吗？没有 → `/pencil-map`；有 → 看意图选 sync 或 assets。

## Critical Rules

1. **每次 `execute` 必须传 `filePath`**（`file://` 绝对 URI）。不传就会命中「最后聚焦的文档」兜底分支，**且不报错**。
2. **`get_app_state` 绝不能用来判断写入目标** —— 它跟随用户焦点，永远不可信。
3. **写前必读哨兵**：确认连的是目标 `.pen`。哨兵不符 → **立即停机，不重试**。
4. **提醒用户不要关掉目标 `.pen`**。未打开的文档会静默回退到焦点文档。
5. **`Update` 绝不带 `type`**；**不传 `children`**（要改结构用 `Replace`）。
6. **`SetVariables` 禁止 `replace: true`** —— 它会删掉未列出的变量并清空 themed 值。
7. **不假设写操作已落盘** —— 收尾必须提示用户保存。
8. **不读凭据文件**（清单见 `../pencil-bridge/references/write-safety.md`）。
9. **图标取不到矢量源码** —— 只能产出「库名 + 图标名」引用。
10. **禁止无 visitor 全量读**：`Get("document", {depth:0})` 会直接报错。

## 栈探测

在需要栈相关约定时（`/pencil-map` 建映射、`/pencil-assets` 出 token），按文件判定：

| 命中文件 | 栈 | 加载 |
|---|---|---|
| `pubspec.yaml` | Flutter | `../pencil-bridge/references/stack-flutter.md` |
| `build.gradle` / `build.gradle.kts` / `AndroidManifest.xml` | Kotlin/Android | `../pencil-bridge/references/stack-kotlin.md` |
| `package.json` | Web | `../pencil-bridge/references/stack-web.md` |

命中多个 = 多栈项目，`design-map.yaml` 用 `stacks` 列表，各栈分别加载。

## Workflow

1. 读 `../pencil-bridge/references/document-routing.md`，跑**会话启动检查单**（Pen 在跑？design-map 存在？哨兵命中？）。
2. 按上面的路由表进入对应命令。
3. 任何需要文档上下文的**读**操作也要带 `filePath`（本技能不解决焦点漂移问题，只能绕开）。
4. 涉及写入时，**先读 `../pencil-bridge/references/write-safety.md` 并逐条执行**。

## Common Mistakes to Avoid

| 错误 | 后果 | 正确做法 |
|---|---|---|
| 用 `get_app_state` 确认「现在连的是哪个文档」 | 读到用户焦点所在的**别的项目**的稿子 | 用 `filePath` + 哨兵 |
| 写 `Get("document", {depth:0})` 想「先看全貌」 | 直接报错，浪费一轮 | 用 visitor 收集需要的字段 |
| 以为 `Get(visitor)` 会返回匹配节点 | 拿到一整个 `false` 数组 | visitor 内部用局部数组 `push` |
| 在 `Update` 里带 `type` | 走整节点替换路径，行为不可预期 | 只给要改的属性 |
| 用 `Delete` 隐藏一个组件实例的后代 | 直接抛 `Cannot delete descendants of instances!` | 改为 `enabled: false` |
| 以为图标能导出 SVG | Pen.app 不提供图标源码，`Export` 无 svg 格式 | 输出库名 + 图标名引用 |
| 用 `strokeWidth` 原值写进 viewBox | 描边粗细差一个比例 | 见 `../pencil-bridge/references/assets-extraction.md`（换算**待实证**） |
| 写完就宣布完成 | 可能根本没落盘 | 提示用户保存 |

## Resources

- `../pencil-bridge/references/mcp-toolbox.md` —— 5 个工具、`execute` API 全貌、visitor 写法、`Print` 通道
- `../pencil-bridge/references/document-routing.md` —— `filePath`、静默回退、哨兵、启动检查单
- `../pencil-bridge/references/write-safety.md` —— 写操作安全规程全文
- `../pencil-bridge/references/design-map.md` —— `.pencil-bridge/design-map.yaml` 协议
- `../pencil-bridge/references/assets-extraction.md` —— 四类素材的取法与坑
- `../pencil-bridge/references/init-and-mcp.md` —— 逐 harness 的 MCP 配置细节
- `../pencil-bridge/references/stack-flutter.md` / `../pencil-bridge/references/stack-kotlin.md` / `../pencil-bridge/references/stack-web.md` —— 分栈约定
