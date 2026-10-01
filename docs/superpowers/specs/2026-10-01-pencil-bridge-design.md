# pencil-bridge 设计规范

- **状态**：已批准（用户于 2026-10-01 逐节确认，含三项裁决）
- **落点**：`~/Project/pencil-bridge/`（git repo，将来上传 GitHub）
- **目标 harness**：DSH、Claude Code、Codex CLI（三者共享同一份技能真源）
- **日期**：2026-10-01

---

## 1. Goal

让 AI harness 能主动通过 pencil MCP 连接到 Pen.app 中**指定的 `.pen` 文件与节点**，从而：

1. 项目内相应页面能**根据设计稿调整样式**（设计 → 代码）；
2. **提取素材**（位图、矢量、图标引用、设计变量 token）；
3. **反向写回设计稿**（代码 → 设计）；
4. 在**多项目并行**时不窜项目、不读错文档。

交付物是**四条命令 + 一个主知识 bundle**，放在公共位置，供三个 harness 共用。

## 2. Non-goals

- **不自己解析 `.pen` 文件格式**。一切结构读写走 MCP；磁盘 `.pen` 是明文 JSON 这一事实只作为最后手段记录，不作为实现路径（磁盘副本可能落后于 app 内存）。
- **不修改 Pen.app 自身的任何数据**。只读探测仅限明确列出的少数文件（`.pen` 的最近打开记录、`workspaceFolders` 等），且**必须跳过 §3.7 的凭据清单**。
- **不碰 `# >>> dsh-skill-mcp-panel:mcp:begin` 受管块**（详见 §6.4）。
- **不读明文凭据文件**（清单见 §3.7）。
- 不做可视化界面；全部能力通过命令与技能文本交付。

---

## 3. 实测地基

本设计的每条硬约束都来自实测。以下事实若被推翻，对应设计需要重审。

### 3.1 MCP 接口面

- 二进制：`/Applications/Pen.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-arm64`
  - 全 app 内 `find` 确认**只有这一份**；`getMcpBinaryName()` 支持 `-darwin-x64` / `-linux-arm64` / `-linux-x64` / `-windows-x64.exe`，但本机 Pen.app 不提供。
  - 另一份独立副本：`~/.pencil/mcp/visual_studio_code/out/mcp-server-darwin-arm64`（VS Code 集成用，连的是 `--app visual_studio_code`）。
- 本机暴露的工具**只有 5 个**：`browser`、`execute`、`get_app_state`、`get_style`、`read_skill`。
  - 旧文档里的 `pencil_batch_get` / `pencil_get_screenshot` / `pencil_get_variables` **不存在**，不得引用。
- CLI 参数：`--app <name>`（决定 socket 名）、`--agent <自由文本>`、`--conversation_id <id>`、`--enable_spawn_agents`。**没有任何指定 `.pen` 文件的参数**。
- `execute` 的 API 面（逐字签名）：

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

- `GetOptions`：`depth` / `resolveVariables` / `resolveInstances` / `includePathGeometry`
- `ExportOptions`：`scale`（默认 2）/ `quality` / `includeHtmlScaffold` / `includeLayerNames` / `includeLayerIds`
- 每次 `execute` 是**独立作用域**；跨调用共享状态只能靠**不带 `const`/`let` 声明的赋值**。
- 失败必须用响应里返回的 `editId` + `edits: [{find, replace}]` 修补后重跑；不能同时再给 `input`。

### 3.2 文档路由：`filePath` 与静默回退（本节是「不窜」的全部依据）

三探针实测：

| 探针 | `filePath` 传入 | 焦点文档（`get_app_state`） | 实际读到的文档 |
|---|---|---|---|
| 1 | `file:///…/yuexiaoshi.pen` | yuexiaoshi | yuexiaoshi（无区分力：焦点恰好相同） |
| 2 | `/tmp/definitely-not-real-xyz.pen` | yuexiaoshi | **yuexiaoshi**（静默回退，**无任何报错**） |
| 3 | `file:///…/hanzi_write.pen`（**非焦点**） | yuexiaoshi（前后均未变） | **hanzi_write** ✅ |

探针 3 是决定性证据：读到 hanzi_write 的顶层 frame，而焦点**始终**是 yuexiaoshi。

**结论**：
- `execute` 的 `filePath` **有效**，按文档路由，且**不改变** `lastFocusedResource`。
- **目标文档未打开、或路径不可解析时，请求静默回退到「最后聚焦的文档」，不报错。** 这是最危险的失败模式。
- 路由实现是三级查找：① `file://` URI 直命中 → ② 遍历设备比对 `getFileURIForPath(filePath) === deviceURI`（**裸路径只对已打开文档有效**）→ ③ 兜底 `lastFocusedResource`。
- `lastFocusedResource` 在**用户点击窗口**时更新（`window-focused` 事件）→ 焦点随时可能被用户改掉。
- **`get_app_state`、`read_skill`、`get_style`、`browser` 都没有 `filePath` 参数**，永远命中兜底分支。→ **`get_app_state` 绝不能用来判断写入目标。**
- MCP 二进制里**没有任何 open/switch/activate/focus document 工具** → 无法通过 MCP 切换活动文档。要打开某个 `.pen`，只能 `open -a Pen <path>`（在既有实例里打开）或让用户手动打开。
- 失败时（文档真的不可达）错误原文：`Failed to access file "<path>". A file needs to be open in the editor to perform this action.`

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

- **禁止无 visitor 全量读**：`Get("document", {depth:0})` 报错
  `Reading the whole document without a visitor would return everything! Pass a visitor to collect only what you need (e.g. Get(n => n.name)), or target a specific node.`
