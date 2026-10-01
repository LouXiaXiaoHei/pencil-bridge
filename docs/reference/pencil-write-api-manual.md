# Pencil / pen.dev MCP 写操作 API 精确手册

> 用途：为 Pen.app 的 pencil MCP 设计「从代码反写回设计稿」能力。
> 来源标注：`[文档]` = read_skill 返回的官方技能文档；`[代码交叉验证]` = 我从 `/Applications/Pen.app/Contents/Resources/app.asar` 解出的编辑器 bundle 中读到的实现/校验；`[未证实]` = 文档与代码都未明确，只能推断。
>
> 本次调研**全程只读**：仅调用 `read_skill` / `get_app_state` 与文件解包搜索，未对 `hanzi_write.pen` 执行任何 Insert/Update/Replace/Move/Delete/SetVariables/Generate。
>
> 调研时的文档版本：`app.asar` 内 `Document.version = "2.20"`；技能文档共 15 个 md（`/out/skills/pen-dev/`，其中 4 个主文档为 `unpacked` 实体文件）。

---

## 1. `read_skill()` 顶层返回的完整文件清单

`read_skill()` 返回 `SKILL.md`，其 Quick reference 表给出全部引用文档（15 个 md，含 SKILL.md 自身）。

| 路径 | 主题 |
| --- | --- |
| `SKILL.md` | 技能总纲：pen.dev 是什么、通用规则、对象/布局/SVG 规范、Style archetypes 列表 |
| `pen-schema.md` | **`.pen` 文件 schema 的 TypeScript 定义（节点类型的字段全集）** |
| `execute.md` | **`execute` MCP 工具的完整 API 参考（写操作主文档）** |
| `generate.md` | `Generate()`：AI/stock 图像、SVG、图像变换（vectorize / remove-bg / replace-bg） |
| `guide/components.md` | 组件（`reusable`）与实例（`ref`）、`descendants` 覆盖、`instanceId/childId` 路径 |
| `scripts-and-shaders.md` | 脚本节点与 shader fill |
| `whiteboard.md` | 用 live `browser` 节点做调研/对比/规划（非产品设计） |
| `guide/code.md` | 从 .pen 生成代码 |
| `guide/design-system.md` | 用设计系统组件组合界面 |
| `guide/landing-page.md` | Landing page 设计 |
| `guide/mobile-app.md` | 移动 App 设计 |
| `guide/slides.md` | 演示幻灯片设计 |
| `guide/table.md` | 表格与 dashboard |
| `guide/tailwind.md` | Tailwind CSS v4 实现 |
| `guide/web-app.md` | Web App 设计 |

补充 `[代码交叉验证]`：`app.asar` 内 `/out/skills/pen-dev/` 正好列出这 15 个 `.md`，与表一致；`SKILL.md` / `execute.md` / `pen-schema.md` / `generate.md` / `pen-schema.md` / `scripts-and-shaders.md` / `whiteboard.md` 为实体文件，其余在 `guide/` 下。

---

## 2. `Insert(parent, nodeData)`

### 2.1 签名 `[文档]`（execute.md 逐字）

```ts
function Insert(parent: string, nodeData: Child): string; // returns the inserted node's id
```

`[文档]` 原文要点（逐字）：

- `Insert`/`Copy`/`Replace` return plain id strings.
- "Insert a new node at the end of the children array of the specified parent node."
- "An insert can only be a single node, if you want to add children to it, use the returned id in the next Insert call."
- "Targets - `path` and `Insert`'s `parent` - are always id/path strings: never pass a node object..."
- "Never set `id` when creating, copying, or replacing nodes or components. pen.dev will always generate unique random IDs and override the input."
- "You MUST set the `name` property with a human readable name on every node and child node you add."
- "To access the children of a newly inserted node, read its subtree with `Get` first: `Get(rowId, {depth: 1}).children`."

**返回值**：新节点的 id，**字符串**（`[文档]` + `[代码交叉验证]`：`handleInsert` 末尾 `return l.id`）。

### 2.2 `parent` 可以是什么

| 写法 | 是否合法 | 来源 |
| --- | --- | --- |
| 某个节点的 id，如 `"Xk9f2"` 或捕获变量 `cardId` | ✅ | `[文档]`+`[代码交叉验证]` |
| 实例内路径 `"instanceId/childId"`（组件实例嵌套） | ✅（仅用于实例嵌套） | `[文档]` |
| 根别名 `"document"` | ✅ | `[文档]`（示例大量使用 `Insert(document, {...})`） |
| 根别名 `"root"` / `"#document"` / `"#root"` | ✅ | `[代码交叉验证]`：`const E4=["document","root","#document","#root"]` |
| 普通层级路径 `"父id/子id"`（非实例嵌套） | ❌ | `[文档]`："Slashes are only valid for component-instance nesting, not normal layer structure" |
| 节点对象本身（`Get` 返回的 node） | ❌ 必须传 `.id` | `[文档]` |
| 数字索引 | ❌ | 无索引寻址；见 §7 |

`[代码交叉验证]`：`handleInsert(e,n,r)` 先校验 `typeof n!="string"` → `"First argument of Insert operation must be a string!"`；随后 `cQ(manager, n)` 解析 parent（`cQ` 对根别名直接返回别名，否则用 `VB` 把 path 规范化）。若 parent 指向导入文档的节点 → 抛 `Cannot insert under ..., because it's an imported node from ...`。

### 2.3 `nodeData` 的 schema（逐节点类型）

`[文档]` `pen-schema.md` 给的 `Child` 联合类型为：

```ts
export type Child = Frame | Group | Rectangle | Ellipse | Path | Polygon | Text | Note | Prompt | Context | Icon | Script | Browser | Ref;
```

公共基类（所有节点可用）：

