# mcp-toolbox —— pencil MCP 工具面与 `execute` API

本文是 pencil-bridge 套装里唯一的 MCP API 参考。来源：spec §3.1（设计规范 ':35-68'）、§3.2（':91-108'），以及写 API 手册第 3 节（':140-158'，路径语法汇总见第 7 节 ':355-388'）。
**关键签名、代码块与报错原文逐字保留，不要改写。**

---

## 1. 只有 5 个工具

本机 pen.dev MCP 暴露的工具**只有 5 个**：

| 工具 | 用途 | 备注 |
|---|---|---|
| `execute` | 在文档上执行一段 JavaScript（canvas API：`Insert` / `Update` / `Copy` / `Get` / `Print` / `Export` …）。**唯一能通过脚本读写文档内容的工具**；schema `required = ["filePath"]`，所以**必须**传 `filePath`。 | 靠参数 `filePath` 路由文档 |
| `get_app_state` | 读 pen.dev 应用的当前状态、当前用户选中项，以及上手所必需的信息。 | **没有 `filePath` 参数** |
| `get_style` | 加载 `.pen` 工作用的视觉风格原型（可配置的字体 / 颜色 / 图像参考）。风格只提供参考值，**不保存变量**。 | **没有 `filePath` 参数** |
| `read_skill` | 读 pen.dev 技能文档：`SKILL.md`，以及它引用的 `execute.md` / `guide/*.md` 等文件。 | **没有 `filePath` 参数** |
| `browser` | 用应用内置浏览器操作真实网站：`load-page` / `import-to-canvas` / `screenshot-to-canvas` / `return-element` / `return-screenshot` / `cdp`。 | **声明了 `filePath`**：schema `required = ["filePath","action"]`，描述文案为 "An optional file path to access a .pen file."；**是否实际参与文档路由【未验证】**，不得据此断言 |

**旧文档里的 `pencil_batch_get` / `pencil_get_screenshot` / `pencil_get_variables` 不存在，不得引用。**

CLI 参数只有 `--app <name>`（决定 socket 名）、`--agent <自由文本>`、`--conversation_id <id>`、`--enable_spawn_agents`。**没有任何指定 `.pen` 文件的参数** —— 本设计只依赖 `execute` 的 `filePath`（`browser` 的 `filePath` 未验证，不采用）。

> 三个没有 `filePath` 的工具（`get_app_state` / `read_skill` / `get_style`）永远命中「最后聚焦的文档」兜底分支。`browser` 的 schema **确实声明了** `filePath` 且列在 `required` 里，但它**是否实际参与文档路由【未验证】** —— 只陈述 schema 事实，不对其路由行为下结论，也不要依赖它来选文档。所以 **`get_app_state` 绝不能用来判断写入目标**；文档路由细节见 `../pencil-bridge/references/document-routing.md`。

---

## 2. `execute` API 全貌

以下是 `execute` 的 API 面（**逐字签名**）：

```js
Insert(parent: string, nodeData: Child): string
Update(path: string, updateData: Child): void
Replace(path: string, nodeData: Child): string
Move(path: string, parent: string | undefined, index?: number): void
Delete(path: string): void
Copy(path: string, parent: string, copyNodeData?: Child): string
SetVariables(variables: Record<string, VariableDefinition>, replace?: boolean): void
Generate("ai" | "stock" | "svg", nodeId, prompt)      // 写文档，返回 void
Generate("vectorize-image", nodeId, imageUrl)          // 写文档，返回 void
Generate("remove-background", imageUrl): string        // 不写文档，返回新 asset url
Generate("replace-background", imageUrl, prompt)       // 不写文档，返回新 asset url
Get(path, options?) | Get(path, visit, options?) | Get(visit, options?)
GetVariables(): { variables, themes? }
FindEmptySpace({ width, height, direction?, padding?, nodeId? })
Print(...values)
TakeScreenshot(nodeIds: string[])
Export(nodeIds, "png"|"jpeg"|"webp"|"pdf"|"html-tailwind"|"html-css", outputPath, options?)
```

选项对象：

- `GetOptions`：`depth` / `resolveVariables` / `resolveInstances` / `includePathGeometry`
- `ExportOptions`：`scale`（默认 2）/ `quality` / `includeHtmlScaffold` / `includeLayerNames` / `includeLayerIds`