- `document` / `root` / `#document` / `#root` 都是根别名；`document` 只能当 `Insert` 的 parent 或 visitor 的起点。
- **`Print` 是唯一的输出通道**；不 `Print` 就拿不到任何数据。

只读哨兵范式（本设计全程用它校验文档身份）：

```js
const out = [];
Get(document, (n, c) => { if (c && c.depth === 1) out.push(n.name); });
Print("SENTINEL_TOP:", out.slice(0, 3).join(" | "));
Print("SENTINEL_COUNT:", out.length);
```

已知基线：yuexiaoshi.pen 顶层计数 **136**；hanzi_write.pen 顶层计数 **183**。

### 3.3 节点模型

- 节点类型：`frame | group | rectangle | ellipse | path | polygon | text | note | prompt | context | icon | script | browser | ref`。
- **没有 `image` 节点类型**。图片是**节点上的 image fill**：`{ type: "image", url, mode: "cover"|"contain"|"stretch" }`。
- **image fill 的 `url` 是相对 `.pen` 所在目录的磁盘相对路径**，原文件真实存在；`.pen` 内无 base64、无 http 外链。
  - 例：`assets/hanzi-design-v1/bg_character_of_day.png` → `<pen目录>/assets/hanzi-design-v1/bg_character_of_day.png`（1,679,293 B 真实 PNG）。
  - → **位图素材可以直接拷磁盘文件，不需要 MCP 传字节。**
- **`context` 不是节点类型，而是挂在 `frame` 上的属性**（一段 markdown 设计说明）。实测 yuexiaoshi 有 12 个 frame 带它，`bSb0t` 那条长 8,334 字符。
- **组件定义** = `type:"frame"` + **`"reusable": true`**（不是独立类型）。例：
  `{"type":"frame","id":"d96ni","name":"组件 · Primary action","reusable":true,"width":240,"height":52,"fill":"$yxs-primary","cornerRadius":"$yxs-radius","padding":[12,16],"justifyContent":"center","alignItems":"center"}`
- **组件实例** = `ref` 节点：`{"id":"r5D5eK","type":"ref","ref":"d96ni","name":"…","width":400,"descendants":{…}}`
  - `ref` 指向组件 id；`descendants` 是**按子节点 id 的覆盖**。
  - `{resolveInstances:true}` 时子节点 id 形如 `instanceId/childId`。
- **`path` 节点**关键字段：`geometry`（SVG path 串）、`viewBox`（**节点上的显式字段，数组形式如 `[0,0,24,24]`**）、`fillRule`、`fill`、`stroke`、`strokeWidth`、`strokeLinecap`、`strokeLinejoin`。
  - 以下样本取自 `hanzi_write.pen` 的 `E5QUX` 子树（「25 · 图标规范 / 还差 12 枚」），其类型直方图为 `{frame:60, text:18, icon:34, path:7}` —— 即 7 个真矢量 `path`（§14 验收标准第 4 条引用此处）。
  - **`viewBox` 只在 `includePathGeometry: true` 时随 `geometry` 一起返回**（此前的「由 width/height 推导」是错的）。
  - `fill: "#00000000"` 是**全透明**，导出时应落成 `fill="none"`。
  - **`strokeWidth` 是节点像素坐标下的值**，不能直接写进 viewBox 坐标系。实测样本 `width:72, height:72, viewBox:[0,0,24,24], strokeWidth:6`；按 `6 × 24/72 = 2` 换算恰好是 lucide 标准描边。**此换算规则标为待实证，不得当定论写进实现。**
- **`icon` 节点**只有：`library`（lucide | feather | Material Symbols Outlined/Rounded/Sharp | phosphor）、`icon`（名字）、`weight`、`fill`。**没有 geometry、没有 SVG 源码。**
  - `Export` 的格式列表里**没有 svg**；本机 Pen.app 未打包任何图标字体/SVG 资源。
  - → **图标只能产出「库名 + 图标名」引用，取不到矢量源码。**
- **无按名查找的内置能力**，必须写 visitor；且**名字不唯一**（实测 `name === "Cap"` 命中 45 个节点），必须叠加 type / 父链 / bounds 才能定位。

### 3.4 变量

- 唯一读取入口是 `Print(GetVariables())`；返回 `{ variables, themes? }`。
- 值形如 `{ "type": "color" | "number" | "string" | "boolean", "value": … }`。写回 `SetVariables` 时**名字不带 `$`**；节点内引用写作 `"$primary"`；链式引用（`"$cream-50"`）是合法的。
- **主题可以是多维的**：yuexiaoshi 的 `themes = {"mode":["light","dark"], "locale":["zh","en"]}`。
- 字体也可以走变量：`"fontFamily": "$yxs-font"`。
- **`SetVariables` 的 `replace` 默认 `false`（merge）**。**`replace: true` 会删掉未列出的本文件变量，并清空已列出变量的 themed 值** —— 因为**没有定向删除变量的 API**，删变量必须 `replace: true` 全量重写。→ **本设计默认禁用 `replace: true`**（见 §11）。
- 导入的变量不可改。

### 3.5 写操作的语义与坑