```ts
export interface Entity extends Position {
  /** Unique string; MUST NOT contain '/'. Auto-generated if omitted. */
  id: string;
  name?: string;
  context?: string;
  /** When true, can be duplicated via `ref` objects. Default false. */
  reusable?: boolean;
  theme?: Theme;
  enabled?: BooleanOrVariable;
  opacity?: NumberOrVariable;
  flipX?: BooleanOrVariable;
  flipY?: BooleanOrVariable;
  /** Absolute position detaches the object from parent's layout and can be absolute positioned. Default auto */
  layoutPosition?: "auto" | "absolute";
  metadata?: { type: string; [key: string]: any };
  /** Degrees CCW around top-left corner. */
  rotation?: NumberOrVariable;
}
export interface Position { x?: number; y?: number; }
export interface Size { width?: NumberOrVariable | SizingBehavior; height?: NumberOrVariable | SizingBehavior; }
export interface CanHaveGraphics extends CanHaveEffects, CanHaveStroke { fill?: Fills; }
export interface CanHaveStroke {
  stroke?: Fills;
  strokeWidth?: NumberOrVariable | { top?: NumberOrVariable; right?: NumberOrVariable; bottom?: NumberOrVariable; left?: NumberOrVariable };
  strokeLinecap?: "butt" | "round" | "square";
  strokeLinejoin?: "miter" | "bevel" | "round";
  strokeAlignment?: "inner" | "center" | "outer";
}
```

> 注意 `[文档]`：`id` 在 schema 里标为必填但"Auto-generated if omitted"，且**永远不要手写**。除 `type` 外没有真正强制的字段，但每类节点有其语义必填项（见下表）。

| `type` | 必填 | 该类型独有 / 关键可选字段 | 备注 |
| --- | --- | --- | --- |
| `frame` | `type` | `layout` `gap` `padding` `justifyContent` `alignItems`（来自 `Layout`）；`clip?`；`placeholder?`；`slot?: false \| string[]`；`children?` | **唯一可带 `layout`/`padding` 的容器**；`Rectangleish` 故有 `fill`/`stroke`/`cornerRadius`。默认 `layout=horizontal, width=fit_content, height=fit_content, clip=false` `[文档]` |
| `group` | `type` | `children?`；仅 `CanHaveEffects` | **没有 `fill`/`stroke`**，不能设 `layout`/`padding` |
| `rectangle` | `type` | `cornerRadius?: NumberOrVariable \| [4项]` | |
| `ellipse` | `type` | `innerRadius?`（0=实心,1=空心）；`startAngle?`；`sweepAngle?`（-360..360） | |
| `polygon` | `type` | `polygonCount?`; `cornerRadius?` | |
| `path` | `type` | `geometry?: string`（SVG path）；`viewBox?: [x,y,w,h]`；`fillRule?: "nonzero"\|"evenodd"` | `[文档]` SVG Path 节："Always set an explicit `viewBox`" |
| `text` | `type` | `content?`；`textGrowth?: "auto"\|"fixed-width"\|"fixed-width-height"`；`TextStyle`（`fontFamily/fontSize/fontWeight/letterSpacing/fontStyle/underline/lineHeight/textAlign/textAlignVertical/strikethrough/href`） | `[文档]`：**text 默认无 `fill`，必须设 `fill` 才可见** |
| `icon` | `type` | `library?`（`lucide`/`feather`/`Material Symbols Outlined|Rounded|Sharp`/`phosphor`）；`icon?`；`weight?`（100-700）；`fill?` | 无 `children` |
| `ref` | `type`,`ref` | `ref: string`（被引用组件 id）；`descendants?: { [id或path或name]: {...} }`；`[key: string]: any`（根级覆盖） | **实例**；`ref` 不可改（`Update` 不支持改 `ref`） |
| `note` | `type` | `content?`；`TextStyle`；`Size` | 无 `fill`（仅 `Entity, Size, TextStyle`） |
| `prompt` | `type` | `content?`；`model?: StringOrVariable`；`TextStyle` | |
| `context` | `type` | `content?`；`TextStyle` | |
| `script`（附加） | `type` | `scriptUri?`；`inputs?`；`clip?` | 用 JS 生成嵌套 children |
| `browser`（附加） | `type` | `url?` `deviceId?` `zoom?` `scrollX?` `scrollY?` `cornerRadius?` | live 网页节点 |

`fill` 取值 `Fills = Fill | Fill[]`，`Fill` 可为：颜色字符串 / `{type:"color",color}` / `{type:"gradient",gradientType?,colors?,...}` / `{type:"image",url,mode?,transform?}` / `{type:"shader",url,uniforms?}` / `{type:"mesh_gradient",...}`。`effect` 同理可为单个或数组。`[文档]`

`[文档]` 变量引用：任何 property 可用 `"$变量名"` 字符串引用变量（`fill:"$primary-color"`, `gap:"$spacing-small"`）。

`[代码交叉验证]`：`handleInsert` 校验 `typeof r!="object"` → `"Second argument of Insert operation must be an object with node properties!"`；`typeof i(r.type)!="string"` → `"...must have a string \`type\` property!"`；随后 `JU(i,r,!1,cb)` 做 schema 校验，非法属性走 `telemetry("invalid-node-property")`。引用不存在的节点 → `Tried to reference non-existent node '...'`。

---

## 3. `Update(path, updateData)`

### 3.1 签名 `[文档]` 逐字

```ts
function Update(path: string, updateData: Child): void;
```

`[文档]` 原文要点（逐字）：

- "Update the properties of existing nodes, without listing their children."
- "DO NOT use this to update the node's `children`, use Replace function for that."
- "This function CANNOT change the `id`, `type` or `ref` properties of any node!"
- `path`: The node to update.

### 3.2 `path` 语法

