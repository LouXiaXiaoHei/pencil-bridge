# design-map —— 设计稿到代码的映射协议

本文是 pencil-bridge 套装里**唯一**的 design-map 参考；`/pencil-map` 负责建立它，`/pencil-sync` 的正向（设计 → 代码）与反向（代码 → 设计稿）都消费它。来源：spec §7.1–§7.4（设计规范 ':398-451'）。
**§7.1 的位置定义、§7.2 的 yaml schema、§7.3 的八步建立流程与 §7.4 的重跑语义逐字搬入，不要改写。**

三条语义先记住：

- 映射表落在**项目根**，不进技能仓库（§1）。
- 配好候选也要**用户确认后才写文件**（§3 第 6 步）。
- **重跑是常态**：原地更新，不重建文件（§4）。

---

## 1. 文件位置与项目根定义（spec §7.1 逐字搬入）

`<projectRoot>/.pencil-bridge/design-map.yaml` —— 放在**项目根**，不进技能仓库。

- 项目根 = 含 `.git` 的最近祖先；无 `.git` 则回落 cwd。
- 取 `projectRoot` 而非 cwd，因为命令可能在子目录里被调用。

---

## 2. schema（spec §7.2 逐字搬入）

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

---

## 3. 建立流程八步（spec §7.3 逐字搬入）

1. **探测项目栈**：按 `pubspec.yaml` / `build.gradle(.kts)` + `AndroidManifest.xml` / `package.json` 判定；命中多个则记为多栈。
2. **定位设计文件**：优先读 `design-map.yaml`；不存在则询问用户，或用 `get_app_state` + `~/Library/Application Support/Pen/recent-documents.json`（顶层键 `documents`，每条含 `uri` / `openedAt`）给出候选（**只读、只作建议，不作判定**）。
3. **建立哨兵**：读设计文件顶层节点名，挑选**该项目独有**的 1–3 个作为 `sentinel`。
4. **提取设计结构**：用 visitor 收集顶层 frame（`context` 属性里的设计说明一并留存）。
5. **扫描代码页面**：按栈的约定找页面入口。
6. **自动配对 + 用户确认**：先给候选配对表，**用户确认后才写文件**（对应最初需求「自动配置 + 映射，我自己确认」）。
7. **导入既有清单**：若项目已有映射清单（如 yuexiaoshi 的 `docs/design-review/manifest.json`，43 页，含 `id` / `code` / `name` / `x,y,w,h` / `screenshot`），作为**导入源**读取，**不取代**它。
8. **另一种模式**：用户**主动输入节点名与页面名**逐条建映射（对应最初需求「我自己主动输入节点名字和页面名字」）。两种模式都要支持，命令行里让用户选。

---

## 4. 重跑语义（spec §7.4 逐字搬入）

`/pencil-map` 必须可重跑：已存在的条目**原地更新**，不重建文件；用户手工添加的字段（注释、自定义键）**保留**。

---

## 5. 哨兵怎么选

`design.sentinel` 是**文档身份校验**的依据：它要能回答「眼前这份设计稿，是不是这个项目的那一份」。三条标准同时满足才合格：

1. **项目独有** —— 只在这个项目的设计稿里出现的**顶层节点名**。`"背景"` / `"Frame 1"` 这类通用名不合格；spec §7.2 的示例取的是 `"设计主题"` / `"色彩规范"`。哨兵的作用是**防窜文档**：设计稿路由会在目标文档不可达时**静默回退**到「最后聚焦的文档」，没有任何报错（**由只读探针推论**；写入路径未单独实测），哨兵是当前已知唯一能提前发现的护栏。
2. **可稳定读到** —— 必须是**顶层**节点（visitor 在 `depth === 1` 处就能收集到），且不随手改版本改名。读不到或频繁改名的哨兵会退化成「永远不匹配」，把正常会话也拦下来。
3. **数量 1–3 个** —— 一个通常已足够区分；留到 3 个是为了在某个节点改名时仍有冗余。**超过 3 个不是更安全，只是更难维护。**

哨兵的**逐字收集与比对范式**（visitor 代码块、已知基线顶层计数表）在 `../pencil-bridge/references/document-routing.md` §5 —— 本文不重复抄写，避免两处漂移。
哨兵不符 ⇒ **停机报告，不重试**；静默回退没有错误信号，重试只会把错误的写入再做一遍。

---

## 相关 reference

- `../pencil-bridge/references/document-routing.md` —— 只读哨兵范式、`filePath` 路由与静默回退、会话启动检查单
- `../pencil-bridge/references/mcp-toolbox.md` —— `execute` API 全貌、visitor 收集顶层 frame 的写法
- `../pencil-bridge/references/stack-flutter.md` / `stack-kotlin.md` / `stack-web.md` —— §3 第 1 步的栈判定与 §3 第 5 步的页面定位按栈读取对应那一份