- **有 undo**：**一次 `execute` = 一个撤销块**（一步撤销）。
- **失败会整次原子回滚**，包括本次创建的全局变量；`Print` 与截图都不会返回。
- `Update` = 属性 **partial merge**；但**数组字段（`fill` / `stroke` / `effect`）是整组替换**，没有按索引 patch。
- **绝对不要在 `Update` 的 `updateData` 里带 `type`** —— 实现会走整节点替换路径（`replaceNode`），与「不能改类型」的文档表面矛盾，行为不可预期。
- `Update` 若传 `children` 会「clearChildren + 整体重插」（产生新 id）。**不要用**，改结构用 `Replace`。
- `Replace` = **全量替换（含 x/y）**，返回新 id。
- `Move` 的 `index` 只有非负 number 生效，否则静默放到末尾；`parent` 省略表示留在原父级。
- `Delete` **级联删整棵子树**；对组件实例的后代直接抛 `Cannot delete descendants of instances!`；节点不存在只发 warning、不报错。
- `Copy` 时 **reusable 节点会变成 `ref` 实例**；对副本后代的改动**必须在同一次 `Copy` 的 `descendants` 里**，之后再 `Update` 原 id 必然失败。
- `Generate` 全部**异步**，结果在 `execute` 返回后才落地。
  - `remove-background` / `replace-background` **不写文档**，只返回新 asset url，**必须在同一个 `execute` 内 `Update` 到 fill**。
  - `svg` / `vectorize-image` 只能传 `placeholder: true` 的 frame。
- ⚠️ **写操作是否立即持久化到磁盘：[未证实]**。`execute` 的提交路径只到 `sceneGraph.commitBlock`（内存 + undo 栈），未找到 `saveDocument` / `writeFile` 调用。
  → **实现不得假设已落盘**，收尾必须提示用户保存（见 §11）。

### 3.6 Pen.app 进程模型

- **单实例**：`out/main.js` 里 `const gotTheLock = app.requestSingleInstanceLock(); if (!gotTheLock) { app.quit(); }`。实测 `open -n -a Pen` 退出码 0，但 `pgrep -x Pen` 恒为同一个 pid。
  - `second-instance` handler 会解析参数里的 `.pen` 并 `loadFile` → **`open -n -a Pen x.pen` 只是在既有实例里打开 x.pen**。
  - → **多实例隔离不可行。**
- **多文档单进程**：每个文档一个 renderer，各自带 `--init-params` 里的 `fileURI`；`connectedAgents` 是**按文档**记录的。
- **IPC 是单一全局 Unix domain socket**：`~/.pencil/socket/pencil-desktop.sock`（不是 TCP、不是 XPC）。
  - 路径生成：`path.join(os.homedir(), ".pencil", "socket")` → `pencil-${appName}.sock`；`appName` 来自 `getAppName(){ return "desktop"; }` —— **硬编码，无 CLI 开关**。
  - → **独立 appName 隔离不可行。** 但 VS Code 集成确实用了 `--app visual_studio_code` 这个**另一个通道**，说明 `--app` 至少能选择已存在的实例名，只是无法自造。
- `--agent` 仅用于 `connectedAgents` 归属显示，**不参与文档路由**（已证实）。它是**自由文本、零校验**。
- `--conversation_id` 只作为 app 内建 chat agent 的键与会话文件路径，**与文档选择无关**（已证实）。
- `workspaceFolders` **只影响 agent 的工作目录 / 终端 cwd，完全不影响 MCP 选哪个文档**；键必须是 `file://` 形式。

### 3.7 设计稿没有版本控制兜底

三份 `.pen` 均**未被 git 跟踪**，且忽略原因各不相同：

| 文件 | 忽略来源 |
|---|---|
| `hanzi_write/docs/hanzi_write.pen` | `hanzi_write/.gitignore` 的 `docs/` 规则 |
| `yuexiaoshi/docs/yuexiaoshi.pen` | `~/.gitignore_global` 的 `*.pen`（**全局规则**） |
| `drama_cash/CashTale/docs/CashTale.pen` | `CashTale/.git/info/exclude` 的 `/docs/` |

- 三处仓库 `git log -- '*.pen'` 均无提交；全 `~/Project` 下无 `*.pen.*` / `*.bak` 备份文件。
- `*.pen` 进全局 gitignore 是**用户的既定偏好**，本设计不试图改变它。
- → **反写必须自建补偿备份**（见 §11）。

**凭据禁读清单**（任何流程都必须显式跳过，且绝不写进日志或产物）：

- `~/.pencil/session-desktop.json`（登录 token）
- `~/.pencil/agent-auth`（API key / OAuth access token）
- `~/.dsh/.credentials.yaml`
- `~/.claude/.credentials.json`
- `~/.claude.json` 内的 `github` MCP 条目（含明文 GitHub token）
- `~/.claude/settings.json` 的 `env` 段（含 ANTHROPIC 密钥）
- `~/.continue/config.json` 的 `models[]`（含明文 API key）

---

## 4. 架构：仓库落点与三 harness 扇出

### 4.1 目录结构

```
~/Project/pencil-bridge/                    # git repo，上传 GitHub 的就是它
├── README.md
├── bin/link                                # 幂等扇出脚本
├── skills/
│   ├── pencil-bridge/                      # 主 bundle：唯一物理副本，承载全部 references
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── mcp-toolbox.md              # execute API 全貌与 visitor 写法
│   │       ├── document-routing.md         # filePath / 静默回退 / 哨兵
│   │       ├── write-safety.md             # 写操作安全规程
│   │       ├── design-map.md               # 映射协议
│   │       ├── assets-extraction.md        # 素材提取
│   │       ├── init-and-mcp.md             # /pencil-init 的逐 harness 细节
│   │       ├── stack-flutter.md
│   │       ├── stack-kotlin.md
│   │       └── stack-web.md
│   ├── pencil-init/SKILL.md                # 薄命令，≈40 行，相对路径指回主 bundle
│   ├── pencil-map/SKILL.md
│   ├── pencil-sync/SKILL.md
│   └── pencil-assets/SKILL.md
└── docs/superpowers/
    ├── specs/2026-10-01-pencil-bridge-design.md
    └── plans/                              # writing-plans 的产出
```