同 §7。要点：节点 id；或实例内路径 `instanceId/childId`（`[文档]`："expanded node ids are full `instanceId/childId` paths that `Update`/`Replace` accept"）。**不能**写普通层级路径 `"父id/子id"`，**不支持索引**，**一次只更新一个节点**（批量要靠 visitor 里的循环，见 execute.md 的 `Get(screen, n => ... && Update(n.id, {...}))`）。

### 3.3 `updateData`：部分覆盖还是全量替换

**属性层面 = 部分覆盖（partial merge）**；**数组型字段 = 整组替换**。

`[代码交叉验证]`：`updateNodeProperties` 里最终调用 `JU(c.type, p, !0, i)`，其中第三个参数 `!0`(true) 即 **partial 标记**；`p` 是去掉 `descendants`/`children` 后的剩余属性对象，未被列出的属性保持不变。

可改字段（`[文档]` schema 全集均可改，除 `id`/`type`/`ref`）：`fill`、`stroke`、`strokeWidth`、`width`、`height`、`layout`、`gap`、`padding`、`justifyContent`、`alignItems`、`clip`、`cornerRadius`、`textGrowth`、`content`、`fontSize`、`fill`、`effect`、`x`、`y`、`rotation`、`opacity`、`enabled`、`reusable`、`slot` ……

**数组型字段（gradient colors、multi-fill、effect 列表）怎么改** `[文档]`+`[代码交叉验证]`：
- `fill` 接受单个 Fill 或 Fill[]。要改数组，**把整个数组写回**；实现是按属性整体赋值，不存在"按索引 patch 某一项"的语法。
- 例（`[文档]` generate.md 逐字）：`Update(cardId, {fill: [{type: "image", url: cutoutUrl}, ...]})`——注意 `...` 表示列表顺序即绘制顺序，必须自己保留其余项。
- 同一文档也提醒："A node's `fill` may be a list drawn in list order, so the visible image is usually the last image fill."

### 3.4 `children` 能不能改

- `[文档]` **明确不建议**："DO NOT use this to update the node's `children`, use Replace function for that."
- `[代码交叉验证]` 但实现里**确实支持**：`const {descendants:d, children:h, ...p} = u;` … `if(h){ if(!Array.isArray(h)) throw new Error('Node update "children" property must be an array!'); e.clearChildren(c), this.insertNodes(e.block, c.path, void 0, h, ...) }`
  → 传 `children` 会**先清空全部子节点再整体插入**（全量替换，且新子节点会拿到新 id）。

### 3.5 返回值

`[文档]`：`void`。`[代码交叉验证]`：`handleUpdate` 无 return（返回 `undefined` / 失败时返回哨兵 `PF="__batchDesignFailed"`）。

### 3.6 `descendants`（ref 覆盖）

`[文档]`：`Update` 的 updateData 支持 `descendants` map，键为实例内节点的 **id / path / 唯一 name**；值里带 `type` = 整棵替换，不带 `type` = 属性覆盖。多级实例用 `"instanceId/childId/..."` 一条路径写，**不要嵌套多层 descendants 对象**。

`[代码交叉验证]` 关键陷阱：`updateNodeProperties` 内 `const l=(c,u)=>{ if(u.type) this.replaceNode(e,c,QU(u,i),s,a); else {...} }`，且顶层就是 `l(n,r)`。
→ **如果 `updateData` 里带了 `type` 键，`Update` 实际会走 `replaceNode` 整节点替换**（未列出的属性会被丢掉），这与文档"CANNOT change the `type`"表面矛盾。
**实践结论：反写时绝不要在 `Update` 里带 `type`；需要换类型请显式用 `Replace`。**

---

## 4. `Replace` / `Move` / `Delete` / `Copy`

### 4.1 `Replace(path, nodeData)` `[文档]` 逐字

```ts
function Replace(path: string, nodeData: Child): string; // returns the replacement node's id
```

- "Replace a node with a new node. All properties including the x/y are replaced."
- "This tool is ideal for swapping out parts of a component instance with new nodes."
- 返回**新节点 id 字符串**。`[代码交叉验证]`：`handleReplace` 找不到节点 → `` `No such node to replace with path '${n}'!` ``；导入节点 → `Cannot replace ...`；成功 `return o.id`。
- 用途：改 `children`、改 `type`、实例内换槽位（`customContentId=Replace(cardId+"/contentSlotId",{type:"frame",...})`）。

### 4.2 `Move(path, parent, index?)` `[文档]` 逐字

```ts
function Move(path: string, parent: string | undefined, index?: number): void;
```

- `path`: The node to move.
- `parent`: Optional. The new parent node. **If omitted, the node stays under its current parent.**
- `index`: Optional new position of the moved node among its siblings. **If omitted, the node is placed at the end.**

`[代码交叉验证]`：
- 校验：`typeof n!="string"`→错误；`r!=null && typeof r!="string"`→`"Second argument of Move operation must be a string if provided!"`；`i!=null && typeof i!="number"`→`"Third argument of Move operation must be a number if provided!"`。
- **index 语义**：`const o=xmn(i)`，而 `function xmn(t){ if(!(typeof t!="number"||t<0)) return t }` → **只有非负 number 生效；负数/非数字被当作 undefined（=放到末尾）**。索引是"在目标 parent 的 children 数组中的位置"。
- 移动后对原 parent 与新节点都排了 layout 校验：`this.sceneManager.fileManager.moveNodes(e.block,[{node:a,index:o,parentId:s}]); l&&e.validator.queueLayoutValidation(l); e.validator.queueLayoutValidation(a)`。
- 找不到节点 → `` `No such node to move with id '${n}'!` ``。
- 返回值：`void`。

### 4.3 `Delete(path)` `[文档]` 逐字

```ts
function Delete(path: string): void;
```

