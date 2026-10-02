# pencil-bridge

## 这是什么

一句话：让 AI harness（DSH / Claude Code / Codex CLI）通过 pencil MCP 连接到 Pen.app 中**指定的 `.pen` 文件与节点**，按设计改代码样式、从设计提取素材、以及把代码里的样式改动反写回设计稿。

交付物是**四条命令 + 一个主知识 bundle**，放在公共位置，供三个 harness 共用。

| 命令 | Codex 写法 | 职责 | 默认方向 |
|---|---|---|---|
| `/pencil-init` | `$pencil-init` | 环境自检：Pen.app 是否在跑、MCP 二进制是否存在、各 harness 的 MCP 注册状态、socket 连通性 | 只读诊断；写入前必须询问 |
| `/pencil-map` | `$pencil-map` | 建立 / 更新 `.pencil-bridge/design-map.yaml` | 设计 → 映射表 |
| `/pencil-sync` | `$pencil-sync` | 按设计改代码样式；**反向模式**改设计稿 | 双向 |
| `/pencil-assets` | `$pencil-assets` | 抽取四类素材 | 设计 → 文件 |

`/pencil-bridge`（主 bundle）同样可调用，作为总控与诊断入口：它解释整体模型、给出当前该用哪条命令的建议，并在用户未指明时做栈探测。

## 安装

```bash
git clone <repo-url> ~/Project/pencil-bridge
~/Project/pencil-bridge/bin/link
```

`bin/link` 会把仓库内的五个技能扇出到三个 harness 的技能根（DSH 与 Claude Code 走目录软链，Codex 走复制），脚本幂等，可重复执行；先用 `--dry-run` 预览。扇出后**重启或新开一个 harness 会话**，技能菜单才会刷新。

## 四条命令怎么用

- `/pencil-init` —— 说「连不上 pencil」「检查设计稿连接」。
- `/pencil-map` —— 说「建映射」「关联设计稿和页面」「这个页面在哪个设计稿里」。
- `/pencil-sync` —— 说「按设计改样式」「设计稿更新了同步一下」；反向说「把这个颜色写回设计稿」。
- `/pencil-assets` —— 说「导出图标」「提取素材」「把设计变量导出成 CSS/Dart/colors.xml」。

**Codex 的写法不同**：Codex CLI 用 **`$`** 而不是 `/`，即 `$pencil-init`、`$pencil-map`、`$pencil-sync`、`$pencil-assets`。技能内容三处完全相同，仅调用前缀不同。

## 前置条件

- **Pen.app 必须正在运行** —— MCP 通过 app 的内存模型读写设计稿，app 不在跑就没有可连的目标。
- **目标 `.pen` 必须已在 Pen.app 中打开**。未打开时，pencil MCP 会**静默回退到「最后聚焦的文档」，不报任何错** —— 也就是说你可能在**改错文档而不自知**。所以每条命令都先用哨兵校验文档身份，再动手。

## 安全边界

- **默认只读**：`/pencil-init` 是只读诊断，任何写入之前必须先询问用户。
- **反写有补偿备份**：`.pen` 不受版本控制兜底（`*.pen` 在全局 gitignore 里），所以反向同步（代码 → 设计稿）在写入前必须自建补偿备份。
- **不读凭据文件**：任何流程都显式跳过 `~/.pencil/session-desktop.json`、`~/.pencil/agent-auth`、`~/.dsh/.credentials.yaml`、`~/.claude/.credentials.json` 等凭据文件，且绝不写进日志或产物。完整的七条禁读清单见 `skills/pencil-bridge/references/write-safety.md` 的凭据禁读一节。
