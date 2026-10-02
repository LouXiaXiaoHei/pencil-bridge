# spec §14 验收实测记录

> **状态：六条全部执行完毕。** 本文件是 plan Task 15 Step 8 要求的验收记录，由 `.superpowers/sdd/2026-10-01-pencil-bridge-implementation/task-15-acceptance-record-draft.md` 定稿而来。
>
> **执行方式说明（必读）：** spec §14 的原文措辞是「在 DSH 里敲 `/命令`」。本次六条**全部由 controller 执行**——用**真实 DSH 技能读取器**加载 `~/.agents/skills/pencil-*`（软链指向本仓库 `skills/`），再逐条执行技能正文所载流程。其机制等价性在于：`/命令` 的实现方式就是把技能正文注入为指令，因此「正文 + 输入」完全相同，**差别仅在键入者**。① 的配对表按要求**拿给用户确认过**后才写入。**本记录不声称「用户亲手键入过」**。
>
> **反例声明：** 本文件只写实测到的读数。凡未跑过的分支一律列在 §3，**绝不写成「通过」**。

- **被验收提交**：`b7f509d9c40b467c36bfe8c4df3621cd38ebf38d`（分支 `feat/pencil-bridge-impl`，工作树干净）
- **提交链尾部**：`fa6431d`（分支点）→ … → `5022ce4` → `2100293` → `b7f509d`
- **验收执行时间**：2026-10-02（CST）
- **记录者**：controller（全部六条的执行与取证）；① 的映射写入经用户确认

---

## 0. 结论摘要

| # | spec §14 验收条目 | 执行者 | 判定 | 依据 |
|---|---|---|---|---|
| ① | `/pencil-map` 在 yuexiaoshi 生成 `design-map.yaml` 且映射经用户确认 | controller（用户确认映射） | **通过** | §2.1 |
| ② | 双文档并行不窜（哨兵只读到 yuexiaoshi） | controller | **通过** | §2.2 |
| ③ | `design.file` 指向未打开的 `.pen` ⇒ 停机并报告 | controller | **通过（条件性）** | §2.3 |
| ④ | `E5QUX` 导出 7 个 `path` 的 SVG + 列出 34 个 `icon` 引用 | controller | **通过** | §2.4 |
| ⑤ | `/pencil-init` 只读报告 Pen.app 状态 / 二进制 / DSH 注册 | controller | **通过** | §2.5 |
| ⑥ | 反写一次面板样式 ⇒ 有备份 + 可回滚 + 提示保存 | controller | **通过** | §2.6 |

**⇒ 整条验收结论：通过。** 六条均有原始读数支撑；③ 的**条件性**与全部未覆盖项见 §2.3 与 §3。

---

## 1. 前置条件核对（只读）

| 项 | 实测值 | 判定 |
|---|---|---|
| Pen.app 在运行 | pid **95880** | ✓ |
| MCP 二进制存在 | `/Applications/Pen.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-arm64` = **4,691,040 B**，`-rwxr-xr-x`，`Mach-O 64-bit executable arm64`，mtime `Sep 30 10:23` | ✓ |
| socket 存在 | `/Users/howard/.pencil/socket/pencil-desktop.sock`，`srwxr-xr-x@`，mtime `Oct 1 20:43`，目录下仅此一个 | ✓ |
| 受管块 | `~/.dsh/profiles/desktop/cordis.patch.yml`（3,400 B）`:85` begin / `:102` `- id: panel-mcp-pencil` / `:105` `serverName: pencil` / `:120` end | ✓ |
| `tables.connections` 实际键 | **只有** `chrome-devtools-chrome-devtools`（无 pencil） | 见 §2.5 的 R41/R45 口径 |
| `recent-documents.json` | 2,386 B / **18** 条；`[0]` yuexiaoshi.pen、`[1]` hanzi_write.pen | ✓ 两份已打开 |

---

## 2. 逐条证据

### 2.1 验收 ① —— `/pencil-map` 在 yuexiaoshi 生成映射

**执行**：在项目根 `/Users/howard/Project/yuexiaoshi`（含 `.git`）逐条执行 `design-map.md` §3 的建立流程八步。