- "Delete a node from a .pen file."
- **"Cannot delete descendants of component instances - emulate the deletion by overriding the descendant's `enabled` property with `false` instead."**
- 返回值：`void`。

`[代码交叉验证]`：
- 节点不存在时**不报错**：`rtWarning(\`Delete skipped: node '${n}' does not exist.\`)`（是一条 warning，不是 error）。
- **是否级联删子节点：是**。`this.removeRecursivelyFromSceneGraph(e,n)` 的实现为 `e.deleteNode(n); for(const r of n.children) this.removeRecursivelyFromSceneGraph(e,r)` → 整棵子树递归删除。
- 实例后代：`if(!r.isUnique){ ... throw new Error(\`Cannot delete descendants of instances! ('${n}' is under '${s?.path}', an instance of '${s?.prototype?.node.path}')\`) }`；对实例中可 override 的兄弟槽位，会 `createInstancesFromSubtree()` 重新实例化来"模拟删除"。

### 4.4 `Copy(path, parent, copyNodeData?)` `[文档]` 逐字

```ts
function Copy(path: string, parent: string, copyNodeData?: Child): string; // returns the copied node's id (descendants get new ids - Get the copy to read them)
```

- `"path"`: The ID of the existing node to copy. 想自定义被复制节点的属性，就"just add them next to the `path` property"（即写进 `copyNodeData`）。
- 想改**被复制节点的后代**：**必须**用 `copyNodeData.descendants`，**不能**分开发 `Update`，因为"the copied node and its descendants receive new IDs, so Update operations referencing the original descendant IDs will fail."
- `descendants` 键可为 node id/path 或唯一 descendant name。
- **"Copying a reusable node creates a connected instance (a `ref` node)."**（复制 `reusable:true` 的组件会生成相连实例）
- 返回复制节点 id 字符串；后代全部拿新 id，需要读用 `Get(copiedId)`。

`[代码交叉验证]`：`handleCopy(e,n,r,i)` 校验 first arg string、second arg string、third arg 若存在必须 object（`"Third argument of Copy operation must be an object with node properties to update!"`）；`const a=g0(n,...); if(!a) throw new Error(\`Can't find node '${n}'!\`)`；随后 `copyNode(this.sceneManager.fileManager.copyNode(e.block,a,o,void 0,s??{},...))`，`s` 即 copyNodeData；`Vie(s, e.replacedIDs)` 会把 `copyNodeData` 子树里的 id 全部重新分配（`if(t.type) wH(t,e); else { descendants...; children... }`）→ **传入的 `copyNodeData` 里写 `id` 无效，且带 `type` 的 descendant 值 = 整棵替换**。返回 `l.id`。

---

## 5. `SetVariables(variables, replace?)`

### 5.1 签名与结构 `[文档]` 逐字

```ts
function SetVariables(variables: Record<string, VariableDefinition>, replace?: boolean): void;
```

`[文档]` 原文要点（逐字）：

- "Define or update the variables and themes of the .pen file. Read existing variables with `Print(GetVariables())` first."
- "`variables`: An object keyed by variable name. Each value MUST be an object with a `type` (`\"color\"`, `\"number\"`, or `\"string\"`) and a `value`. Passing a bare value like `\"#A3B59A\"` or `16` will fail."
- "Variable names are arbitrary strings and MUST NOT begin with a dollar sign. The `$` prefix is only used when referencing a variable from a property (e.g. `fill: \"$accent\"`)."
- "`replace` (optional, default `false`): when `false`, the variables are merged into the existing definitions. Pass `true` to completely replace the document's existing variable definitions."
- "Don't specify themes separately. If a variable uses theming, theme axes and values that aren't yet present in the document are registered automatically. For themed values, pass an array of `{value, theme}` entries."

```js
SetVariables({
  accent: {type:"color",value:"#A3B59A"},
  "spacing-unit": {type:"number",value:16},
  "font-heading": {type:"string",value:"Playfair Display"},
  background: {type:"color",value:[
    {value:"#F8F5F0",theme:{mode:"light"}},
    {value:"#1A1A1A",theme:{mode:"dark"}}
  ]}
})
```

**返回值**：`void`。

### 5.2 代码交叉验证（重要补充与限制）

`[代码交叉验证]` `rmn(sceneManager, block, n, r)`：

- 只读文档 → `` `The document '...' is read-only` ``。
- 每个定义：必须 object；**`type` 必须是 `"boolean"`/`"color"`/`"string"`/`"number"` 之一**（注意：代码里**包含 `"boolean"`**，而文档只写了 color/number/string——`boolean` 是文档遗漏的合法类型）；必须有 `value`；否则分别报 `Variable 'X' has an invalid 'type' property` / `Variable 'X' is missing its 'value' property` / `Variable 'X' is missing its 'type' property`。
- **变量名不能包含冒号**：`if(s.includes(":")) throw new Error(\`Variable names cannot contain colons: '${s}'\`)`（文档只说了不能以 `$` 开头）。
- 导入的变量不可改：`Cannot change 'X', because it's an imported variable from ...`。
- **`replace:true` 的破坏性语义**：先把新变量名收成 Set，然后遍历现有变量；对本文件定义（`o.document.id===void 0`）的变量：
  - 名字在新集合里 → `e.setVariable(o,[])`（**清空其 themed 值**）；
  - 名字不在新集合里 → `e.deleteVariable(o.qualifiedName)`（**删除该变量**）。
  即 `replace:true` = 用新定义**整体替换**本文件全部变量定义。
- 值校验走 `kde(..., onInvalidValue, onCircular, onMissing)`，错误原文：
  - `` `Variable '${s}' has an invalid value: ${o}` ``
  - `` `Circular dependency on variable '${s}'` ``
  - `` `Reference to non-existent variable '${s}'` ``

