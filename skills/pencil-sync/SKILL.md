---
name: pencil-sync
description: 按设计稿修改项目页面的样式（正向），或把代码里的样式改动反写回设计稿（反向）。当用户说「按设计改样式」「设计稿更新了同步一下」「把这个颜色写回设计稿」「反写」时使用。
metadata:
  version: "1.0.0"
  suite: pencil-bridge
---

# /pencil-sync（Codex: $pencil-sync）

## 何时使用

设计稿更新了要按设计改代码样式（正向），或代码里的样式改动要写回设计稿（反向）时。

## 先读这些

- `../pencil-bridge/references/write-safety.md`（**写入必读**，反向模式逐条执行：十二条写安全规程、备份 / 幂等 / 凭据禁读）
- `../pencil-bridge/references/design-map.md`（`.pencil-bridge/design-map.yaml` 协议：页面与节点 id 的对应关系）
- `../pencil-bridge/references/document-routing.md`（会话启动检查单、哨兵范式、`filePath` 路由与静默回退）
- 与探测到的栈对应的那一份分栈 reference（**按探测到的栈只读对应那一份**）：`../pencil-bridge/references/stack-flutter.md` / `../pencil-bridge/references/stack-kotlin.md` / `../pencil-bridge/references/stack-web.md`

## 输入

方向（正向 / 反向）+ 页面或节点范围（可省略，省略则按 `design-map.yaml` 的全部条目）。反向模式还需指明要写回的样式在代码里的位置。

## 流程

**正向（设计 → 代码）**

1. **校验文档身份**：跑会话启动检查单与哨兵，确认连的是 `design-map.yaml` 里 `design.file` 指定的那份 `.pen`。
2. **拉节点树**：`Get(<id>, {depth, resolveVariables: true})`，按 `design-map.yaml` 的页面条目取对应节点。
3. **产出差异清单**：设计值 vs 代码现值。
4. **直接改，改完给 diff 摘要** —— **不做**「事前确认清单」（这一点与 `/pencil-map` 的确认策略不同）。
5. **范围**限颜色 / 间距 / 圆角 / 字号 / 字重 / 布局方向；**不改结构、不改文案**。

**反向（代码 → 设计稿）**

1. **逐条**执行 `../pencil-bridge/references/write-safety.md` 的写安全规程。
2. 用**节点 id** 定位目标节点，**不用名字**。
3. **写后回读**校验。
4. 收尾**提示用户保存**（写操作是否立即落盘未证实）。
5. 回滚不可行时（如 id 已被 `Replace` 改变）**如实报告**，不静默尝试。

## 输出契约

- 正向：**改动文件清单 + diff 摘要**。
- 反向：**备份文件路径 + 回读结果**；回滚不可行时明确说明。

## 铁律

- 正向**不做事前确认清单**；反向**逐条走 write-safety**。
- 写前必读哨兵，哨兵不符 ⇒ 停机报告，不重试。
- **`Update` 绝不带 `type`、不传 `children`**；`SetVariables` 禁止 `replace: true`。
- 反向定位**只看节点 id**，不靠名字。
- 不假设写操作已落盘 —— 收尾必须提示用户保存。
