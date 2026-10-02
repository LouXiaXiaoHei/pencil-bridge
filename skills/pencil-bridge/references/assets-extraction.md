# assets-extraction —— 四类素材的取法与坑

本文是 pencil-bridge 套装里**唯一**的素材提取参考；`/pencil-assets` 的全部行为都靠它。来源：spec §9（设计规范 ':476-504'，含 §9.1 ':487-490' / §9.2 ':491-496' / §9.3 ':497-504'），位图与矢量的字段细节取自 §3.3 节点模型（':125-147'）。
**§9 的四类产物表与 §9.1–§9.3 逐字搬入，不要改写；第 3 节的 `strokeWidth` 换算规则是「待实证」，不得当定论用。** 本文里的 `§N` 指**本文的小节**；spec 的章节一律写成 `spec §N`。

四类产物（位图 / 矢量 / 图标引用 / 变量 token）各有各的取法，先记住三条边界：

- 位图**直接拷磁盘文件**，不走 MCP 字节流（§2）。
- 矢量的 `viewBox` 与 `strokeWidth` 都有坑，换算规则**待实证**（§3）。
- `icon` 节点**取不到矢量源码**，只出「库名 + 图标名」引用（§6）。

---

## 1. 四类产物的取法表（spec §9 逐字搬入）

四类产物（用户裁决：四类全要）：

| 类别 | 取法 | 关键约束 |
|---|---|---|
| **位图** | image fill 的 `url` → 相对 `.pen` 目录解析成绝对路径 → 直接拷磁盘文件 | 不需要 MCP 传字节；保留原扩展名 |
| **矢量** | `path` 节点 + `includePathGeometry: true` 取 `geometry` / `viewBox` / `fill` / `stroke` / `strokeWidth` / `strokeLinecap` / `strokeLinejoin` | **`includePathGeometry: true`** 决定 `geometry` 是否返回真实路径串（不带时为字面量 `"..."`，静默不报错）；`viewBox` **始终返回**；`strokeWidth` 需按 viewBox 比例换算（**待实证**）；`fill:"#00000000"` → `fill="none"`；`stroke` 是变量引用时的落法见下 |
| **图标引用** | `icon` 节点的 `library` + `icon` 名 | **取不到 SVG 源码**，只出「用 lucide 的 `book-open`」这类引用；按栈写成对应库的调用 |
| **变量 token** | `Print(GetVariables())` | 出三栈格式见 §9.2；支持多维 themes |

四行往下展开：位图的解析见 §2；矢量的字段与坑见 §3，其中变量引用的落法见 §4；三栈 token 格式见 §5；图标引用与两条提取边界见 §6；产物落地见 §7。

---

## 2. 位图的路径解析（spec §3.3）

- **没有 `image` 节点类型**。图片是**节点上的 image fill**：`{ type: "image", url, mode: "cover"|"contain"|"stretch" }`。注意 `fill` **是数组字段**，上面是其中**一个元素**的形态；取用时按首元素处理（见 `../pencil-bridge/references/write-safety.md` 的写语义表）。
- **image fill 的 `url` 是相对 `.pen` 所在目录的磁盘相对路径**，原文件真实存在；`.pen` 内无 base64、无 http 外链。
- → **位图素材可以直接拷磁盘文件，不需要 MCP 传字节。**

解析步骤：

1. 取出 image fill 的 `url` —— 它是磁盘相对路径，不是 URL。
2. 把它拼到 `.pen` 文件所在目录上，得到绝对路径。
3. **直接拷该磁盘文件**到产物目录（§7）；不走 `Export`，也不需要 MCP 传字节。
4. **保留原扩展名**：`.png` 拷出来仍是 `.png`，不转码、不改名。

- 例：`assets/hanzi-design-v1/bg_character_of_day.png` → `<pen目录>/assets/hanzi-design-v1/bg_character_of_day.png`（1,679,293 B 真实 PNG）。

---

## 3. 矢量的字段与坑（spec §3.3）

- **`path` 节点**关键字段：`geometry`（SVG path 串）、`viewBox`（**节点上的显式字段，数组形式如 `[0,0,24,24]`**）、`fillRule`、`fill`、`stroke`、`strokeWidth`、`strokeLinecap`、`strokeLinejoin`。
- 以下样本取自 `hanzi_write.pen` 的 `E5QUX` 子树（「25 · 图标规范 / 还差 12 枚」），其类型直方图为 `{frame:60, text:18, icon:34, path:7}` —— 即 7 个真矢量 `path`（§14 验收标准第 4 条引用此处）。

三个坑：