### 5.3 新增 / 修改 / 删除变量（操作配方）

| 操作 | 做法 | 来源 |
| --- | --- | --- |
| **新增** | `SetVariables({新名:{type,value}})`, `replace` 省略/false（merge） | `[文档]`+`[代码交叉验证]` |
| **修改** | 同名键再 `SetVariables({同名:{type,value}})`，merge 下覆盖 | 同上 |
| **改单主题值** | `value:[{value,theme:{axis:val}},...]`，未注册的主题轴自动登记 | `[文档]` |
| **删除某个变量** | ⚠️ **没有定向删除 API**。唯一途径是 `replace:true` 并把**所有想保留的变量**一起列出来（没列出的本文件变量被删）。用前必须先 `Print(GetVariables())` 备份 | `[代码交叉验证]`（`deleteVariable` 只出现在 replace 分支） |
| **改导入变量** | ❌ 不允许 | `[代码交叉验证]` |

> `[文档]` 的 `guide` 提示（SKILL.md 逐字）："When creating new variables make sure you are not accidentally overwriting any existing design."

---

## 6. `Generate(...)`

### 6.1 签名 `[文档]` 逐字（execute.md 与 generate.md 一致）

```ts
function Generate(type: "ai" | "svg", nodeId: string, prompt: string): void;
function Generate(type: "stock", nodeId: string, query: string): void;
function Generate(type: "vectorize-image", nodeId: string, imageUrl: string): void;
function Generate(type: "remove-background", imageUrl: string): string; // returns the new asset url
function Generate(type: "replace-background", imageUrl: string, prompt: string): string;
function Generate(type: "replace-background", imageUrl: string, prompt: string): string; // returns the new asset url
```

### 6.2 逐类型用途 / 参数 / 返回

| type | 用途 | 参数 | 返回 | 目标节点要求 |
| --- | --- | --- | --- | --- |
| `"ai"` | 生成一张全新 AI 图像，作为 **fill** 应用到已有节点 | `("ai", nodeId, prompt)` | `void` | 节点需 `supportsImageFill()`；**没有 `image` 节点类型**，图像只是 fill |
| `"stock"` | 从 Unsplash 取图作为 fill | `("stock", nodeId, query)`，query = 1–3 个具体关键词 | `void` | 同上；无匹配时 url 静默消失 |
| `"svg"` | 生成矢量插画，落到 frame 的 children（paths） | `("svg", nodeId, prompt)` | `void` | **只能传 frame**，且该 frame 需 `placeholder:true`；结果缩放到 frame bbox |
| `"vectorize-image"` | 把**文档里已有**的位图描成矢量 paths | `("vectorize-image", nodeId, imageUrl)` | `void` | 先插入 `placeholder:true` 的 frame，nodeId 传它 |
| `"remove-background"` | 抠图，得到透明背景的新资产 | `("remove-background", imageUrl)` | **新 asset url（string）** | **不写文档、无 nodeId**；返回的 url 需自己 `Update(fill)` 应用 |
| `"replace-background"` | 保留主体、重新生成背景 | `("replace-background", imageUrl, prompt)` | **新 asset url（string）** | 同上；prompt 描述背景而非主体 |

`[文档]` 关键原文：
- "Every type is async: the result lands after the `execute` call that started it has returned, so a screenshot taken right away will not show it. Never re-generate it, draw the result by hand, or add children to a frame you generated into."
- "`imageUrl` ... must ALREADY be in the document ... Never invent, guess, or hand-write this url."
- "Apply a returned url with `Update` on the node's `fill` ... in the SAME execute call ... Never carry it into a later call through a global."
- 源图限制："The source must be a JPEG, PNG or WEBP, at most 16MB, and between 256px and 4096px in both dimensions."
- 等待方式：frame 类看 `Print(Get(id,{depth:0}).placeholder)`；fill 类看 `fill` 的 `pencil:pending-image-...` url 是否已改写。

`[代码交叉验证]` 参数校验（execute.md 同款 zod union，错误原文）：
- `` `nodeId` property is required for Generate operation! ``
- `` `prompt` property is required for Generate operation! ``
- `` `imageUrl` property is required for Generate operation! ``
- `` `type` property must be one of ... for Generate operation! ``
- 运行期：`` `Node '${a.nodeId}' not found for Generate operation!` ``、`` `Node '${a.nodeId}' does not support image fills!` ``。
- `"remove-background"` 在不可生成时直接原样返回输入 url（`return a.imageUrl`）；`"replace-background"` 无此回退。

---

## 7. `path` 语法专题（全篇汇总）

| # | API / 场景 | `path` 合法形式 | 索引可用 | 备注 |
| --- | --- | --- | --- | --- |
| 1 | `Get(path)` | 节点 id；实例路径 `instanceId/childId`；根别名 `document`/`root`/`#document`/`#root` | ❌ | `Get(visit)` 无 path = 全文档 visitor（禁止无 visitor 的全量读） |
| 2 | `Update(path)` | 同上 | ❌ | 实例展开 id 形如 `instanceId/childId` |
| 3 | `Replace(path)` | 同上 | ❌ | |
| 4 | `Copy(path, parent)` | 同上 | ❌ | `parent` 用 id 或根别名 |
| 5 | `Move(path, parent, index?)` | 同上 | `index` 是**参数**不是 path 段 | 同 parent 内重排用 `Move(id, undefined, n)` |
| 6 | `Delete(path)` | 同上 | ❌ | |
| 7 | `Insert(parent, data)` | id / 实例路径 / 根别名 | ❌ | |
| 8 | `descendants` map 键 | 后代 node id / path / **唯一 name**；多级实例用 `"instanceId/childId/..."` 一个字符串 | ❌ | 名字重名会报 `Found multiple descendants named 'X'`，须改用 id/path |
| 9 | `ref` 内覆盖 | `"instanceId/childId"`，可任意深度嵌套实例 | ❌ | `[文档]` "This works for arbitrarily nested component instances" |

