# init-and-mcp —— `/pencil-init` 的逐 harness 接入细节

本文是 pencil-bridge 套装里**唯一**的 harness 接入参考；`/pencil-init` 的全部行为都靠它。来源：spec §6（设计规范 ':315-396'）—— §6.1 ':317-328'、§6.2 ':329-333'、§6.3 ':334-344'、§6.4 ':345-356'、§6.5 ':357-379'、§6.6 ':380-396'。
**§6.1 / §6.5 / §6.6 的三张表逐字保留，不要改写。**
文中的字节数 / 行号 / 条目数是**实测快照，会随官方 installer、其它工具与手改而漂移**；它们只用于**识别形状**，写配置前必须按第 5 节**重新测量**。

`/pencil-init` 默认**只读诊断**，**任何写入前必须先询问用户**。

---

## 1. 定位：补齐 + 校验，不是从零配置

**补齐 + 校验**，不是从零配置。实测本机现状（spec §6.1 逐字）：

| harness | pencil 是否已配 | `--agent` |
|---|---|---|
| Codex CLI | ✅ 已有 | `codexCLI` |
| OpenCode | ✅ 已有 | `openCodeCLI` |
| VS Code | ✅ 已有 | `copilotIDE`（且用 `--app visual_studio_code`） |
| **DSH** | ⚠️ **有两份定义** | 都没有 |
| Claude Code / Claude Desktop / Gemini / Kiro / Cursor / Goose / Continue | ❌ 未配 | — |

- **Codex CLI 在 0.154.0 上已配**（实测 `~/.codex/config.toml` 有 `[mcp_servers.pencil]`），**不要盲目重写**。OpenCode（`~/.config/opencode/opencode.json` 的 `mcp.pencil`）与 VS Code（`~/Library/Application Support/Code/User/mcp.json` 的 `servers.pencil`）同理 —— 三格 ✅ 都是**已办事项**，只做校验。
- **DSH 的 ⚠️ 是「重复注册风险」而非「缺」** —— 处置见第 4 节；其余 ❌ 才是要补齐的目标。
- 逐文件的当前形状（**实测快照，写前必重测**）：

| 目标 | 容器键 | 实测形状（快照） |
|---|---|---|
| `~/.codex/config.toml` | `mcp_servers`（TOML 段） | 已有 `[mcp_servers.pencil]`，`--agent codexCLI` |
| `~/.config/opencode/opencode.json` | `mcp` | 已有 `mcp.pencil`，`--agent openCodeCLI`；**第 164 行尾部逗号** ⇒ `JSON.parse` 失败（第 7 节） |
| `~/Library/Application Support/Code/User/mcp.json` | `servers` | 已有 `servers.pencil`，含 **`type: "stdio"`**（第 6 节） |
| `~/.claude.json` | `mcpServers`（顶层 + 各 project） | 顶层 `mcpServers` 实测只有 `github` / `context7`；全文 `"mcpServers"` 出现 56 次（55 个 project + 1 顶层）。**全文 `pencil` 命中 1 处，但那是 `skillUsage."pencil-design"`，不是 MCP 条目** ⇒ Claude Code 的 pencil **未配** |
| `~/.claude/settings.json` | — | `permissions.allow` 里 **`mcp__pencil` 命中 0**，但已有 `permissions` 键 ⇒ **真缺口**（第 7.1 节） |
| `~/.cursor/mcp.json` | `mcpServers` | **已有 1 条 `claude-mem`** ⇒ 插入要**先补逗号**（非空容器） |
| `~/.kiro/settings/mcp.json` | `mcpServers` | 内容恰为 `{\n  "mcpServers": {}\n}` ⇒ **空容器** |
| `~/Library/Application Support/Claude/claude_desktop_config.json` | `mcpServers` | 同上，**空容器** |
| `~/.gemini/settings.json` | `mcpServers` | 文件非空（另有 `hooks` / `statusLine` / `experimental`），但 **`mcpServers` 当前为空容器** |
| `~/.gemini/antigravity/mcp_config.json` | `mcpServers` | **0 字节**，必须当 `{}` 处理 |
| `~/.continue/config.json` | `mcpServers` | 含 `//` 注释，严格 JSON 解析器会死（第 7 节） |
| `~/.dsh/profiles/desktop/cordis.patch.yml` | 受管块 | 受管标记 `:85`–`:120`，块内 `panel-mcp-pencil`；**只操作活动 profile**（第 4 节） |

---

## 2. 前置硬门禁（spec §6.2 逐字）

