# write-safety —— 反写安全规程、写操作语义与凭据禁读

本文是 pencil-bridge 套装里**唯一**的写安全参考；`/pencil-sync` 的反向（写回设计稿）模式**必须逐条执行**它。来源：spec §11（设计规范 ':525-539'）、§3.5（':157-172'）、§3.4（':148-155'）、§3.7（':187-209'），以及写 API 手册第 8 节 `docs/reference/pencil-write-api-manual.md`（':390-426'）。
**§11 的 12 条规程与 §3.7 的凭据清单逐字保留，不要改写。**

---

## 1. 十二条写安全规程（spec §11 逐字搬入）

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

## 2. 为什么不能用文件拷贝做备份

- **磁盘 `.pen` 可能落后于 app 内存**，所以**文件拷贝不等于状态快照**。`execute` 只作用于活文档的内存 scene graph（§5），此时磁盘上的 `.pen` 未必反映用户屏幕上的真实状态 —— 拷一份磁盘文件，可能备份到一个既非「改动前」也非「改动后」的中间态。
- **没有版本控制兜底**：三份 `.pen` 均**未被 git 跟踪**，且忽略来源各不相同 —— `hanzi_write/.gitignore` 的 `docs/` 规则、`~/.gitignore_global` 的 `*.pen`（全局规则）、`CashTale/.git/info/exclude` 的 `/docs/`。三处仓库 `git log -- '*.pen'` 均无提交；全 `~/Project` 下无 `*.pen.*` / `*.bak` 备份文件。`*.pen` 进全局 gitignore 是**用户的既定偏好**，本设计不试图改变它。
  ⇒ **反写必须自建补偿备份**（规程 1）。
- **正确的备份 = 状态快照，不是文件副本**：写前用 `Get(<nodeIds>, { depth })` 读出**将被改动节点**的 id 与属性原值，序列化落盘：
  - 路径：`<projectRoot>/.pencil-bridge/backups/<ISO8601>.json`（每次写操作一份，文件名用 ISO8601 时间戳）。
  - `depth` 要覆盖到本次可能改动的**每一层后代**；只备份目标节点本身而漏掉子树，回滚时无法复原结构。
  - 回滚时按规程 12，用文件里的原值 `Update(path, 原值)` 写回；**若原 id 已被后续 `Replace` 换掉，回滚不可行，如实报告**。

---

## 3. 写操作语义速查表（spec §3.5）

| 操作 | 语义 | 必须记住的坑 |
|---|---|---|
| `Update` | 属性 **partial merge** | **数组字段（`fill` / `stroke` / `effect`）是整组替换**，没有按索引 patch（规程 4）；**绝不带 `type`**，带了会走整节点替换路径 `replaceNode`，行为不可预期（规程 3）；**传 `children` 会「clearChildren + 整体重插」（产生新 id）**，不要用，改结构用 `Replace`（规程 5） |
| `Replace` | **全量替换（含 x/y）**，返回**新 id** | 改结构用它；替换后旧 id 失效 ⇒ 之后按旧 id 回滚不可行（规程 12） |
| `Move` | `index` **只有非负 number 生效**，否则**静默放到末尾**；`parent` 省略表示留在原父级 | 传了非法的 index 不报错，只是安静地挪到末尾 —— 写完必须回读确认位置 |
| `Delete` | **级联删整棵子树** | 对**组件实例的后代**直接抛 `Cannot delete descendants of instances!`；节点不存在只发 warning、**不报错** ⇒ 删除优先用 `enabled: false`（规程 6） |
| `Copy` | **reusable 节点会变成 `ref` 实例** | 对副本后代的改动**必须在同一次 `Copy` 的 `descendants` 里**，之后再 `Update` 原 id **必然失败**（规程 9） |
| `SetVariables`（spec §3.4） | `replace` 默认 `false`（**merge**） | **`replace: true` 会删掉未列出的本文件变量，并清空已列出变量的 themed 值**；因为**没有定向删除变量的 API**，删变量只能全量重写 ⇒ **本设计默认禁用 `replace: true`**（规程 7）；导入的变量不可改 |
| `Generate` | 全部**异步**，结果在 `execute` 返回后才落地 | `remove-background` / `replace-background` **不写文档**，只返回新 asset url，**必须在同一个 `execute` 内 `Update` 到 fill**（规程 8）；`svg` / `vectorize-image` 只能传 `placeholder: true` 的 frame |

变量读写的补充（spec §3.4）：唯一读取入口是 `Print(GetVariables())`，返回 `{ variables, themes? }`；写回 `SetVariables` 时**名字不带 `$`**，节点内引用写作 `"$primary"`；主题可以是多维的（如 `{"mode":["light","dark"], "locale":["zh","en"]}`）。

---

## 4. undo 与失败语义

**一次 `execute` = 一个撤销块**：