### 4.2 为什么是「主 bundle + 薄命令」

三个 harness 都**不解析 `/name arg` 的参数**，路由只能靠技能名本身 → 必须每个命令一个技能目录（方案 C：单命令 + 参数路由，已否决）。

同时，`execute` / `Get` / 变量这套核心 API 知识与坑若被三个命令各维护一份必然漂移（方案 B：三个平行 bundle，已否决）。

→ **唯一物理副本 + 三个薄壳**。薄壳只做三件事：声明触发场景、用**相对路径**（`../pencil-bridge/references/<file>.md`）指向主 bundle 的对应 reference、声明该命令的输入输出契约。

### 4.3 扇出机制

三个 harness 的技能根**两两不相交**，不存在任何「一个目录被三者原生扫描」的公共位置：

| Harness | 用户级技能根 | 触发语法 | 本项目扇出方式 |
|---|---|---|---|
| DSH | `~/.agents/skills/`（rank 500，另有不存在的 `~/.dsh/skills` rank 400） | `/name` | **软链** —— 源码证实跟随：`nodeEntryKind()` 对软链走 `stat` 而非 `lstat` |
| Claude Code | `~/.claude/skills/` | `/name` | **软链** —— 现役配置即有 74 条目录软链 |
| Codex CLI | `~/.codex/skills/` | **`$SkillName`** | **复制** —— 是否跟随软链未证实且无法脚本化验证（§13.3），不赌 |

- 项目级根：DSH `<projectRoot>/.dsh/skills`(rank 100) / `.agents/skills`(200)；Claude Code `<repo>/.claude/skills/`。**本设计不使用项目级根**（技能要跨项目共享）。
- **`bin/link` 对三个技能根采用两种扇出方式**：

```
~/.agents/skills/<name>  ->  ~/Project/pencil-bridge/skills/<name>   # 目录软链
~/.claude/skills/<name>  ->  ~/Project/pencil-bridge/skills/<name>   # 目录软链
~/.codex/skills/<name>    =  仓库内 skills/<name> 的复制副本          # 复制，非软链
```

- **DSH 与 Claude 走目录软链** —— 两者都已被证实跟随软链（DSH 见上表；Claude 有 74 条现役目录软链为证），物理副本只保留仓库内一份。
- **Codex 走复制，不依赖软链**（用户 2026-10-01 裁决）。理由：Codex CLI 无法脚本化调用（`--version` / `--help` 挂起，重定向 stdin 后 rc=0 但零输出），「是否跟随软链」既未证实、也无法在实现前自动实测 —— **不赌**。

- **`<name>` 包含全部五个技能**：`pencil-bridge`（主 bundle）+ `pencil-init` / `pencil-map` / `pencil-sync` / `pencil-assets`。
  **主 bundle 必须一起处理** —— 薄壳正是靠 `skills/` 下这个同级兄弟来解析相对路径（见 §12），少了它相对路径会断。复制分支尤其不能漏，否则副本目录里的同级关系一并断裂。

- 脚本必须**幂等**：软链分支 —— 已存在且指向正确则跳过，存在但不正确则先删再建；复制分支 —— 先删旧副本再整体拷贝，保证与真源一致。`.codex/skills` 不存在则创建。
- 必须有 `--dry-run`。
- 因 Codex 走复制，**每次重跑 `bin/link` 都是一次三 harness 同步** —— 改完技能内容后重跑一次即可让三处一致。

### 4.4 frontmatter 铁律

三个 harness 的**安全交集**是 `name` + `description`：

- `name` 必须匹配 `^[a-z0-9]+(?:-[a-z0-9]+)*$`，且**目录名 == frontmatter `name` == 唯一 slug**。
- `description` 必填。**DSH 缺 description 会丢弃整个技能**。
- **严禁 legacy 驼峰键** `disableModelInvocation` / `modelInvocable` / `userInvocable` → DSH 抛错并**丢弃整个技能**。
- 严禁 `_` 前缀名（DSH 直接看不见，实例：`_gstack-command`）。
- 可选加 `metadata`（对象型，三处都安全）。
- 本项目**不使用** `allowed-tools`（只在 Claude 生效）与 `argument-hint`（只在 Claude 生效），以免造成三 harness 行为不一致。
- 各技能均 `user-invocable`（默认 true）→ `/name` 自动进菜单，**不需要写任何插件**。

### 4.5 Codex 的触发差异（已接受）

Codex 的自定义命令目录机制已不存在（`prompts_dir` / `.codex/prompts` / `slash_commands` 在二进制里零命中），触发语法是 **`$pencil-map`** 而非 `/pencil-map`。

**裁决（用户 2026-10-01 确认）**：接受该差异，不做第二套。技能内容三处完全相同，仅调用前缀不同，文档中同时写明两种写法。

---

## 5. 四条命令

| 命令 | Codex 写法 | 职责 | 默认方向 |
|---|---|---|---|
| `/pencil-init` | `$pencil-init` | 环境自检：Pen.app 是否在跑、MCP 二进制是否存在、各 harness 的 MCP 注册状态、socket 连通性 | 只读诊断；写入前必须询问 |
| `/pencil-map` | `$pencil-map` | 建立 / 更新 `.pencil-bridge/design-map.yaml` | 设计 → 映射表 |
| `/pencil-sync` | `$pencil-sync` | 按设计改代码样式；**反向模式**改设计稿 | 双向 |
| `/pencil-assets` | `$pencil-assets` | 抽取四类素材 | 设计 → 文件 |