**第 1 步 栈探测**：`find` 排除 `node_modules` / `.dart_tool` / `Pods` / `build` / `dist` / `.git` 后共 **8 个命中**，其中 **6 个落在 `client/android/`**（Flutter 的 Android 宿主壳）：

```
./admin/package.json
./client/pubspec.yaml
./client/android/app/build.gradle.kts
./client/android/build.gradle.kts
./client/android/settings.gradle.kts
./client/android/app/src/{debug,main,profile}/AndroidManifest.xml
```

佐证：`client/{android,ios,macos,linux,windows,web}` 六个宿主壳目录**全部存在且全部没有 `package.json`**；`client/web/` 只有 `favicon.png` / `icons` / `index.html` / `manifest.json`，**构建器配置 0 个**。Web 侧 `admin/` 有 `package.json`（含 `react` / `vite` / `react-router`）+ `admin/vite.config.ts`，散装 `*.html` **0** 个。

⇒ **`stacks` = 2**：`{ stack: flutter, root: client/ }`、`{ stack: web, root: admin/ }`。
（这正是最终整支复审 **I-1** 修复后的行为：宿主壳属父栈、不计入独立栈。修复前一次朴素扫描会得出 **3–4 栈**。）

**第 7 步导入源**：`docs/design-review/manifest.json` 是 **43 条** `{id, code, name, x, y, w, h, screenshot}` 数组，第 1 条 `{"id":"JiRbS","code":"C01","name":"C01 · 首次启动与引导 / Welcome",…}`。

**第 5 步代码页面扫描**：Flutter 侧页面类 3 个 —— `LibraryView`（`client/lib/modules/library/library_view.dart:14`）、`ReaderView`（`client/lib/modules/reader/reader_view.dart:12`）、`SettingsPage`（`client/lib/modules/settings/settings_page.dart:10`）；Web 侧 React Router 7 六个模块 —— `LoginPage`（`admin/app/routes/login.tsx:63`）、`DashboardHome`（`admin/app/routes/dashboard.home.tsx:89`）、`UsersPage`（`admin/app/routes/dashboard.users.tsx:133`）、`ReportsPage`（`admin/app/routes/dashboard.reports.tsx:104`）、`ConfigPage`（`admin/app/routes/dashboard.config.tsx:159`）、`DashboardLayout`（`admin/app/routes/dashboard.tsx:40`）。

**第 6 步配对（用户确认那道门）**：43 页里 **8 页**有代码落点，配对表拿给用户确认，**用户确认按此写入**。`A06` 无对应路由、其余 34 页设计先行无代码落点 ⇒ 记为待确认候选。

| 设计页 | 代码落点 | selector |
|---|---|---|
| C02 书架首页 | `client/lib/modules/library/library_view.dart` | `class LibraryView` |
| C07 统一阅读器与沉浸模式 | `client/lib/modules/reader/reader_view.dart` | `class ReaderView` |
| C34 设置首页与阅读偏好 | `client/lib/modules/settings/settings_page.dart` | `class SettingsPage` |
| A01 管理端登录 | `admin/app/routes/login.tsx` | `LoginPage` |
| A02 运营数据面板 | `admin/app/routes/dashboard.home.tsx` | `DashboardHome` |
| A03 用户列表与权益详情 | `admin/app/routes/dashboard.users.tsx` | `UsersPage` |
| A04 举报与内容审核 | `admin/app/routes/dashboard.reports.tsx` | `ReportsPage` |
| A05 系统、AI 与存储配置 | `admin/app/routes/dashboard.config.tsx` | `ConfigPage` |

**产物**：`/Users/howard/Project/yuexiaoshi/.pencil-bridge/design-map.yaml`（**3,062 B**，本次新建）。`design.sentinel: ["阅小识   /   YUEXIAOSHI", "可复用组件"]`；`pages[].code.file` 一律相对 `project.root` 书写。

**判据（全绿）**：
- `js-yaml` 解析 **OK**；`pages` = **8** 条。
- 8 个 selector **逐个唯一可 grep**（每个在本文件命中 1 次，全仓命中文件数 1）。
- **读清单未被改动**：`docs/design-review/manifest.json` = **8,739 B** / `sha256 de607a878a9f1fd9b6bd84229dc7949f0674aeff0d34b7adbececab81308b396` / `design-review/` 文件数 **46**，与本步执行**前**完全一致（映射是只读过程，不该改读清单）。