1. **Pen.app 必须在运行**。判据：`pgrep -f "/Applications/Pen.app/Contents/MacOS/Pen"` 有输出。不在跑 → 握手必然挂起，**先让用户启动，不要重试**。
2. **二进制必须存在且可执行**：`fs.accessSync(bin, X_OK)`。`bin` 的实际取值（spec §3.1 ':37'）：
   `/Applications/Pen.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-arm64`。
   另一份独立副本（VS Code 集成用，连的是 `--app visual_studio_code`，spec ':39'）：`~/.pencil/mcp/visual_studio_code/out/mcp-server-darwin-arm64`。
   不存在时按 `getMcpBinaryName()` 的架构矩阵算出**应然文件名**再报错。

- **`getMcpBinaryName()` 架构矩阵**：`-darwin-arm64` / `-darwin-x64` / `-linux-arm64` / `-linux-x64` / `-windows-x64.exe`。本机 Pen.app **只提供 `-darwin-arm64` 一份**（全 app `find` 确认）；Intel Mac 会缺文件。
- ⚠️ 门禁用的是 `pgrep -f` 的**路径判据**，与二进制体积无关：启动器 `/Applications/Pen.app/Contents/MacOS/Pen` 与真正的 MCP server 二进制是**两个不同产物**，**不要拿体积当判据**。
- `--app <name>` 决定 socket 名；探测时用的 `--app` 必须与配置文件里的一致（VS Code 用 `visual_studio_code`，其余默认 `desktop`）。

---

## 3. 连通性验证配方（spec §6.3 已实测跑通）

spawn 目标 `command + args`，依次发 `initialize` / `notifications/initialized` / `tools/list`：

- **成功判据**：`result.serverInfo.name === "pencil"`，且 `tools/list` 返回 **5** 个工具（`browser` / `execute` / `get_app_state` / `get_style` / `read_skill`，工具面见 `../pencil-bridge/references/mcp-toolbox.md`）。
- **最强信号**：stderr 出现

  ```
  [TransportClient] connected to ~/.pencil/socket/pencil-desktop.sock
  ```

  （日志原文里是展开后的主目录绝对路径；**本文档一律写成 `~` 开头的形态** —— 见第 5 节末尾的绝对路径禁令。socket 名由 `--app` 决定。）
- **失败分流**：
  - stderr 无 `connected to …` → Pen.app 没跑，或 `--app <name>` 指向不存在的实例。
  - `command` ENOENT → 架构不匹配，或 Pen 未装在 `/Applications`。
  - 握手成功但 harness 里看不到工具 → **未重启 harness**（见第 8 节）。

---

## 4. DSH 特例（重复注册风险）（spec §6.4）

DSH 上有**两套并行机制**，pencil 可能同时存在两处：

- `~/.dsh/profiles/desktop/cordis.patch.yml` 受管块内的 `panel-mcp-pencil`。
- `~/.dsh/storages/mcp_connector.json` 的 `tables.connections."json-pencil"`（实测：**该键当前不在 `tables.connections` 里** —— 该表实测只有 `chrome-devtools-chrome-devtools`；`json-pencil` 只出现在 `tables.snapshots` 的历史快照中 ⇒ **不能只靠 grep 全文件判定在线注册**）。
- 两者 `serverName` 都是 `pencil`，argv 也相同 → 实测只起了一个进程，**无法从 argv 区分来源**。

**`/pencil-init` 第 0 步必须两处都查 `pencil`**：

1. 读 `cordis.patch.yml`，查 `serverName: pencil`（受管标记内外都要看）。
2. 解析 `mcp_connector.json`，**只看 `tables.connections` 的实际键**（不要只 grep 全文件 —— `tables.snapshots` 会给出假阳性）。
3. 任一命中就**不写第二处**；两处都有则让用户**选一处**保留。

### 4.1 硬约束（必须逐条守住）

- **绝不修改** `# >>> dsh-skill-mcp-panel:mcp:begin` 与 `# <<< …:end` 之间的内容 —— 面板重写会**静默抹掉**块内手写内容。若必须新增，在**标记之外**追加独立的 `- insert:` 条目（形态参考 `~/.dsh/profiles/tauri/cordis.patch.yml` 里的手写 `- id: mcp-pencil`）。
- **只操作活动 profile**（实测即 `~/.dsh/profiles/desktop`）；`~/.dsh/profiles/tauri` 与 `~/.dsh/recovery/*` 的多份快照**不得**顺手改。
- `cordis.yml`（合成产物）**不要手改**。
- `mcp_connector.json` 是**数百 KB 的版本化领域存储**（含快照 / scope 绑定）—— **建议交给 GUI 或插件 API，不手写**。
- 生效：受管块走面板 = **热加载**；手改文件 = 保守起见提示用户**重启 DSH 网关**。