`/pencil-bridge`（主 bundle）同样 `user-invocable`，作为总控与诊断入口：它负责解释整体模型、给出当前该用哪条命令的建议，并在用户未指明时做栈探测。

**反写不单开命令**。裁决（用户 2026-10-01 确认）：反写并入 `/pencil-sync` 的反向模式。理由：反写与同步共用同一套 `filePath` 钉住、哨兵校验、补偿备份逻辑，拆成两条命令就要把这套安全逻辑维护两份 —— 与「否决三个平行 bundle」是同一个理由。

---

## 6. `/pencil-init`

### 6.1 定位

**补齐 + 校验**，不是从零配置。实测本机现状：

| harness | pencil 是否已配 | `--agent` |
|---|---|---|
| Codex CLI | ✅ 已有 | `codexCLI` |
| OpenCode | ✅ 已有 | `openCodeCLI` |
| VS Code | ✅ 已有 | `copilotIDE`（且用 `--app visual_studio_code`） |
| **DSH** | ⚠️ **有两份定义** | 都没有 |
| Claude Code / Claude Desktop / Gemini / Kiro / Cursor / Goose / Continue | ❌ 未配 | — |

### 6.2 前置硬门禁

1. **Pen.app 必须在运行**。`pgrep -f "/Applications/Pen.app/Contents/MacOS/Pen"`。不在跑 → 握手必然挂起，先让用户启动。
2. **二进制必须存在且可执行**：`fs.accessSync(bin, X_OK)`。不存在时按 `getMcpBinaryName()` 的架构矩阵算出**应然文件名**再报错（本机只有 `darwin-arm64`，Intel Mac 会缺文件）。

### 6.3 连通性验证配方（已实测跑通）

spawn 目标 `command + args`，依次发 `initialize` / `notifications/initialized` / `tools/list`：

- 成功判据：`result.serverInfo.name === "pencil"`，且 `tools/list` 返回 5 个工具。
- **最强信号**：stderr 出现 `[TransportClient] connected to /Users/howard/.pencil/socket/pencil-desktop.sock`。
- 失败分流：
  - stderr 无 `connected to …` → Pen.app 没跑，或 `--app <name>` 指向不存在的实例。
  - `command` ENOENT → 架构不匹配或 Pen 未装在 `/Applications`。
  - 握手成功但 harness 里看不到工具 → **未重启 harness**（见 §6.6）。

### 6.4 DSH 特例（重复注册风险）

- DSH 上有**两套并行机制**，pencil 同时存在两处：
  - `~/.dsh/profiles/desktop/cordis.patch.yml` 受管块内的 `panel-mcp-pencil`
  - `~/.dsh/storages/mcp_connector.json` 的 `tables.connections."json-pencil"`（`enabled: true`）
  - 两者 `serverName` 都是 `pencil`，argv 也相同 → 实测只起了一个进程，**无法从 argv 区分来源**。
- **`/pencil-init` 第 0 步必须两处都 grep `pencil`**：任一命中就**不写第二处**；两处都有则让用户选一处。
- **绝不修改 `# >>> dsh-skill-mcp-panel:mcp:begin` 与 `# <<< …:end` 之间的内容** —— 面板重写会**静默抹掉**块内手写内容。若必须新增，在**标记之外**追加独立的 `- insert:` 条目（形态参考 `~/.dsh/profiles/tauri/cordis.patch.yml` 里的手写 `- id: mcp-pencil`）。
- `cordis.yml`（合成产物）**不要手改**。
- `mcp_connector.json` 是 373 KB 的版本化领域存储（含快照 / scope 绑定），**建议交给 GUI 或插件 API，不手写**。
- 生效：受管块走面板 = 热加载；手改文件 = 保守起见提示用户重启 DSH 网关。

### 6.5 写入铁律

- **禁止整文件序列化写回**。Pen.app 官方 installer 就是这么干的（`smol-toml` 重序列化 TOML、`JSON.stringify(obj,null,2)` 重写整个 `~/.claude.json`），会：丢掉 `~/.codex/config.toml` 的**全部注释与键序**、把 99,958 B 的 `~/.claude.json`（含 55 个项目状态）**整体重排**。**本设计不复刻该行为。**
- 实现方式：**文本级定点定位容器**，在容器起始 `{` 后插入渲染好的片段，缩进**逐字对齐该文件现有条目**。
- 容器键名有四种形态，**不能写错**：

| 形态 | 用于 |
|---|---|
| `mcpServers` | Claude Code / Claude Desktop / Gemini / Kiro / Cursor / Windsurf |
| `servers` | **VS Code**（`~/Library/Application Support/Code/User/mcp.json`） |
| `mcp` | **OpenCode**（`command` 是 `[exe, ...args]` 数组，`type: "local"`，`enabled: true`） |
| `mcp_servers` | **Codex**（TOML 段） |

- **三个会毒死严格解析器的文件**：
  - `~/.config/opencode/opencode.json` —— 第 164 行有**尾部逗号**，`JSON.parse` 直接抛 `Expecting property name enclosed in double quotes`。
  - `~/.continue/config.json` —— 含 `//` 注释与非法内容。
  - `~/.gemini/antigravity/mcp_config.json` —— **0 字节**，必须当 `{}` 处理。