**⇒ ① 通过。**

### 2.2 验收 ② —— 双文档并行不窜

**执行**：两份 `.pen` 同时打开的前提下，用**互斥哨兵探针**各发一次（`document-routing.md:69-74` 的逐字范式）。

```
filePath = file:///Users/howard/Project/yuexiaoshi/docs/yuexiaoshi.pen
  SENTINEL_TOP:   阅小识   /   YUEXIAOSHI | 静读深蓝，智识微紫 · 43 SCREEN SYSTEM · 中文主稿 / English-re | 可复用组件
  SENTINEL_COUNT: 136        ← = 基线 136
  SENTINEL_HIT:   yes yes
  TOP_FRAME_COUNT: 127   TOP_TYPES: {"text":3,"frame":127,"ref":6}

filePath = file:///Users/howard/Project/hanzi_write/docs/hanzi_write.pen
  SENTINEL_TOP:   设计主题 | 设计说明 | 色彩规范
  SENTINEL_COUNT: 183        ← = 基线 183
  HIT_YXS: NO    HIT_HZ: yes
```

**关键判据**：两发返回**两棵不同的树**（136 vs 183，且 hanzi_write 那发**不含** yuexiaoshi 的哨兵）⇒ 两者都真的已打开（第 ①/② 级直命中），**不是静默回退**。两份顶层名完全不同 ⇒ 这是**不可伪造**的区分证据。

**为什么这条有意义**：`document-routing.md:18` 探针 3 已证「**已打开但未聚焦**时第 ① 级 URI 直接命中，不会静默回退」——本步在真实双文档场景复现了它。

**⇒ ② 通过**（并行不窜：读 yuexiaoshi 时读到的是 yuexiaoshi，读 hanzi_write 时读到的是 hanzi_write）。

### 2.3 验收 ③ —— 指向未打开的 `.pen` 必须停机并报告

**执行**：`design.file` 指向**未打开**的 `kinobite.pen`，跑同一条哨兵范式。**当次焦点文档 = `/Users/howard/Project/hanzi_write/docs/hanzi_write.pen`**（`get_app_state` 实测记录）。

```
DESIGN_FILE_REQUESTED: /Users/howard/Project/drama_cash/KinoBite/pen/kinobite.pen
SENTINEL_EXPECTED: ["阅小识   /   YUEXIAOSHI","可复用组件"]      ← design-map.yaml 登记的（yuexiaoshi 的）
SENTINEL_TOP: 设计主题 | 设计说明 | 色彩规范
SENTINEL_COUNT: 183
HIT1: NO      HIT2: NO
VERDICT: 哨兵不符 → 停机报告，不重试
IS_HANZI_WRITE_TREE: yes（回退落到了 hanzi_write）
```

⇒ 请求的 `design.file` 未打开 ⇒ 读路径静默回退到焦点文档（hanzi_write）⇒ 读回的树**不含** yuexiaoshi 哨兵 ⇒ 按 `document-routing.md:106`「**哨兵不符 → 停机报告，不重试。**」**停机**。**③ 判据成立，零写入**（全程只跑一条只读 `Get`）。

#### ③ 的条件性（重要，务必连读）

③ 的机制是**哨兵**，而不是「检测目标文件是否已打开」——MCP 没有查询文档是否打开的手段，读路径的三级查找（`document-routing.md:31-37`）在目标未打开时会静默回退到 `lastFocusedResource`。**因此 ③ 只在「回退落点 ≠ 哨兵期望的那一份」时成立。**

本会话实测了**同一发探针、唯一变量 = 焦点文档**的对照：

| 焦点文档 | 请求的 `filePath` | 实际读回的树 | 对 yuexiaoshi 哨兵 | 检查单判定 | ③ 是否有效 |
|---|---|---|---|---|---|
| **yuexiaoshi.pen** | 未打开的 `kinobite.pen` | **yuexiaoshi 自己的**（`阅小识…`，136） | **命中** | 哨兵命中 → 继续 | ❌ **假绿**（且会真的往下写 yuexiaoshi 的代码） |
| **hanzi_write.pen** | 未打开的 `kinobite.pen` | **hanzi_write 的**（`设计主题…`，183） | **不符** | 停机报告，不重试 | ✅ 有效 |