---

## 5. 写入铁律（spec §6.5）

- **禁止整文件序列化写回**。Pen.app 官方 installer 就是这么干的（`smol-toml` 重序列化 TOML、`JSON.stringify(obj,null,2)` 重写整个 `~/.claude.json`），会**丢掉 `~/.codex/config.toml` 的全部注释与键序**、把 `~/.claude.json`（含 55 个项目状态）**整体重排**。**本设计不复刻该行为。**
- 实现方式：**文本级定点定位容器**，在容器起始 `{` 后插入渲染好的片段，缩进**逐字对齐该文件现有条目**。
- **插入前必须重新测量**：这些文件是活状态，本稿的字节数与行号只是快照。先读文件，**现算**容器位置与**该文件现有的缩进**，再做定点插入；实测与描述不符时，**按实测执行**。

### 5.1 容器插入的三种状态（必须分别处理）

1. **空容器** —— `<key>: {}`。实测 `~/.kiro/settings/mcp.json` 与 `~/Library/Application Support/Claude/claude_desktop_config.json` 的内容恰为 `{\n  "mcpServers": {}\n}`：把 `{}` 展开为含新条目的块，**不得**产生 `{,}` 或多余逗号。
2. **非空容器** —— 实测 `~/.cursor/mcp.json` 的 `mcpServers` 已有 1 条 `claude-mem`：插入前**先补逗号**，缩进对齐现有条目。（`~/.gemini/settings.json` 文件非空、但 `mcpServers` 为空 ⇒ 按第 1 种处理。）
3. **容器缺失** —— **创建容器键**再放条目；`~/.gemini/antigravity/mcp_config.json` 是 **0 字节**，先当 `{}`（第 7 节）。

### 5.2 绝对路径禁令

本套装**禁止在交付文本里出现主目录 / 系统绝对路径**（仓库克隆到别处即失效，`bin/check` 会直接判 FAIL）。凡引用真实路径一律写 `~` 开头的形态；需要提 codex 时只写 `codex CLI 0.154.0`，**不写安装路径**。唯一的例外是 Pen.app 自身的位置（`/Applications/Pen.app/…` 与 `pgrep -f` 的那条命令），它不随克隆位置变化。

---

## 6. 容器键名四种形态表（spec §6.5 逐字）

容器键名有四种形态，**不能写错**：

| 形态 | 用于 |
|---|---|
| `mcpServers` | Claude Code / Claude Desktop / Gemini / Kiro / Cursor / Windsurf |
| `servers` | **VS Code**（`~/Library/Application Support/Code/User/mcp.json`） |
| `mcp` | **OpenCode**（`command` 是 `[exe, ...args]` 数组，`type: "local"`，`enabled: true`） |
| `mcp_servers` | **Codex**（TOML 段） |

**逐种子形态的条目字段**（写错字段名同样不生效）：

- **OpenCode（`mcp`）**：`command` 是 **`[exe, ...args]` 数组**（不是字符串），另有 `type: "local"`、`enabled: true`。实测形态：

  ```json
  "pencil": {
    "command": [
      "/Applications/Pen.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-arm64",
      "--app",
      "desktop",
      "--agent",
      "openCodeCLI"
    ],
    "enabled": true,
    "type": "local"
  }
  ```

- **VS Code（`servers`）**：条目是 `command`（**字符串**）+ `args` + `env` + **`type: "stdio"`**。spec §6.5 的表只给了 `servers` 键名、**漏了这个 `type` 字段**（同表 OpenCode 那格却写了 `type: "local"`）⇒ **必须补齐 `type: "stdio"`**，与 OpenCode 的 `type: "local"` 形成对称。实测形态（`command` 的值按实测形状写成 `~` 形态；写前重测）：

  ```json
  "pencil": {
    "command": "~/.pencil/mcp/visual_studio_code/out/mcp-server-darwin-arm64",
    "args": ["--app", "visual_studio_code", "--agent", "copilotIDE"],
    "env": {},
    "type": "stdio"
  }
  ```

