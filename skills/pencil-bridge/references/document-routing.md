# document-routing —— 多项目不窜：`filePath` 路由、静默回退与哨兵

本文是 pencil-bridge 套装里**唯一**的文档路由参考，也是「**多项目不窜**」的全部依据。来源：spec §3.2（设计规范 ':70-121'）、§10.1（':513-521'）。
**三探针表、哨兵代码块与失败原文逐字保留，不要改写**（探针 2 的路径已按本套件的「禁止绝对路径引用」守卫改写为占位形态，语义不变 —— 见 §1 表下注）。

四个薄壳（`pencil-init` / `pencil-map` / `pencil-sync` / `pencil-assets`）与 hub `pencil-bridge` 都引用本文件（薄壳的 `references/` 引用行随各自 `SKILL.md` 一并落地）；其中 `pencil-map` / `pencil-sync` / `pencil-assets` 明示引用本文件的哨兵范式与会话启动检查单（`pencil-init` 按可选方式引用哨兵）。

---

## 1. 三探针实测

三探针实测：

| 探针 | `filePath` 传入 | 焦点文档（`get_app_state`） | 实际读到的文档 |
|---|---|---|---|
| 1 | `file:///…/yuexiaoshi.pen` | yuexiaoshi | yuexiaoshi（无区分力：焦点恰好相同） |
| 2 | `/abs/path/to/definitely-not-real-xyz.pen` | yuexiaoshi | **yuexiaoshi**（静默回退，**无任何报错**） |
| 3 | `file:///…/hanzi_write.pen`（**非焦点**） | yuexiaoshi（前后均未变） | **hanzi_write** ✅ |

探针 3 是决定性证据：读到 hanzi_write 的顶层 frame，而焦点**始终**是 yuexiaoshi。

> 探针 2 的原始写法是本机一个**临时目录**下的路径；本文件按守卫要求改写成 `/abs/path/to/` 占位。改写后它仍然是**裸路径**，仍然指向一个**确实不存在**的文件 —— 这两点正是探针 2 要验证的东西（裸路径只对已打开文档有效，设备比对必然失败，才会走到兜底回退）。

---

## 2. 路由结论

- `execute` 的 `filePath` **有效**：按文档路由，且**不改变** `lastFocusedResource`（探针 3：焦点前后均未变）。**读**已由三探针实测；**写**由同一路由机制承担，但**写入路径未单独实测【未验证】**。
- **最危险的失败模式**：**目标文档未打开、或路径不可解析时，请求静默回退到「最后聚焦的文档」，不报错。**（实测手段是**读**。）
  由此**推论**：写入会安静地落到**另一个项目**的设计稿上，**没有任何错误信号**【未验证：写入路径未单独实测】；哨兵（§5）是当前**已知唯一**能提前发现的护栏。
- 路由实现是**三级查找**：
  1. `file://` URI 直命中；
  2. 遍历设备比对 `getFileURIForPath(filePath) === deviceURI`（**裸路径只对已打开文档有效**）；
  3. 兜底 `lastFocusedResource`。
  第 1、2 级都不命中时落到第 3 级 —— 这里就是「静默回退」的发生位置。
- `lastFocusedResource` 在**用户点击窗口**时更新（`window-focused` 事件）⇒ **焦点随时可能被用户改掉**，因此它**永远**不是可信的写入目标。
- 推荐做法（本套件采用的做法）：**每次 `execute` 都显式传 `file://` 绝对 URI 形式的 `filePath`**（裸路径只对已打开文档有效），并且**写前必跑哨兵**（§5、§7）确认文档身份。

---

## 3. 哪些工具没有 `filePath`

**三个**工具的 schema 里**没有** `filePath`：`get_app_state` / `read_skill` / `get_style`。
它们**永远命中「最后聚焦的文档」兜底分支** —— 无法指定目标文档，只能跟随焦点。

⇒ **`get_app_state` 绝不能用来判断写入目标。** 它返回的是用户当前焦点，而焦点随时会被用户点走（§2）。

`browser` 是**另一个**情形（2026-10-01 stdio `initialize` + `tools/list` 实测）：它的工具 schema **确实声明了** `filePath`，且列在 `required = ["filePath","action"]` 里（描述文案为 "An optional file path to access a .pen file."）。
但它**是否实际参与文档路由【未验证】** —— 本文件只陈述 schema 事实，**既不断言它按文档路由，也不断言它走兜底分支**，更不要依赖它来选择目标文档。

**旧写法作废**：若在别处读到「四个没有 `filePath` 的工具（… 含 `browser`）」，那是已废弃的初稿说法，**以本节为准**。

---

## 4. 无法切换活动文档

- MCP 二进制里**没有任何 open / switch / activate / focus document 工具** ⇒ **无法通过 MCP 切换活动文档**。
- 要打开某个 `.pen`，只有两条路：
  1. `open -a Pen <path>`（在**既有实例**里打开）；
  2. 让用户**手动**打开。
- 用 `open -a Pen <path>` 打开后必须**等待**用户确认已打开，再继续后续步骤（否则写请求会静默回退，见 §2）。

---

## 5. 只读哨兵范式

本设计全程用它校验文档身份。**逐字抄录，不要改写**：

```js
const out = [];
Get(document, (n, c) => { if (c && c.depth === 1) out.push(n.name); });
Print("SENTINEL_TOP:", out.slice(0, 3).join(" | "));
Print("SENTINEL_COUNT:", out.length);
```

已知基线（顶层节点计数）：

| 文档 | 顶层计数 |
|---|---|
| `yuexiaoshi.pen` | **136** |
| `hanzi_write.pen` | **183** |

`SENTINEL_COUNT` 与基线不符 ⇒ 十有八九连错了文档（正是静默回退）⇒ **停机报告**（§7）。

---

## 6. 失败原文

文档真的不可达时，错误原文（**逐字**）：

```
Failed to access file "<path>". A file needs to be open in the editor to perform this action.
```

---

## 7. 会话启动检查单（每次进命令都走）

逐字抄录 spec §10.1：

- [ ] `Pen.app` 在运行
- [ ] `design-map.yaml` 存在且 `design.file` 可读
- [ ] `design.file` 对应的 `.pen` **已打开**（哨兵读得到）
- [ ] 哨兵命中 → 继续；否则停机报告

**哨兵不符 → 停机报告，不重试。** 收到 `Failed to access file "…"` 同样立即停止并报告，**不重试**。
静默回退**没有**错误信号，重试只会把错误的写入再做一遍；报告比自愈安全。

---

## 相关 reference

- `../pencil-bridge/references/mcp-toolbox.md` —— 已知工具面（5 个工具）、`execute` API 全貌、visitor 写法
- `../pencil-bridge/references/write-safety.md` —— 写操作安全规程、`editId` 失败修补的确切流程
