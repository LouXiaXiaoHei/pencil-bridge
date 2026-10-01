---
name: pencil-init
description: 检查并补齐 pencil MCP 到各 harness 的连接。当用户说「连不上 pencil」「pencil MCP 没反应」「配置一下 Pen 连接」「检查设计稿连接」时使用。默认只读诊断，任何写入前必须先询问用户。
metadata:
  version: "1.0.0"
  suite: pencil-bridge
---

# /pencil-init（Codex: $pencil-init）

## 何时使用

连不上 pencil、刚装好 Pen.app、换了机器、或想确认配置状态时。

## 先读这些

- `../pencil-bridge/references/init-and-mcp.md`（**本命令的全部细节都在这里**：逐 harness 的容器键名、前置门禁、连通性验证配方、写入铁律）
- `../pencil-bridge/references/document-routing.md`（若要顺带验证文档连通：`filePath` 路由、静默回退与哨兵）

## 输入

无参数。用户可能附带说明「只检查不修改」。

## 流程

1. **只读诊断**（默认行为，永远先做）：Pen.app 是否在跑 → MCP 二进制是否存在且可执行 → 各 harness 的注册状态 → socket 连通性。
2. **报告**：逐项给出「现状 / 判定 / 建议」，并如实标注哪些结论是「未验证」的（例如 `browser` 工具是否实际参与文档路由）。
3. **写入**：只有在用户明确要求时才进入写配置流程，且**逐条**执行 `../pencil-bridge/references/init-and-mcp.md` 的写入铁律（定点插入、不整文件重写、写前备份、幂等）。

## 输出契约

一张诊断表 + 明确结论（逐项「现状 / 判定 / 建议」）。若发现 DSH 上 pencil 已被注册（两处机制任一命中），**报告并停止**，不要写第二处。

## 铁律

- 默认只读。任何写入前必须询问。
- 探测已装 harness **不能靠 `command -v`**，只能靠配置文件是否存在。
- **绝不触碰** `dsh-skill-mcp-panel` 的受管标记块（标记块之间的内容不读、不改）。
- 若 DSH 上已注册 pencil，**报告并停止**，不写第二处。