⇒ 两发唯一变量是焦点，结果从「假绿」翻成「正确停机」——**这就把「判定由哨兵做出」钉死了**。

**这不是本实现引入的缺陷**：spec §14③ 措辞本身是**条件性承诺**；交付物的会话启动检查单逐字抄录 spec §10.1（`document-routing.md:99` 自证），并已在自己文件里显式记下这一盲区（`document-routing.md:109-114`，首行写明「本套件补充（非 spec 逐字文本）」）。最终整支复审已把它列为必答项，裁定为「可交付 + 补注」，补注已落地。

**操作含义**：当**焦点文档恰好就是本项目目标 `.pen`** 时，「未打开但回退到同一份」与「已打开」**不可区分**；此时须由用户确认已打开，或改用**哨兵期望值不同**的 `.pen` 作靶。**不得**改用 `get_app_state` 判断写入目标（`document-routing.md:46`；本步只用它记录焦点，未用它做任何写入判定）。

**⇒ ③ 通过（条件性）**，前提已满足且当次焦点文档已记录。

### 2.4 验收 ④ —— `E5QUX` 导出 7 个 `path` 的 SVG + 列出 34 个 `icon` 引用

**执行**：在 `/Users/howard/Project/hanzi_write`（先为其生成 `.pencil-bridge/design-map.yaml`：1 栈 Flutter、哨兵 `["设计主题","色彩规范"]`）逐条执行 `pencil-assets`。

**`Get("E5QUX", visitor, {includePathGeometry: true, depth: 25})` 直方图**：

```
{"frame":60,"text":18,"icon":34,"path":7}     ← 与 spec :598 逐字一致
```

- **34 个 `icon` 全部 `library="lucide"`**（`icons.json` `rows: 34`、`allTrue(lucide)`）。
- **7 个 `path` 全部** `viewBox [0,0,24,24]`、`width/height 72`、`fill "#00000000"`、`stroke "$ink"`、`strokeWidth 6`、`linecap/linejoin "round"`。

7 个名字与 id：`icon_tmpl_trace`(`n9JPfR`) / `icon_game_huarongdao`(`A1HCj`) / `icon_character_of_day`(`ik97J`) / `icon_type_poetry`(`bTqfH`) / `icon_type_idiom`(`uCYMj`) / `icon_type_xiehouyu`(`w7xP9`) / `icon_membership`(`YgcNR`)。

**产物落盘** `/Users/howard/Project/hanzi_write/.pencil-bridge/assets/2026-10-02T130955Z/`：`svg/` **7 个 SVG**（254 / 381 / 254 / 247 / 277 / 304 / 328 B）+ `svg/_manifest.json` + `icons.json`（34 条）。

**判据（全绿）**：`viewBox == "0 0 24 24"` **且** `fill == "none"` **且** `d != "..."`，**7/7 通过**。

> **过程缺陷（已修，方法级记录）**：首版产物有**两处转录错误**——图标只写了 **3** 条（源为 34），且 `icon_type_xiehouyu` 的 `d` **多了一个字符**（长度 124 vs 源 **123**，肉眼几乎不可能发现）。修法是**让机器自证**：在 `execute` 沙箱内对每段 geometry 自算 **FNV-1a**，写入后读回文件重算同一哈希并比对长度。第二版 7/7 通过，FNV-1a 依次 `6cca3a40` / `d4b31588` / `4e0254d4` / `ca540090` / `162773e1` / `14824494` / `d1f4b35e`（长度 73/200/73/66/96/123/147）。**教训：把机器生成的字符串搬进文件，必须两端各算同一个校验和；长度单独不够。**

**未打开路径的负控**：本步全程以 `includePathGeometry: true` 读取；若省略该选项，`geometry` 会返回字面量 `"..."`（静默、不报错）——这正是最终整支复审 **I-2** 修复的那条机制。

**⇒ ④ 通过。**

### 2.5 验收 ⑤ —— `/pencil-init` 只读报告