**核心规则（`[文档]` 逐字）**：
> "The `path` argument (used by `Get`, `Copy`, `Update`, `Replace`, `Move`, `Delete`) is a node ID, or a slash-separated path to a node nested inside a component instance (`instanceId/childId`). Slashes are only valid for component-instance nesting, not normal layer structure, and work for any nesting depth."
> "Targets - `path` and `Insert`'s `parent` - are always id/path strings: never pass a node object; when holding a node from `Get`, pass its `.id`. Returned ids concatenate directly: `cardId + \"/childId\"`"

**如何在 execute 里稳定指到某个嵌套节点** `[文档]`+`[代码交叉验证]`：
1. 普通层级：**只能靠 id**。父 id 与子 id 之间**不能**用 `/` 拼（`/` 只给实例用）。
2. 组件实例内：`实例id + "/" + 组件内子节点id`，可多级 `a/b/c`。
3. 不确定 id 时用 visitor 按 name 找：`Get(n => n.name === "Primary Button" && Update(n.id, {...}))`。
4. `Get` 的 path 解析 `[代码交叉验证]` `g0`：逐段 `getNodeByPath(段)`；若该段不是 id，则按 **name** 递归收集后代（`IWe`），唯一命中才采用，多命中且都不 unique → `Found multiple descendants named '...'`，无命中 → 返回 undefined（上层报 "not found"）。所以**name 也能当 path 段用，但只在全局唯一时安全**。

**`resolveInstances:true` 的 `instanceId/childId` 能否用于写操作？**
✅ **能**。`[文档]` Get 节逐字：
> "`path` is a node ID or instance path (with `resolveInstances`, expanded node ids are full `instanceId/childId` paths that `Update`/`Replace` accept)."
`[文档]` components.md：
> "Use `Update(instanceId+\"/childId\", {...})` to change properties / Use `newNodeId=Replace(instanceId+\"/childId\", {...})` to replace with a new node"
`[代码交叉验证]`：`g0` 与 `canonicalizePath` 均支持实例内路径，`Update`/`Replace`/`Copy`/`Move`/`Delete` 共用一个 `g0` 解析器。

⚠️ 但 `[文档]` 提醒：实例**没有自己的 children**——"An instance (`ref` node) has no `children` of its own - its subtree comes from the component. Do NOT `Get` an instance to discover its children"，且 **Delete 不能删实例后代**（改用 `enabled:false`）。

---

## 8. 写操作的安全与坑

### 8.1 undo

`[代码交叉验证]`：**有 undo，且整次 execute 是"一步"**。
- 成功路径：`this.sceneManager.scenegraph.commitBlock(i.block,{undo:!0})` → `commitBlock(e,n){ n.undo && this.sceneManager.undoManager.pushUndo(e.rollback) }`
- 失败路径：`this.sceneManager.scenegraph.rollbackBlock(i.block)` → `applyFromStack([e.rollback], null)`
- 即：一次 execute 产生的所有改动合成一个 rollback block，提交时入 undo 栈。用户 Ctrl/Cmd+Z 会**整步撤销**，不会半途。

### 8.2 是否立即持久化到磁盘

`[未证实]`。我在编辑器 bundle 的 execute 提交路径中**没有找到任何 saveDocument / writeFile 调用**——提交只到 `sceneGraph.commitBlock`（内存 scene graph + undo 栈）。合理推断：写操作**立即反映到用户正在编辑的活文档 UI**，磁盘 `.pen` 落盘由 App 自身的保存流程负责，不由 execute 触发。**给父 agent 的建议：不要假设 execute 已写盘；若需要交付文件，走 `Export` 或让 App 保存。**

### 8.3 失败后的 `editId` 修补流程（确切用法）

`[文档]` 逐字：
> "When an `execute` call fails, ALWAYS fix it with the `edits` parameter and the `editId` from the failure message - never resend the snippet. If the patched snippet fails again, keep fixing it with further `edits` under the same `editId`; `find` must then match the snippet as already patched."

`[代码交叉验证]` 参数校验规则（错误原文）：
- `edits` 必须是 `{find, replace}` 对象的数组；每项 `find` 为非空 string、`replace` 为 string：
  - `"`edits` must be an array of `{ find, replace }` objects. Send the `edits` that patch the failed snippet, or resend the full corrected snippet in `input`."`
  - `` `edits[${s}] must be an object with a non-empty \`find\` string and a \`replace\` string!` ``
- 用 `edits` 必须同时给 `editId`；两者缺一都报错：
  - `` "`editId` requires `edits`. ..." `` / `` "`editId` is required when using `edits`. Pass the editId printed in the failure message." ``
- `input` 与 `edits` **不能同时给**：`"Provide either `input` or `edits`, not both. Use `edits` alone to patch and re-run a failed call."`
- `edits` 不能作为 partial 调用：`"`edits` cannot be sent as a partial call. Send the complete `edits` array in a single non-partial `execute` call."`
- 失败响应的修复指引会带 `editId`；若 find 未命中，提示：
  > "- The failed snippet \"…\" was NOT modified. Fix the `edits` so each `find` matches its content exactly and call `execute` again with the same `editId`, or resend the full corrected snippet in `input`."
- 修补后 snippet **从头重跑**（不是增量执行）；未命中时原 snippet 未被改动。
- `edits` 的 `all:true` 语义：替换全部匹配（本仓 pencil 工具 schema：`all` 布尔，默认要求唯一匹配）。

### 8.4 批量写是否原子 / 一次 execute 能否写多个节点

