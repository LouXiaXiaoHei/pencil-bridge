# pencil-bridge

[English](README.en.md) | **中文**

让 AI harness（DSH / Claude Code / Codex CLI）通过 **pencil MCP** 连接到 Pen.app 中**指定的 `.pen` 文件与节点**，按设计改代码样式、从设计提取素材、以及把代码里的样式改动反写回设计稿。

## 它解决什么问题

设计稿和代码是两份会各自漂移的东西。设计师在 Pen.app 里调了一个间距、换了一个图标、加了一个颜色 token，代码侧通常只能靠人肉对照截图去追。反过来，代码里改了样式，设计稿也慢慢跟真实界面脱节。

pencil-bridge 把这条链路交给 harness 去做，但要解决三个真问题：

1. **改对文档**。pencil MCP 在目标 `.pen` 未打开时会**静默回退到「最后聚焦的文档」，不报任何错** —— 你可能在改错文档而不自知。所以每条命令都先用**哨兵**校验文档身份，不符即停机。
2. **定位到节点**。设计稿里同名节点遍地都是，靠名字匹配不可靠。映射表里存的是**节点 id**。
3. **写坏了能回滚**。`.pen` 不在版本控制里（`*.pen` 通常被 gitignore），所以任何反向写入（代码 → 设计稿）之前必须自建补偿备份。

## 交付物

四条命令 + 一个主知识 bundle，放在公共位置供三个 harness 共用。

| 命令 | Codex 写法 | 职责 | 默认方向 |
|---|---|---|---|
| `/pencil-init` | `$pencil-init` | 环境自检：Pen.app 是否在跑、MCP 二进制是否存在、各 harness 的 MCP 注册状态、socket 连通性 | 只读诊断；写入前必须询问 |
| `/pencil-map` | `$pencil-map` | 建立 / 更新 `.pencil-bridge/design-map.yaml` | 设计 → 映射表 |
| `/pencil-sync` | `$pencil-sync` | 按设计改代码样式；**反向模式**改设计稿 | 双向 |
| `/pencil-assets` | `$pencil-assets` | 抽取四类素材：位图、矢量 `path`、图标引用、设计变量 token | 设计 → 文件 |

`pencil-bridge`（主 bundle）同样可调用，作为总控与诊断入口：它解释整体模型、给出当前该用哪条命令的建议，并在用户未指明时做栈探测。

## 安装

```bash
git clone https://github.com/LouXiaXiaoHei/pencil-bridge.git ~/Project/pencil-bridge
~/Project/pencil-bridge/bin/link
```

`bin/link` 把仓库内的五个技能扇出到三个 harness 的技能根：

| harness | 技能根 | 方式 |
|---|---|---|
| DSH | `~/.agents/skills/` | 目录软链 |
| Claude Code | `~/.claude/skills/` | 目录软链 |
| Codex CLI | `~/.codex/skills/` | 复制（是否跟随软链**未证实**，不赌） |

脚本幂等，可重复执行；先用 `--dry-run` 预览，或用 `--only agents|claude|codex` 只处理一根。

> 软链的两根会自动跟随仓库改动；**Codex 那根是副本，仓库更新后要重跑 `bin/link --only codex`**，否则技能内容会停在旧版本。

扇出后**重启或新开一个 harness 会话**，技能菜单才会刷新。

## 四条命令怎么用

- `/pencil-init` —— 说「连不上 pencil」「pencil MCP 没反应」「检查设计稿连接」。
- `/pencil-map` —— 说「建映射」「关联设计稿和页面」「这个页面在哪个设计稿里」。
- `/pencil-sync` —— 说「按设计改样式」「设计稿更新了同步一下」；反向说「把这个颜色写回设计稿」。
- `/pencil-assets` —— 说「导出图标」「提取素材」「把设计变量导出成 CSS/Dart/colors.xml」。

**Codex 的写法不同**：Codex CLI 用 **`$`** 而不是 `/`，即 `$pencil-init`、`$pencil-map`、`$pencil-sync`、`$pencil-assets`。技能内容三处完全相同，仅调用前缀不同。

## 支持的技术栈

栈探测覆盖三类，可识别**单仓多栈**（映射表里 `stacks` 是一个列表）：