**执行**：用真实 DSH 读取器加载 `pencil-init`，逐条执行其「流程」第 1 步只读诊断。**契约执行结果：报告并停止**——`pencil-init` 的「输出契约」+「铁律」第 4 条要求「若 DSH 上 pencil 已注册，报告并停止，不写第二处」。判定**已注册** ⇒ **本轮零写入**，未触碰受管标记块内部。

| 诊断项 | 实测读数 | 判定 |
|---|---|---|
| Pen.app | 在运行，pid **95880**；`/Applications/Pen.app` 存在 | ✓ |
| MCP 二进制 | 4,691,040 B，`-rwxr-xr-x`，`Mach-O 64-bit executable arm64`，`test -x` yes | ✓ |
| socket | `srwxr-xr-x@`，`[ -S ]` yes | ✓ |
| **DSH 注册** | `cordis.patch.yml:102` `- id: panel-mcp-pencil` / `:105` `serverName: pencil` / `:120` end（文件最后一行） | ✓ 与 `init-and-mcp.md:40` 逐字一致 |
| **DSH `tables.connections`** | 顶层键 `connections, grants, catalog, snapshots, governance, connection_scopes, tool_catalog`；`connections` **仅** `chrome-devtools-chrome-devtools` | ✓ 与 `init-and-mcp.md:82` 逐字一致 |
| **Claude 注册** | `~/.claude/settings.json` `mcp__pencil` 命中 **0**；`~/.claude/.mcp.json` **不存在**；`~/.claude.json` 唯一 `pencil` 命中是 `:2618` `"pencil-design"`（**无关技能名，不是 MCP 注册**） | 无注册 |
| **Codex 注册** | `~/.codex/config.toml:49` `[mcp_servers.pencil]` / `:50` command / `:51` `args = [ "--app", "desktop", "--agent", "codexCLI" ]` | ✓ 与 `init-and-mcp.md:23`/`:29`/`:164` 一致 |

**正面确认一条**：`init-and-mcp.md:217` 称「**DSH 侧保持与现状一致（不加 `--agent`）**」——实测受管块确实**无** `--agent`，Codex **有** `--agent codexCLI`。⇒ 交付物对两侧差异的描述准确。

**「两处注册」不是通过条件**：DSH 侧实测**只有受管块一处**，报告如实只写一处。（设计上 DSH 的注册点是受管块 + `mcp_connector.json`，但后者当前不含 pencil 条目——这属**现状**，不是缺陷。）

**边界**：本步证明「`/pencil-init` 经真实读取器加载后只读流程跑通且诊断正确」；**不**证明「下次敲一定看到同样输出」（pid / mtime / `tables` 会变）；**不**覆盖 `init-and-mcp.md` 的**写入**路径（按契约从未进入）。

**⇒ ⑤ 通过。**

### 2.6 验收 ⑥ —— 反写一次面板样式 + 备份 + 回滚

**执行**：加载 `pencil-sync`，按「反向（代码 → 设计稿）」流程逐条执行 `write-safety.md` 的**十二条规程**。

**靶点 `t65uzn`**——`组件 · P01 上下文付费面板`，`frame`，`reusable: true`，`width 390`，`fill "$yxs-surface"`，`cornerRadius [10,10,0,0]`。**爆炸半径为零**：全文档共 100 个 `ref` 节点，指向它的 **0 个**。

| 规程 | 实测 |
|---|---|
| 写前读哨兵（`document-routing.md:97-107`） | **136 命中**（`阅小识   /   YUEXIAOSHI` + `可复用组件`）⇒ 继续 |
| 备份 = `Get(<nodeIds>, {depth})` **状态快照**（**不是文件拷贝**） | `/Users/howard/Project/yuexiaoshi/.pencil-bridge/backups/2026-10-02T131239Z.json`，**5,139 B**，**15 节点**，含 `schema: pencil-bridge/backup/v1`、`propertiesToRestore.cornerRadius = [10,10,0,0]`、`rollbackPlan`、`fullSnapshot` |
| 一次面板样式反写 | `Update("t65uzn", { cornerRadius: [9,9,0,0] })`——**不带 `type`** ✓、**不传 `children`** ✓、数组整组替换 ✓ |
| 写后回读 | `cornerRadius: [9,9,0,0]`；`TYPE_UNCHANGED: yes`；`READBACK_COUNT: 15` |
| 回滚（用备份原值） | `DIFF_COUNT: 0`、`DIFFS: []`、`ID_SET_IDENTICAL: yes`，`RESTORED_SELF.cornerRadius` 回到 `[10,10,0,0]` |