- **Codex（`mcp_servers`，TOML 段）**：`command = "…"`（字符串）+ `args = [ … ]`。实测形态：

  ```toml
  [mcp_servers.pencil]
  command = "/Applications/Pen.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-arm64"
  args = [ "--app", "desktop", "--agent", "codexCLI" ]
  ```

- **`mcpServers`（JSON 对象）**：`command`（字符串，VS Code 外的 harness 均如此）+ `args` + 可选 `env`。

---

## 7. 三个会毒死严格解析器的文件（spec §6.5）

写之前必须先分类；直接 `JSON.parse` / TOML 反序列化会死在这三个文件上：

- **`~/.config/opencode/opencode.json`** —— 第 **164** 行有**尾部逗号**，`JSON.parse` **直接失败**。本机 **Node v26.8.2** 实测报错原文：

  ```
  Expected double-quoted property name in JSON at position 3324 (line 164 column 3)
  ```

  **措辞随解析器 / V8 版本而异**（旧版 V8 的文案是 `Expecting property name enclosed in double quotes`）；**承重的分类事实是「`JSON.parse` 直接失败、并指向第 164 行的尾部逗号」，行号 164 不变。** ⇒ 不能靠 parse→改→序列化，必须走文本级定点插入（第 5 节）。
- **`~/.continue/config.json`** —— 含 `//` 注释与非法内容，**不是合法 JSON**（实测 `Unexpected token '/'`）⇒ 只能文本级定位；且**绝不触碰 `models[]`**（含明文 API key，见 `../pencil-bridge/references/write-safety.md` 的凭据禁读清单）。
- **`~/.gemini/antigravity/mcp_config.json`** —— **0 字节**，必须当 `{}` 处理（按空对象创建 `mcpServers`）。

### 7.1 Claude Code 要写两处

- `~/.claude.json` 的**连接定义**；
- **加上** `~/.claude/settings.json` 的 `permissions.allow` 必须含字符串 `"mcp__pencil"`（**去重**），否则工具不生效。
- 实测 `~/.claude/settings.json` 当前 **`mcp__pencil` 命中 0**、但已有 `permissions` 键 ⇒ 这是**真缺口**，不是已办事项。
- ⚠️ `~/.claude/settings.json` 的 `env` 段含 ANTHROPIC 密钥 —— **禁读**（`../pencil-bridge/references/write-safety.md`）。

### 7.2 原子性、备份与幂等

- **写入原子性**：同目录 temp + `rename` + 锁文件。
- **写前备份**：`<file>.pencil-init.bak.<ISO8601>`，**同一次运行内不覆盖已有备份**。
- **幂等**：键名固定 `pencil`；按「**容器键 + 名字**」定位，已存在则**只更新该条目的键**。

---

## 8. 探测与生效（spec §6.6）

- **探测已装 harness 不能靠 `command -v`** —— 本机 `dsh` / `claude` / `codex` / `opencode` / `gemini` / `cursor-agent` **全部找不到**（皆 GUI 形态，不在 PATH）。只能靠**配置文件是否存在**来判定。
- 生效条件（**除 DSH 外均为「未验证」**，文案中必须如实标注）：

| harness | 生效条件 | 验证状态 |
|---|---|---|
| DSH | 插件受管块热加载；手改文件则重启网关 | **受管块热加载：已实测**；手改文件重启网关：**未实测** |
| Codex CLI | 重开 codex 会话 | **未验证** |
| Claude Code CLI | 新会话（`/mcp` 可查状态） | **未验证** |
| OpenCode | 重开 opencode | **未验证** |
| Claude Desktop | **完全退出并重启** | **未验证** |
| Gemini / Antigravity / Kiro | 新会话 | **未验证** |
| Cursor / VS Code / Windsurf | 重启编辑器或 reload window | **未验证** |
| Goose / Continue | 重启对应进程 | **未验证** |

- **`--agent` 值**按 harness 填（自由文本、零校验）：`claudeCodeCLI` / `codexCLI` / `openCodeCLI` / `copilotIDE` / `geminiCLI`。**DSH 侧保持与现状一致（不加 `--agent`）**。
- 「握手成功但 harness 里看不到工具」⇒ 先按本表让用户重启对应 harness，再复测（第 3 节的第三种失败分流）。

---

## 相关 reference

- `../pencil-bridge/references/document-routing.md` —— `filePath` 路由、静默回退、哨兵、会话启动检查单
- `../pencil-bridge/references/mcp-toolbox.md` —— 5 个工具、`execute` API 全貌、CLI 参数形态
- `../pencil-bridge/references/write-safety.md` —— 写操作安全规程、凭据禁读清单