- **一次 execute 可以写任意多个节点**（就是 JS：循环、数组、`for...of`；`Insert` 在循环里插很多次）。
- **原子性 = 是**。`[文档]` 逐字："In case of an error, all modifications and the created globals will be reverted."
  `[代码交叉验证]`：失败 → `rollbackBlock(i.block)`；`[文档]` 另注 "Values printed by a failed `execute` call are not returned."、"Screenshots of a failed `execute` call are not returned."
- **跨 execute 不共享局部变量**：`[文档]` "Each `execute` is executed in its own scope. Local variables and helper functions are NOT shared between `execute` calls. To persist values between calls, don't use `const` or `let` ... use `myNodeId = Insert(...)`."（全局赋值会持久化，但失败会连同全局一起回滚。）

### 8.5 其它硬性坑（速查）

- **绝不手写 `id`**：`[...] pen.dev will always generate unique random IDs and override the input.`（`[文档]`）实例化的 `copyNodeData` 里的 id 也会被重新分配（`[代码交叉验证] Vie`）。
- **id 不能含 `/`**（`[文档]` schema）；`/` 在 path 里专用于实例。
- **`Update` 不要带 `type`**（会退化成 `replaceNode` 全量替换）`[代码交叉验证]`。
- **`Update` 改 `children` 是全量清空重建**（新子节点换新 id）`[代码交叉验证]`；文档建议用 `Replace`。
- **`Delete` 级联删整棵子树**，且**对实例后代直接报错**（`Cannot delete descendants of instances!`），实例内"删除"要用 `enabled:false`。
- **`Move` 的 index 必须 `>=0` 的 number**，否则静默"放到末尾"。
- **`Copy` 的后代必须用同一次 Copy 的 `descendants` 改**，之后再 Update 原 id 一定失败（id 已变）。
- **`SetVariables` 的 `replace:true` 会删除未列出的本文件变量**，且会清空已列出变量的 themed 值。
- **`Generate` 的 `remove-background`/`replace-background` 返回的 url 必须在同一个 execute 内应用**，不能带到下一次调用。
- **`Generate("svg")`/`"vectorize-image"` 只接受 frame**，且必须 `placeholder:true`。
- **变量引用用 `$name`，定义时不能写 `$`**；变量名不能含 `:`。
- **`layout`/`padding` 只能设在 `frame` 上**；`group` 无 fill/stroke。
- **text 不设 `fill` 就不可见**。
- **设置 `width`/`height` 必须配 `textGrowth`**（否则报错/无效）。

---

## 9. 文档中「不可逆 / 需谨慎 / 必须确认」的逐条原文引用

> 以下均为官方技能文档原文（英文逐字），按主题归类。

**回滚与失败处理（execute.md）**
- "In case of an error, all modifications and the created globals will be reverted."
- "When an `execute` call fails, ALWAYS fix it with the `edits` parameter and the `editId` from the failure message - never resend the snippet. If the patched snippet fails again, keep fixing it with further `edits` under the same `editId`; `find` must then match the snippet as already patched."
- "Values printed by a failed `execute` call are not returned."
- "Screenshots of a failed `execute` call are not returned."

**禁止的行为（execute.md）**
- "Never set `id` when creating, copying, or replacing nodes or components. pen.dev will always generate unique random IDs and override the input."
- "When copying a node and modifying its descendants, you MUST use the \"descendants\" property in the Copy operation itself. DO NOT use separate Update operations for descendants of copied nodes, as this will fail due to ID mismatches."
- "DO NOT use this to update the node's `children`, use Replace function for that."
- "This function CANNOT change the `id`, `type` or `ref` properties of any node!"
- "Cannot delete descendants of component instances - emulate the deletion by overriding the descendant's `enabled` property with `false` instead."
- "Do not include comments in the generated `execute` JavaScript snippet. Keep the input small."
- "IMPORTANT: Do NOT use or think in CSS/HTML properties or behavior."
- "Do NOT use: alignItems baseline/stretch, margin, percentage size. These values are not supported and will cause an error."

**变量（execute.md / SKILL.md）**
- "Variable names are arbitrary strings and MUST NOT begin with a dollar sign."
- "`variables`: An object keyed by variable name. Each value MUST be an object with a `type` (`\"color\"`, `\"number\"`, or `\"string\"`) and a `value`. Passing a bare value like `\"#A3B59A\"` or `16` will fail."
- "`replace` (optional, default `false`): when `false`, the variables are merged into the existing definitions. Pass `true` to completely replace the document's existing variable definitions."
- "When creating new variables make sure you are not accidentally overwriting any existing design."

**Generate（execute.md / generate.md）**
- "IMPORTANT: There is NO `image` node type. Images are applied as FILLS to existing nodes; SVGs become paths inside a parent frame."
- "Never re-generate it, draw the result by hand, or add children to a frame you generated into."
- "Never call Generate again for pending work."
- "Never guess or invent an image url - it only ever comes from `Generate`."
- "Never invent, guess, or hand-write this url."
- "Apply a returned url with `Update` on the node's `fill` (it holds one fill or a list), in the SAME execute call - no `TakeScreenshot`, `Export`, or further `Generate` in between. Those hand control back to the editor, and once the transform resolves the url you are still holding stops referring to anything. Never carry it into a later call through a global."
- "Failures are silent: a `placeholder` flag cleared on a frame that still has no children, or a fill whose `url` has disappeared."
- "the generator sees nothing of the document, so the prompt must state the subject, composition, line/fill style, and colors."