- **Flutter** —— `pubspec.yaml`
- **Android / Kotlin** —— `build.gradle(.kts)` + `AndroidManifest.xml`
- **Web** —— `package.json` 及构建器配置（Vite / Next.js / Nuxt 等）

探测会**排除**：依赖目录（`node_modules/`、`.dart_tool/`、`Pods/`）、产物目录（`build/`、`dist/`、`.next/` 等）、宿主壳目录（Flutter 的 `android/`、`ios/`、`macos/`、`linux/`、`windows/`、`web/` 属父栈，不算独立栈），以及**仓库内自带的工具链 / 第三方 SDK 副本**（如 `tools/<sdk>/`）。

## 前置条件

- **Pen.app 必须正在运行** —— MCP 通过 app 的内存模型读写设计稿，app 不在跑就没有可连的目标。
- **目标 `.pen` 必须已在 Pen.app 中打开**。未打开时 MCP 会静默回退到「最后聚焦的文档」（见上文「改对文档」）。
- pencil MCP 需已注册进对应 harness。跑 `/pencil-init` 可以只读诊断这一项。

## 安全边界

- **默认只读**：`/pencil-init` 是只读诊断，任何写入之前必须先询问用户。
- **反写有补偿备份**：反向同步（代码 → 设计稿）在写入前先 `Get` 出目标子树存到 `.pencil-bridge/backups/<ISO8601>.json`，并附回滚指令；写入后逐节点比对验证。
- **哨兵不符即停机**，不重试。
- **不读凭据文件**：任何流程都显式跳过 `~/.pencil/session-desktop.json`、`~/.pencil/agent-auth`、`~/.dsh/.credentials.yaml`、`~/.claude/.credentials.json` 等凭据文件，且绝不写进日志或产物。完整的七条禁读清单见 [`skills/pencil-bridge/references/write-safety.md`](skills/pencil-bridge/references/write-safety.md) 的凭据禁读一节。
- **写操作不会立即落盘**：`execute` 写入在返回后数秒内不落盘，需要用户在 Pen.app 里保存。命令收尾会提示。

## 仓库结构

```
bin/
  link            把五个技能扇出到三个 harness 技能根
  check           校验技能包（frontmatter 合法、reference 齐全、无绝对路径、无悬空引用）
skills/
  pencil-bridge/  主 bundle：总控 + 9 份 reference
    references/   mcp-toolbox / document-routing / write-safety / design-map /
                  assets-extraction / init-and-mcp / stack-{flutter,kotlin,web}
  pencil-init/    薄壳，指回主 bundle
  pencil-map/     薄壳
  pencil-sync/    薄壳
  pencil-assets/  薄壳
tests/
  check.test.sh   bin/check 的测试（25 项）
  link.test.sh    bin/link 的测试（56 项，隔离 HOME）
docs/
  reference/      pencil MCP 写入 API 手册、验收记录
  superpowers/    设计规格与实施计划
```

## 开发

```bash
bin/check                 # 校验技能包，失败返回非 0
tests/check.test.sh       # bin/check 的测试
tests/link.test.sh        # bin/link 的测试（隔离 HOME，不碰真实技能根）
```

改完技能后重跑 `bin/check`；如果改了 `skills/` 下的内容，记得 `bin/link --only codex` 刷新副本。

**注意**：主 bundle 里有同一句栈探测判据重复出现在三份分栈 reference 中（`stack-flutter.md` / `stack-kotlin.md` / `stack-web.md`），改措辞时需三处同步。

## 文档

- [设计规格](docs/superpowers/specs/2026-10-01-pencil-bridge-design.md) —— 完整设计决策与约束
- [实施计划](docs/superpowers/plans/2026-10-01-pencil-bridge-implementation.md) —— 15 个任务的实施过程
- [pencil 写入 API 手册](docs/reference/pencil-write-api-manual.md) —— 实测整理的 MCP `execute` API 行为
- [验收记录](docs/reference/acceptance-2026-10-01.md) —— 六条验收标准的实测结果与未覆盖项

## 许可

尚未添加许可证文件。在添加之前，本仓库默认保留全部权利。