**回滚是逐节点比对的**：15 个节点在 `id / name / type / depth / reusable / width / height / fill / stroke / strokeWidth / cornerRadius / layout / gap / padding` 十四项上**全部零差异**。

**磁盘独立互证（规程 11 的必要性）**：写入 + 回滚之后

```
/Users/howard/Project/yuexiaoshi/docs/yuexiaoshi.pen
  size=1194385  mtime=2026-10-01T08:38:11  inode=1104917363
```

与写入**前**逐字相同 ⇒ **写入与回滚都没有触达磁盘**。因此「收尾提示用户保存」是**必需**的，不是保守措辞。（边界：只证「返回后数秒内未落盘」，**不等于「永不落盘」**。）

**⇒ ⑥ 通过**（备份存在 ✓ / 回滚可用且已执行 ✓ / 一次 panel 样式反写完成 ✓ / 已提示保存 ✓）。

---

## 3. 仍未覆盖 / 明确不在本轮范围

1. **用户亲手键入 `/命令` 这一段**：本次六条均由 controller 经真实读取器执行（见文首说明）。**机制等价，但操作者不同**。
2. **写入的延迟落盘 / 退出时自动保存**：只证「返回后数秒内不落盘」（§2.6），**未测**何时落盘、退出时是否自动保存。
3. **`write-safety.md` 的未触发分支**：`Replace` 换 id 导致回滚不可行、`SetVariables`、`Generate`、正向模式（代码 → 设计稿的反向已测）均**未覆盖**。
4. **`assets-extraction.md` 的 `6 × 24/72 = 2` 换算**：仍标「待实证」——`width/height` 已实测（7/7 = `72`/`72`），算术成立，但 7 个样本**同一配置**，要定论需**更多不同尺寸的样本**。
5. **`init-and-mcp.md` 的写入路径**：按契约（§2.5 报告并停止）本轮从未进入。
6. **`.pencil-bridge/` 的 git 待遇**：spec 对此留白 ⇒ `yuexiaoshi` / `hanzi_write` 的 `git status` 会新增 `.pencil-bridge/`，属**预期**，不是缺陷。
7. **栈探测已知缺口（本次验收④顺带实测到，未在本轮改交付物）**：`hanzi_write` 仓库内自带 Flutter SDK 副本 `tools/flutter-sdk-3.47.5/`（已被 `.gitignore:399` 忽略、git 未跟踪），其下含**数十个** `pubspec.yaml` / `build.gradle(.kts)` / `AndroidManifest.xml`；另有 git 跟踪的 `tools/arch_guard/`（含 `pubspec.yaml`）。现有规则只排除**依赖目录**与**产物目录**，**没有**「仓库内自带的工具链 / 第三方 SDK 副本」这一类，也**没有**以 git 跟踪状态为判据 ⇒ 一次朴素递归扫描会在此项目炸出**上百个虚假栈根**。已作为**下一轮候选改进**登记，本轮未改任何交付物。

---

## 4. 相关产物与位置

| 产物 | 路径 |
|---|---|
| 验收①映射 | `/Users/howard/Project/yuexiaoshi/.pencil-bridge/design-map.yaml` |
| 验收⑥备份 | `/Users/howard/Project/yuexiaoshi/.pencil-bridge/backups/2026-10-02T131239Z.json` |
| 验收④产物目录 | `/Users/howard/Project/hanzi_write/.pencil-bridge/assets/2026-10-02T130955Z/` |
| 验收④图标清单 | 同上 `icons.json`（34 条） |
| 逐条原始读数汇总 | `.superpowers/sdd/2026-10-01-pencil-bridge-implementation/task-15-evidence.md`（Step 1–11） |
| 实施与裁定台账 | `.superpowers/sdd/2026-10-01-pencil-bridge-implementation/progress.md` |