**组件与实例（guide/components.md）**
- "IMPORTANT: DO NOT try to Update a node's descendant that you just copied (Copy), since copying will recreate the descendant nodes and it will assign new IDs to those children nodes."
- "Never use separate Update operations for descendants of copied nodes, as this will fail due to ID mismatches."
- "You cannot reference components across files. If you want to use a component from a different file you must copy it over."
- "An instance (`ref` node) has no `children` of its own - its subtree comes from the component. Do NOT `Get` an instance to discover its children..."
- "When accessing multi-level descendant nodes in the component, use paths in the `descendants` object keys to access it, DO NOT create multiple levels of `descendants` objects."
- "When an instance is not inside an object using `layout`, it must be positioned by overriding its `x` and `y` properties. Do this even if the position is (0, 0). Never override just a single position axis."

**schema（pen-schema.md）**
- "Unique string; MUST NOT contain '/'. Auto-generated if omitted."（`Entity.id`）
- "When true, can be duplicated via `ref` objects. Default false."（`reusable`）
- `descendants` 覆盖语义逐字："- `type` is not present = property overrides: the descendant node is updated with the listed properties. - `type` is present = replacement: the descendant node is fully replaced with a new node tree."

**协作环境（SKILL.md）**
- "pen.dev is a collaborative multiplayer environment: the document can change while you work, so the state you remember may be stale. If a node is missing or no longer matches what you expected, re-read instead of recreating it, and don't undo changes the user made in the meantime."
- "User may ask for technical modifications like removing, moving, re-ordering, clearing, and copying objects/variables, or just ask questions. Only do what's requested and nothing more."
- "If a property is not present in the .pen schema, it's not supported. Find a different way to achieve the same visual effect."
- "After reviewing the design, do NOT delete it to make changes. If you want to fix it, always make direct updates to the existing objects."

**Root 卫生（SKILL.md）**
- "Keep the document root clean: only page/screen frames, reusable component frames, and other major container frames belong directly under `document`. Never place text, icons, buttons, cards, rows, images, or decorative shapes directly in `document`."

---

## 10. 反写设计稿的最小安全流程建议

> 目标场景：从代码/既有产物反写回 `.pen`。以下是在「不破坏用户正在编辑的文档」前提下的最小风险流程。

1. **先只读勘察，再动手**
   - `get_app_state` 确认当前编辑器指向哪个 `.pen`、选中了哪些节点。
   - 在 execute 里先 `Get` / `Print` 读取：顶层节点、目标容器、组件清单（`Get(n=>n.reusable && Print(n.id,n.name))`）、变量清单（`Print(GetVariables())`）。
   - 绝不凭记忆假设 id；协作文档随时可能变（SKILL.md 明确警告）。

2. **划定写入边界**
   - 只写自己的目标容器，绝不直接写 `document`（SKILL.md：root 只放页面/组件/大容器）。
   - 新建/改动的 root frame 全程带 `placeholder:true`，完成后立刻 `Update(id,{placeholder:false})`。
   - 用 `FindEmptySpace({width,height,padding,nodeId})` 找位置，避免覆盖既有内容。

3. **先复制，后修改，而不是重画**
   - SKILL.md 首选："Favor copying existing content and updating the copied content later."
   - 复制已存在的近似节点 → `Copy(srcId, parent, {..., descendants:{...}})`；**所有后代改动都写在这同一次 Copy 的 `descendants` 里**，绝不分开发 `Update`。

4. **一次 execute 一个逻辑单元，靠原子性兜底**
   - 把"新增一个卡片/一节内容"放一次 execute；出任何错整次回滚（可放心重试）。
   - 失败时用失败消息里的 `editId` + `edits:[{find,replace}]` 打补丁，**不要重发整段**；一直用同一个 editId 迭代到通过。

5. **写前备份变量，写后校验**
   - `SetVariables` 只在 merge 模式（不传 `replace`）下增量添加/覆盖；**永远不要随手 `replace:true`**（会删除未列出的变量）。
   - 需要删除某变量时，先 `Print(GetVariables())` 记下全量，再用 `replace:true` 列全量重写——并把这步单独作为一次 execute，便于撤销。

6. **改属性用 `Update`（不带 `type`），改结构用 `Replace`**
   - `Update` 只传要改的键；数组型字段（`fill`/`effect`/`stroke`）整组传回（先 `Get` 读旧值再改）。
   - 需要换节点类型、改槽位、改整棵子树，用 `Replace`（注意 x/y 也会被替换，需显式带上）。
   - 绝不在 `Update` 的 `updateData` 里带 `type`（代码会走 replaceNode 全量替换）。

7. **删除最保守**
   - 优先 `enabled:false` 而非 `Delete`；`Delete` 会级联删整棵子树，且对实例后代直接报错。
   - 删除前先 `Get(path,{depth:0})` 确认拿到的正是目标节点；注意节点不存在时 Delete 只报 warning、静默跳过。

8. **涉及 Generate 时**
   - `ai`/`stock`/`svg`/`vectorize-image` 都是异步：同一个 execute 里只发起，**不截图、不依赖结果**；`["svg","vectorize-image"]` 传 `placeholder:true` 的 frame。
   - `remove-background`/`replace-background` 返回的 url **必须在同一次 execute 内** `Update` 到 `fill` 上。
   - 结果到达后用极小读取校验（`placeholder` 是否被清 / `fill` url 是否已从 `pending-image-` 改写）。

9. **收尾**
   - `TakeScreenshot([sectionId])` 只截完成的 section（不是整文档），验证布局/对比度/裁切。
   - 需要交付就用 `Export([...], "html-tailwind"|"png", ...)`，不要靠截图当交付物。
   - 每次 execute 结束 `Print` 一份"本次新建节点 name→id"清单，作为下次 execute 的稳定锚点（局部变量不跨调用持久，但全局赋值 + id 字符串可）。

10. **兜底心态**
    - 写操作有 undo，一次 execute = 一步撤销；但这依赖 App 在手，**不要把它当成事务性文件写**。
    - 磁盘落盘与否未经证实（§8.2）：若下游需要文件，显式走 `Export` 或让 App 保存，而不是假设 execute 已写盘。