- 成功路径（`[代码交叉验证]`）：`this.sceneManager.scenegraph.commitBlock(i.block,{undo:!0})` → `commitBlock(e,n){ n.undo && this.sceneManager.undoManager.pushUndo(e.rollback) }`
- 失败路径（`[代码交叉验证]`）：`this.sceneManager.scenegraph.rollbackBlock(i.block)` → `applyFromStack([e.rollback], null)`
- 即：一次 `execute` 产生的所有改动合成一个 rollback block，提交时入 undo 栈。用户 Ctrl/Cmd+Z 会**整步撤销，不会半途**。
- **失败会整次原子回滚**，包括本次创建的全局变量（`[文档]` 逐字："In case of an error, all modifications and the created globals will be reverted."）。
- **失败时 `Print` 与截图都不返回**：`[文档]` 逐字 "Values printed by a failed `execute` call are not returned."、"Screenshots of a failed `execute` call are not returned."。⇒ 失败那一次的 `Print` 回读（规程 10）拿不到任何值，**不能靠它判断失败原因**。
- **一次 `execute` 可以写任意多个节点**（循环 / 数组 / `for...of`），原子性仍然成立；但按规程 2，**不要因此把多个逻辑单元塞进一次调用** —— 粒度越细越容易恢复。
- **跨 `execute` 不共享局部变量**：每次 `execute` 是独立作用域，`const` / `let` 声明的局部变量与 helper 不跨调用；需要在调用间保留值，只能靠**不带声明的赋值**（`myNodeId = Insert(...)`）—— 但全局赋值也**同样在失败时被一起回滚**。

### 4.1 失败后的 `editId` 修补流程（确切用法）

失败**不要重发整段**，用失败消息里的 `editId` + `edits: [{find, replace}]` 打补丁重跑。`[文档]` 逐字：

> "When an `execute` call fails, ALWAYS fix it with the `edits` parameter and the `editId` from the failure message - never resend the snippet. If the patched snippet fails again, keep fixing it with further `edits` under the same `editId`; `find` must then match the snippet as already patched."

参数校验规则（`[代码交叉验证]` 错误原文）：

- `edits` 必须是 `{find, replace}` 对象的数组；每项 `find` 为非空 string、`replace` 为 string：
  - `` "`edits` must be an array of `{ find, replace }` objects. Send the `edits` that patch the failed snippet, or resend the full corrected snippet in `input`." ``
  - `` `edits[${s}] must be an object with a non-empty \`find\` string and a \`replace\` string!` ``
- 用 `edits` 必须同时给 `editId`；两者缺一都报错：
  - `` "`editId` requires `edits`. ..." `` / `` "`editId` is required when using `edits`. Pass the editId printed in the failure message." ``
- `input` 与 `edits` **不能同时给**：`"Provide either `input` or `edits`, not both. Use `edits` alone to patch and re-run a failed call."`
- `edits` 不能作为 partial 调用：`` "`edits` cannot be sent as a partial call. Send the complete `edits` array in a single non-partial `execute` call." ``
- 未命中时提示：`"- The failed snippet \"…\" was NOT modified. Fix the `edits` so each `find` matches its content exactly and call `execute` again with the same `editId`, or resend the full corrected snippet in `input`."`
- 修补后 snippet **从头重跑**（不是增量执行）；未命中时原 snippet **未被改动**。`edits` 的 `all: true` 语义为替换全部匹配（默认要求唯一匹配）。

---

## 5. 未证实项

- ⚠️ **写操作是否立即持久化到磁盘：[未证实]**。`execute` 的提交路径**只到 `sceneGraph.commitBlock`**（内存 scene graph + undo 栈）；在编辑器 bundle 的 execute 提交路径中**没有找到任何 `saveDocument` / `writeFile` 调用**。
- 由此的**合理推断（不得当成定论）**：写操作**立即反映到用户正在编辑的活文档 UI**，磁盘 `.pen` 的落盘由 App 自身的保存流程负责，**不由 `execute` 触发**。
- ⇒ **实现不得假设已落盘**：收尾必须提示用户保存（规程 11）；若需要交付文件，显式走 `Export` 或让 App 保存，而不是假设 `execute` 已写盘。
- 另一处相邻的未证实项：**写入路径的文档路由未单独实测**（读路径已由三探针实测）—— 见 `../pencil-bridge/references/document-routing.md`。

---

## 6. 凭据禁读清单（spec §3.7 逐字搬入）

任何流程都必须**显式跳过**，且**绝不写进日志或产物**：

- `~/.pencil/session-desktop.json`（登录 token）
- `~/.pencil/agent-auth`（API key / OAuth access token）
- `~/.dsh/.credentials.yaml`
- `~/.claude/.credentials.json`
- `~/.claude.json` 内的 `github` MCP 条目（含明文 GitHub token）
- `~/.claude/settings.json` 的 `env` 段（含 ANTHROPIC 密钥）
- `~/.continue/config.json` 的 `models[]`（含明文 API key）

---

## 相关 reference

- `../pencil-bridge/references/mcp-toolbox.md` —— 已知工具面（5 个工具）、`execute` API 全貌、visitor 写法、`editId` 修补的调用形态
- `../pencil-bridge/references/document-routing.md` —— `filePath` 路由、静默回退、哨兵、会话启动检查单