两条硬性行为约束（**逐字**）：

- 每次 `execute` 是**独立作用域**；跨调用共享状态只能靠**不带 `const`/`let` 声明的赋值**。
- 失败必须用响应里返回的 `editId` + `edits: [{find, replace}]` 修补后重跑；不能同时再给 `input`。

`editId` 修补的调用语义（`execute` 工具 schema）：每个 edit 把失败片段里的 `find` 换成 `replace`，然后**整段修补后的片段从头重跑**；edits 按顺序生效，每个 `find` 必须匹配「已被前面 edit 改过」的片段。用 `editId` 时**不要**再传 `input`。修补后若再次失败，继续用同一个 `editId` 下发 `edits`。

---

## 3. visitor 的正确写法

`Get` 的 visitor 语义（**容易写错**）：

- `Get(visitor)` 返回的是**「每个节点上 visitor 的返回值」组成的数组，长度 = 遍历节点总数**，不是过滤结果。
- **正确写法是 visitor 内部用局部数组累积，visitor 本身不返回值**：

```js
const out = [];
Get(x => {
  const n = x && x.node ? x.node : x;   // 兼容 ctx / node 两种签名
  if (n && n.type === "path") out.push({ id: n.id, name: n.name });
}, { includePathGeometry: true });
Print("RESULT:", JSON.stringify(out));
```

**反面写法**：`Get(n => n.type === "path")` 不会返回匹配到的 path 节点，而是得到一个**一整个 `false` 数组**（长度 = 遍历节点总数，除匹配项外全是 `false`）。

**禁止无 visitor 全量读**：`Get("document", {depth:0})` 报错

```
Reading the whole document without a visitor would return everything! Pass a visitor to collect only what you need (e.g. Get(n => n.name)), or target a specific node.
```

---

## 4. `Print` 是唯一输出通道

- **`Print` 是唯一的输出通道**；不 `Print` 就拿不到任何数据。
- 任何返回值都只在 `execute` 的响应里出现，且只经由 `Print`。所以 `GetVariables()` 也必须写成 `Print(GetVariables())` 才看得到；`GetVariables()` 返回 `{ variables, themes? }`。
- `Get` / `Insert` / `Export` 等有返回值的 API 同理：想读到值，必须自己 `Print(...)` 出来。

```js
Print(GetVariables());
```

---

## 5. 根别名与 path 语法

**根别名**：`document` / `root` / `#document` / `#root` 都是根别名；`document` 只能当 `Insert` 的 `parent` 或 visitor 的起点。

**`/` 只用于组件实例嵌套**：

- path 是**节点 id**，或**组件实例内节点**的斜杠路径 `instanceId/childId`（可任意深度嵌套）。
- `/` **只对组件实例嵌套合法**，普通层级结构**不能**用 `/` 拼接；**不支持索引**（`Move` 的 `index` 是**参数**，不是 path 段）。
- name 也能当 path 段，但**仅在其全局唯一时才安全**；多命中报 `Found multiple descendants named 'X'`，此时必须改用 id / path。
- 只读、带 `Get` 返回的节点对象时，传给 `Update` / `Copy` 等的应当是它的 `.id`，不是节点对象本身。

`[文档]` 原文（逐字）：

> "The `path` argument (used by `Get`, `Copy`, `Update`, `Replace`, `Move`, `Delete`) is a node ID, or a slash-separated path to a node nested inside a component instance (`instanceId/childId`). Slashes are only valid for component-instance nesting, not normal layer structure, and work for any nesting depth."
>
> "Targets - `path` and `Insert`'s `parent` - are always id/path strings: never pass a node object; when holding a node from `Get`, pass its `.id`. Returned ids concatenate directly: `cardId + \"/childId\"`"

不确定 id 时，用 visitor 按 name 精确定位再更新，例如：`Get(n => n.name === "Primary Button" && Update(n.id, {...}))`。

---

## 相关 reference

- `../pencil-bridge/references/document-routing.md` —— `filePath`、静默回退、哨兵、会话启动检查单
- `../pencil-bridge/references/write-safety.md` —— 写操作安全规程、`editId` 失败修补的确切流程
- `../pencil-bridge/references/assets-extraction.md` —— `Export` / `Generate` 出素材的用法与坑
