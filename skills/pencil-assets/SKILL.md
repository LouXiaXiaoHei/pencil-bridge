---
name: pencil-assets
description: 从设计稿提取素材：位图、矢量 path、图标引用、设计变量 token。当用户说「导出图标」「提取素材」「把设计变量导出成 CSS/Dart/colors.xml」「导出 SVG」时使用。
metadata:
  version: "1.0.0"
  suite: pencil-bridge
---

# /pencil-assets（Codex: $pencil-assets）

## 何时使用

要从设计稿导出位图、矢量 path、图标引用或设计变量 token 时。

## 先读这些

- `../pencil-bridge/references/assets-extraction.md`（**本命令的全部细节都在这里**：四类产物的取法表、位图路径解析、矢量字段与坑、三栈 token 格式、提取边界）
- `../pencil-bridge/references/document-routing.md`（会话启动检查单、哨兵范式、`filePath` 路由与静默回退）
- 与探测到的栈对应的那一份分栈 reference（**按探测到的栈只读对应那一份**，用于 token 的输出格式与落点）：`../pencil-bridge/references/stack-flutter.md` / `../pencil-bridge/references/stack-kotlin.md` / `../pencil-bridge/references/stack-web.md`

## 输入

产物类别（位图 / 矢量 / 图标引用 / 变量 token，按用户指定或四类全出）+ 节点范围（可省略，省略则按 `design-map.yaml` 或用户指定的顶层 frame）。

## 流程

1. **校验文档身份**：跑会话启动检查单与哨兵。
2. **按类别取素材**：位图 → 解析 image fill 的 `url` 后直接拷磁盘文件（不走 MCP 字节流）；矢量 → `path` 节点 + `includePathGeometry: true` 取 `geometry` / `viewBox` / `strokeWidth` 等；图标引用 → 只取 `library` + `icon` 名；变量 token → `Print(GetVariables())`。
3. **按栈输出 token**：加载对应分栈 reference，按其格式与落点写出。
4. **落地**：产物写进 `<projectRoot>/.pencil-bridge/assets/<timestamp>/`。

## 输出契约

- 目录：`<projectRoot>/.pencil-bridge/assets/<timestamp>/`。
- 摘要：逐个文件列出**来源节点 id**，让用户对得上「这份素材来自画布上哪个节点」。

## 铁律

- **不导出 `icon` 节点的矢量** —— Pen.app 不提供源码，`Export` 无 svg 格式，只出「库名 + 图标名」引用。
- **不导出 html-tailwind / html-css** —— 那是整页重建，不属于本命令的「提取素材」。
- `strokeWidth` 的 viewBox 换算规则**待实证**，不得当定论用。
- 变量引用默认落 `currentColor`；是否 resolve 成实际色值是**待用户确认的实现细节**，以开关形式暴露，不写死。