- **Claude Code 要写两处**：`~/.claude.json` 的连接定义，**加上** `~/.claude/settings.json` 的 `permissions.allow` 必须含字符串 `"mcp__pencil"`（去重），否则工具不生效。
- **写入原子性**：同目录 temp + `rename` + 锁文件。
- **写前备份**：`<file>.pencil-init.bak.<ISO8601>`，同一次运行内不覆盖已有备份。
- **幂等**：键名固定 `pencil`；按「容器键 + 名字」定位，存在则只更新该条目的键。
- `--agent` 值按 harness 填（自由文本、零校验）：`claudeCodeCLI` / `codexCLI` / `openCodeCLI` / `copilotIDE` / `geminiCLI`。**DSH 侧保持与现状一致（不加 `--agent`）**。

### 6.6 探测与生效

- **探测已装 harness 不能靠 `command -v`** —— 本机 `dsh` / `claude` / `codex` / `opencode` / `gemini` / `cursor-agent` 全部找不到（皆 GUI 形态）。只能靠**配置文件是否存在**。
- 生效条件（**除 DSH 外均为「未验证」**，文案中必须如实标注）：

| harness | 生效条件 |
|---|---|
| DSH | 插件受管块热加载；手改文件则重启网关（未实测） |
| Codex CLI | 重开 codex 会话 |
| Claude Code CLI | 新会话（`/mcp` 可查状态） |
| OpenCode | 重开 opencode |
| Claude Desktop | **完全退出并重启** |
| Gemini / Antigravity / Kiro | 新会话 |
| Cursor / VS Code / Windsurf | 重启编辑器或 reload window |
| Goose / Continue | 重启对应进程 |

---

## 7. `/pencil-map` 与 design-map 协议

### 7.1 文件位置

`<projectRoot>/.pencil-bridge/design-map.yaml` —— 放在**项目根**，不进技能仓库。

- 项目根 = 含 `.git` 的最近祖先；无 `.git` 则回落 cwd。
- 取 `projectRoot` 而非 cwd，因为命令可能在子目录里被调用。

### 7.2 schema

```yaml
version: 1

design:
  file: /abs/path/to/xxx.pen        # 绝对路径；会话用它生成 filePath URI
  sentinel:                          # 该项目独有、可稳定读到的顶层节点名，用于校验文档身份
    - "设计主题"
    - "色彩规范"

project:
  root: /abs/path/to/project
  stack: flutter | kotlin | web
  # 单项目多栈时用 stacks 列表
  # stacks:
  #   - { stack: flutter, root: client/ }
  #   - { stack: web,     root: admin/  }

pages:
  - design:
      node: "C01 · 首页"             # 人类可读名
      id: JiRbS                       # 节点 id（优先用 id，名字可能不唯一）
    code:
      file: lib/pages/home.dart       # 相对 project.root
      selector: "class HomePage"      # 定位锚点
    tokens:                           # 该页用到的设计变量 → 代码里的对应物
      primary: "$yxs-primary"
      radius:  "$yxs-radius"
```

### 7.3 建立流程

1. **探测项目栈**：按 `pubspec.yaml` / `build.gradle(.kts)` + `AndroidManifest.xml` / `package.json` 判定；命中多个则记为多栈。
2. **定位设计文件**：优先读 `design-map.yaml`；不存在则询问用户，或用 `get_app_state` + `~/.pencil/.../recent-documents.json` 给出候选（**只读、只作建议，不作判定**）。
3. **建立哨兵**：读设计文件顶层节点名，挑选**该项目独有**的 1–3 个作为 `sentinel`。
4. **提取设计结构**：用 visitor 收集顶层 frame（`context` 属性里的设计说明一并留存）。
5. **扫描代码页面**：按栈的约定找页面入口。
6. **自动配对 + 用户确认**：先给候选配对表，**用户确认后才写文件**（对应最初需求「自动配置 + 映射，我自己确认」）。
7. **导入既有清单**：若项目已有映射清单（如 yuexiaoshi 的 `docs/design-review/manifest.json`，43 页，含 `id` / `code` / `name` / `x,y,w,h` / `screenshot`），作为**导入源**读取，**不取代**它。
8. **另一种模式**：用户**主动输入节点名与页面名**逐条建映射（对应最初需求「我自己主动输入节点名字和页面名字」）。两种模式都要支持，命令行里让用户选。

### 7.4 重跑语义

`/pencil-map` 必须可重跑：已存在的条目**原地更新**，不重建文件；用户手工添加的字段（注释、自定义键）**保留**。

---

## 8. `/pencil-sync`

### 8.1 正向：设计 → 代码

1. 读 `design-map.yaml` → 取 `design.file` 与 `sentinel`。
2. **校验文档身份**（§10）。
3. 对目标页拉取节点树：`Get(<nodeId>, { depth, resolveVariables: true })`。
4. 与代码对照，产出**差异清单**（设计值 → 代码当前值）。
5. **改完给 diff 摘要**（用户裁决：直接改，不做事前确认清单）。
6. 同步的样式属性限：颜色（含变量引用）、间距、圆角、字号、字重、布局方向。
   **不改结构、不改文案**，除非用户显式要求。

### 8.2 反向：代码 → 设计

- 走 §11 的写操作安全规程。
- 目标定位必须用**节点 id**，不用名字（名字不唯一）。
- 写入后**回读刚改节点**的属性确认。
- 收尾**必须提示用户保存**（落盘时机未证实）。

---

## 9. `/pencil-assets`

四类产物（用户裁决：四类全要）：