1. **`includePathGeometry: true` 决定 `geometry` 是否返回真实路径串**（此前的「由 width/height 推导」是错的）。**不带这个 option（或传 `false`）时，`geometry` 仍然会返回，但内容是字面量 `"..."`** —— **静默、不报错**，极易被当成路径串写出坏 SVG。
   **`viewBox` 与该 option 无关，三档都返回**（实测恒为 `[0,0,24,24]`）。
2. `fill: "#00000000"` 是**全透明**，导出时应落成 `fill="none"`。
   不要原样写进 SVG，那会变成不透明黑而不是「无填充」。
3. **`strokeWidth` 是节点像素坐标下的值**，不能直接写进 viewBox 坐标系。实测样本 `width:72, height:72, viewBox:[0,0,24,24], strokeWidth:6`；按 `6 × 24/72 = 2` 换算恰好是 lucide 标准描边。**此换算规则标为待实证，不得当定论写进实现。**
   比例换算只是当前样本上的候选解释，未在更多样本上验证。

`stroke` / `fill` 是变量引用时（如 `"$ink"`）的落法见 §4。

---

## 4. 变量引用的落法（spec §9.1 逐字搬入）

`stroke` / `fill` 可能是变量引用（如 `"$ink"`）。**默认落成 `stroke="currentColor"`**，让代码侧用 CSS/主题控制；提供开关可强制 resolve 成实际色值（`{resolveVariables:true}` 取计算值）。**此默认值是待用户最终确认的实现细节，实现时以开关形式暴露，不写死。**

- **默认**：变量引用 → `currentColor`，颜色交给代码侧的主题控制。
- **开关**：`{resolveVariables:true}` 在 `Get` 时取计算值，落成变量定义里的实际色值。
- **不要把默认值写死**：以实现时的开关形式暴露，等用户最终确认。

---

## 5. 三栈 token 输出格式（spec §9.2 逐字搬入）

- **web**：CSS 自定义属性文件（`:root { --yxs-primary: …; }`），多维主题按 `[data-theme]` / `prefers-color-scheme` 分组。
- **flutter**：Dart 常量类（`class YxsTokens { static const primary = Color(0x…); }`）。
- **kotlin**：`colors.xml`（+ 需要时 `dimens.xml` / `styles.xml`）。

变量本身由 `Print(GetVariables())` 读出，返回 `{ variables, themes? }`；`themes` 可以是多维的（如 `{"mode":["light","dark"], "locale":["zh","en"]}`），多维主题在 web 侧就按上面两种分组展开。变量读写的完整规程见 `../pencil-bridge/references/write-safety.md`。

---

## 6. 提取边界（spec §9.3 逐字搬入）

- **不导出 `icon` 节点的矢量**（Pen.app 不提供源码，`Export` 无 svg 格式）。
- **不导出 html-tailwind / html-css**（`Export` 支持，但那是整页重建，属于 `pencil-design` 那类技能的领域，不是本项目的「提取素材」）。
- 产物落地目录：`<projectRoot>/.pencil-bridge/assets/<timestamp>/`，并在摘要里列出每个文件的来源节点 id。

两条边界的理由：

- **`icon` 节点**只有：`library`（lucide | feather | Material Symbols Outlined/Rounded/Sharp | phosphor）、`icon`（名字）、`weight`、`fill`。**没有 geometry、没有 SVG 源码。**
- 所以 `Export` 的格式列表里**没有 svg**，本机 Pen.app 也未打包任何图标字体/SVG 资源（spec §3.3）⇒ **图标只能产出「库名 + 图标名」引用，取不到矢量源码。**

---

## 7. 产物落地

- 目录：`<projectRoot>/.pencil-bridge/assets/<timestamp>/`。
- **摘要里列出每个文件的来源节点 id** —— 让用户能对上「这份素材来自画布上哪个节点」。
- 位图按 §2 拷贝，矢量按 §3 导出，token 按 §5 的三栈格式写出。

`Export` 的签名与选项对象在 `../pencil-bridge/references/mcp-toolbox.md`；素材写入要遵守的 `Generate` asset url 规程在 `../pencil-bridge/references/write-safety.md`（spec §11 规程 8）。

---

## 相关 reference

- `../pencil-bridge/references/mcp-toolbox.md` —— `Get` / `Export` 的完整签名、`GetVariables` / `includePathGeometry` 等选项对象、visitor 写法
- `../pencil-bridge/references/write-safety.md` —— `Generate` 的 asset url 必须在同一个 `execute` 内 `Update` 到 fill（§11 规程 8），以及素材写入相关的安全规程
- `../pencil-bridge/references/document-routing.md` —— `filePath` 必须传绝对 `file://` URI、静默回退与会话启动检查单（素材提取同样受它约束）