| 类别 | 取法 | 关键约束 |
|---|---|---|
| **位图** | image fill 的 `url` → 相对 `.pen` 目录解析成绝对路径 → 直接拷磁盘文件 | 不需要 MCP 传字节；保留原扩展名 |
| **矢量** | `path` 节点 + `includePathGeometry: true` 取 `geometry` / `viewBox` / `fill` / `stroke` / `strokeWidth` / `strokeLinecap` / `strokeLinejoin` | `viewBox` 只有带该 option 时才返回；`strokeWidth` 需按 viewBox 比例换算（**待实证**）；`fill:"#00000000"` → `fill="none"`；`stroke` 是变量引用时的落法见下 |
| **图标引用** | `icon` 节点的 `library` + `icon` 名 | **取不到 SVG 源码**，只出「用 lucide 的 `book-open`」这类引用；按栈写成对应库的调用 |
| **变量 token** | `Print(GetVariables())` | 出三栈格式见 §9.2；支持多维 themes |

### 9.1 矢量导出的变量处理

`stroke` / `fill` 可能是变量引用（如 `"$ink"`）。**默认落成 `stroke="currentColor"`**，让代码侧用 CSS/主题控制；提供开关可强制 resolve 成实际色值（`{resolveVariables:true}` 取计算值）。**此默认值是待用户最终确认的实现细节，实现时以开关形式暴露，不写死。**

### 9.2 token 输出格式（按栈）

- **web**：CSS 自定义属性文件（`:root { --yxs-primary: …; }`），多维主题按 `[data-theme]` / `prefers-color-scheme` 分组。
- **flutter**：Dart 常量类（`class YxsTokens { static const primary = Color(0x…); }`）。
- **kotlin**：`colors.xml`（+ 需要时 `dimens.xml` / `styles.xml`）。

### 9.3 提取边界

- **不导出 `icon` 节点的矢量**（Pen.app 不提供源码，`Export` 无 svg 格式）。
- **不导出 html-tailwind / html-css**（`Export` 支持，但那是整页重建，属于 `pencil-design` 那类技能的领域，不是本项目的「提取素材」）。
- 产物落地目录：`<projectRoot>/.pencil-bridge/assets/<timestamp>/`，并在摘要里列出每个文件的来源节点 id。

---

## 10. 多项目并行隔离协议（贯穿全部命令）

Pen.app **单实例**，隔离不能靠多实例。唯一可行路径是 **`filePath` 钉住 + 哨兵校验**：

1. **每次 `execute` 必须显式传 `filePath`**，值用 `file://` 绝对 URI（裸路径只对已打开文档有效）。
2. **永不使用 `get_app_state` 判断写入目标** —— 它跟随用户焦点，永远不可信。
3. **写前哨兵**：读 `design-map.yaml` 的 `sentinel` 节点名，确认连的是对的文档。
4. **停机不重试**：哨兵不符、或收到 `Failed to access file "…"` → **立即停止并报告**，不重试。
5. **提醒用户不要关掉目标 `.pen`** —— 未打开的文档会**静默回退**到焦点文档且不报错，这是最危险的失败模式。
6. 需要打开文档时用 `open -a Pen <path>`（在既有实例里打开），并**等待**用户确认已打开后再继续。

### 10.1 会话启动检查单（每次进命令都走）

- [ ] `Pen.app` 在运行
- [ ] `design-map.yaml` 存在且 `design.file` 可读
- [ ] `design.file` 对应的 `.pen` **已打开**（哨兵读得到）
- [ ] 哨兵命中 → 继续；否则停机报告

---

## 11. 写操作安全规程（反写与任何 `Update` 场景）

1. **写前补偿备份**：`Get(<nodeIds>, { depth })` 记录将被改动节点的原值，落 `<projectRoot>/.pencil-bridge/backups/<ISO8601>.json`。
   **不用文件拷贝** —— 磁盘 `.pen` 可能落后于 app 内存，文件拷贝不等于状态快照。
2. **一次 `execute` 一个逻辑单元**。失败会整次原子回滚，粒度越细越容易恢复。
3. **`Update` 绝不带 `type`**。
4. **数组字段（`fill` / `stroke` / `effect`）整组替换**，不做按索引 patch。
5. **`Update` 不传 `children`**；改结构用 `Replace`。
6. **删除优先用 `enabled: false`**（`Delete` 级联删子树，且对实例后代直接抛错）。
7. **变量只用 merge 模式（`replace: false`）**；**禁止 `replace: true`**。若确需删除变量，必须先 `Print(GetVariables())` 全量备份，并单独向用户确认。
8. **`Generate` 的 `remove-background` / `replace-background`**：返回的 asset url 必须在**同一个 `execute` 内** `Update` 到 fill。
9. **`Copy` 的后代改动必须在同一次调用里做完**。
10. **写后回读**刚改节点的 id 与属性。
11. **收尾提示用户保存**（落盘时机未证实）。
12. **回滚**：用备份文件里的原值 `Update(path, 原值)` 写回。若已被后续 `Replace` 改变了 id，则回滚不可行，**如实报告**而不是静默尝试。

---

## 12. references 组织

主 bundle 承载全部，按需读取（`Base directory for this skill: <path>` 供相对路径解析）：

**栈无关（共用）**：
- `mcp-toolbox.md` —— 5 个工具、`execute` API 全貌、visitor 正确写法、`Print` 通道
- `document-routing.md` —— `filePath` / 静默回退 / 哨兵 / 会话启动检查单
- `write-safety.md` —— §11 全文
- `design-map.md` —— §7 schema 与流程
- `assets-extraction.md` —— §9 全文
- `init-and-mcp.md` —— §6 全文（逐 harness 路径与容器键名）

**分栈（各一份，由 `/pencil-map` 探测后只加载对应的一份）**：
- `stack-flutter.md` —— pubspec、widget 定位、Dart 常量输出
- `stack-kotlin.md` —— gradle、XML 布局 / Compose、`colors.xml` 输出
- `stack-web.md` —— package.json、CSS 变量输出、Tailwind 映射约定（若有）

薄命令 SKILL.md 用**相对路径**指向主 bundle：`../pencil-bridge/references/<file>.md`。

之所以相对路径成立，是因为两个目录在 `skills/` 下是**同级兄弟**：无论宿主按虚拟路径解析（`~/.agents/skills/pencil-map/../pencil-bridge/…` → `~/.agents/skills/pencil-bridge/…`，本身也是软链）还是按 realpath 解析（`~/Project/pencil-bridge/skills/pencil-map/../pencil-bridge/…`），两次都落到真源。

**禁止使用绝对路径** —— 它会让仓库克隆到任意位置后失效。

代价：Codex 若走复制模式，`bin/link` 必须把 `skills/` 下的**全部五个技能**一起复制，否则同级关系断裂。

---

## 13. 未证实项与风险

**必须在实现前实测或实现中标注为不确定的项**：

1. **`strokeWidth` 的 viewBox 换算规则** —— 样本仅一例（72×72 / viewBox 24 / strokeWidth 6 → 2）。标为待实证。
2. **写操作是否立即持久化到磁盘** —— `execute` 提交路径未见 `saveDocument` / `writeFile`。实现不得假设已落盘。
3. **Codex 是否跟随 `~/.codex/skills/<name>` 软链** —— **既未证实，也无法脚本化验证**：`/opt/homebrew/bin/codex`（v0.154.0）的 `--version` / `--help` 直接挂起（30 s+ 零输出），stdin 接 `/dev/null` 后 rc=0 但 stdout/stderr 全空。**已裁决（用户 2026-10-01）：不赌，Codex 一律走复制模式**，见 §4.3。
4. **除 DSH 外，各 harness 写入后是否需重启** —— 无证据，一律按「需重启或新会话」处理并在文案里标「未验证」。
5. **DSH 上 `panel-mcp-pencil` 与 `json-pencil` 谁真正生效** —— argv 相同，无法区分。（按用户指示不深挖）
6. **`--app` 能否指向自造的实例名** —— `getAppName()` 硬编码 `"desktop"`，但 VS Code 用 `visual_studio_code`。未验证可否自造。
7. **Continue 新版 `mcpServers/` 目录形态、Goose 的 `mcpServers` vs `extensions`、Zed 的 `context_servers`、Antigravity 的 schema** —— 均未取证。
8. **`~/.pencil/mcp/visual_studio_code/` 副本是否随 Pen.app 升级同步** —— 未知。

**结构性风险**：

- **静默回退**是本设计面对的最大风险，只能靠哨兵缓解，无法根除（MCP 不报错）。
- **重名技能**可能导致 Claude Code 丢弃整个 personal-skills 集（gstack 注释 #2511 的告警，v2.1.181 严重性存疑）→ 靠「目录名 == name == 唯一 slug」规避。
- 本设计**不解决**「用户切走焦点窗口后，无 `filePath` 的工具读到错误文档」的问题 —— 因此所有需要文档上下文的读操作也必须带 `filePath`。

---

## 14. 验收标准

设计落地后，应能满足：

1. 在 DSH 中输入 `/pencil-map`，能在 yuexiaoshi 项目里生成 `.pencil-bridge/design-map.yaml`，且映射经用户确认。
2. 同时开着 yuexiaoshi.pen 与 hanzi_write.pen，在 yuexiaoshi 项目里跑 `/pencil-sync`，**只读到 yuexiaoshi 的节点**（哨兵通过）；把焦点切到 hanzi_write 窗口后重跑，**结果不变**。
3. 故意把 `design-map.yaml` 的 `design.file` 指向一个未打开的 `.pen` → 命令**停机并报告**，不静默改错文档。
4. `/pencil-assets` 在 hanzi_write 项目的 `E5QUX` 节点上，能导出 7 个 `path` 节点的 SVG（含正确 `viewBox` 与 `fill="none"`），并列出 34 个 icon 节点的库名+图标名引用。
5. `/pencil-init` 在只读模式下能正确报告：Pen.app 状态、二进制存在性、以及 DSH 上 pencil 的两处注册。
6. 反写一次面板样式后，备份文件存在，且回滚可用。

---

## 附录 A · 关键证据索引

| 事实 | 证据位置 |
|---|---|
| `filePath` 生效 + 静默回退 | 本站三探针实测（§3.2 表） |
| 单实例锁 | `/Applications/Pen.app/Contents/Resources/out/main.js:70-73` |
| socket 路径生成 | `node_modules/@ha/mcp/dist/mcp-socket-server.js:7-16` |
| `getAppName()` 硬编码 | `out/desktop-mcp-adapter.js` |
| 路由三级查找 | `node_modules/@ha/ipc/dist/index.js:759-786` |
| `lastFocusedResource` 更新 | `out/app.js:586`、`out/app.js:627-629` |
| DSH 跟随软链 | `dsh-skill-filesystem/lib/index.js:764-772`（`stat` 而非 `lstat`） |
| DSH 技能名正则 | `@deepseek-ai/dsh-skill/lib/index.js:17` |
| DSH skills rank | `dsh-skill-filesystem/lib/index.js:150-187` |
| `json-pencil` 键名规则 | `dsh-mcp-connector/lib/connectors/json-connector.js` `stdioRecord()` |
| 工具名前缀 | `dsh-mcp-connector/lib/governance.js:27` |
| Pen 官方整文件重写 | `app.asar` 内 `@ha/mcp/installer.js` |
| pen-dev 技能资源 | `app.asar` 内 `out/skills/pen-dev/`（15 个 md） |
| 写 API 手册 | `docs/reference/pencil-write-api-manual.md`（本仓库内，554 行） |
