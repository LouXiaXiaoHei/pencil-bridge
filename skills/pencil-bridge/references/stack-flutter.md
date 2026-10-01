# stack-flutter —— Flutter 栈的项目识别、页面定位与 token 落点

本文是 pencil-bridge 套装里 Flutter 栈的**唯一**分栈参考；`/pencil-map`（建映射）与 `/pencil-assets`（出 token）探测到 `pubspec.yaml` 时按需加载它，`/pencil-sync` 沿用它定「样式改哪里」。来源：spec §12（分栈清单）与 §9.2（三栈 token 输出格式）。
本文里的 `§N` 指本文小节号，`spec §N` 指设计规范章节号。

先记住四条：

- 识别靠 `pubspec.yaml`，**不是**靠目录名（§1）。
- 页面目录**随项目而异**；可靠的 selector 锚点是页面类名串（`class XxxPage` / `class XxxView` / `class XxxScreen`，后缀随项目而异）（§2）。
- 样式先落到 token 常量类，再落到 `ThemeData`，最后才是组件内字面量（§3）。
- 边界是**只动样式，不动结构与文案**（§6）。

---

## 1. 项目识别

- 命中文件：`pubspec.yaml`（`/pencil-map` 的栈判定表用它，见 `../pencil-bridge/references/design-map.md` §3 第 1 步）。
- **单仓多栈**：一个仓库里可以同时有多个栈根，例如 `client/`（Flutter）与 `admin/`（Web）。此时 `design-map.yaml` 用 `stacks` 列表，每条 `{ stack, root }`，各栈分别加载自己那份 reference。
- 判定要落到**哪一个** `pubspec.yaml`：`project.root` 是含该 `pubspec.yaml` 的目录；页面路径一律**相对它**写。
- `pubspec.yaml` 只说明「这是 Flutter/Dart 项目」，不说明页面在哪个目录 —— 页面定位见 §2。

---

## 2. 页面定位约定（与 `pages[].code.selector` 对应）

**页面目录是项目自定的，`lib/pages/` 只是其中一种。** 实测两个真实工程：

- 一个（feature-first）的 `lib/` 是 `app` / `components` / `config` / `constants` / `controllers` / `core` / `design_system` / `domain` / `engines` / `features` / …；
- 另一个的 `lib/` 是 `bean` / `common` / `components` / `index` / `launch` / `model` / `personal` / …。

feature-first 的 `lib/features/<feature>/…` 与平铺的 `lib/pages/` 同样常见。**不要假设固定路径**：先 `find` / `grep` 现有页面文件，或读入口文件的路由表（见下面手法 1）来确认。

> 上面提到的目录名只用于说明「形状不固定」，**不要写死成规范**；以当前项目的实际扫描结果为准。

定位手法（按可靠度排序）：

1. **路由表（若项目有）**：入口文件（如 `main.dart` / `app.dart` 或 `lib/routes/` 等独立路由文件）里 `routes` / `onGenerateRoute` / `getPages`（GetX，键是 `GetPage.name`）/ GoRouter 的 `path` 的键 → 页面 widget 名；**有路由表也要用手法 2 补齐未登记路由的页面；没有路由表就直接转手法 2**。
2. **类名扫描**：`grep -rnE "class [A-Za-z0-9_]*(Page|View|Screen) extends" lib/`（`StatelessWidget` / `StatefulWidget` / `ConsumerWidget` / `GetView` 都算）。**不要只扫 `*Page`** —— 实测某工程（`lib/modules/<feature>/` 布局）的三个页面类里有两个是 `*View`（`GetView` 子类），只扫 `*Page` 会把它们全漏掉。
3. **目录扫描**：`lib/pages/`、`lib/screens/`、`lib/features/*/presentation/`、`lib/modules/*/` 等，**随项目而异** —— 有的工程把视图直接放在 `lib/modules/<feature>/<name>_view.dart`，只按 `pages` / `screens` 找会一无所获。

**selector 锚点写类名串（`class XxxPage` / `class XxxView` / `class XxxScreen`，后缀随项目而异）** —— 实测 `*Page` 与 `*View` 在真实 Flutter 工程里都大量存在（`AboutPage` / `AccountBindPage` / `SettingsPage` / `LibraryView` / `ReaderView` / …），是稳定可 `grep` 的锚点。**但同名类可能在多处定义** —— 实测 `class AboutPage` 在同一工程的两份 `about_page.dart`（`lib/features/mine/about/about_page.dart` 与 `lib/pages/about/about_page.dart`）里各有一份，所以 `selector` 必须与 `code.file` 成对出现才能唯一定位，单给 `selector` 不足以消歧。`design-map.yaml` 里：

```yaml
pages:
  - design: { node: "C01 · 首页", id: JiRbS }
    code:
      file: lib/pages/home_page.dart   # 相对 project.root；真实路径按上面扫描结果填
      selector: "class HomePage"       # 直接用类名串
```

- `code.file` 写**相对 `project.root` 的路径**，不要写绝对路径。
- `code.selector` 是自由文本锚点，写 `class HomePage` 这种能被 `grep -F` 命中的串；同一文件里有多个类时，锚点要能唯一指向目标 widget。
- 上例的 `lib/pages/` 只是占位，实际目录以扫描结果为准。

---

## 3. 样式改动落点

按「token 常量 → 主题 → 组件」的顺序找落点，命中即停，不要越改越散：

| 设计属性 | Flutter 落点 | 说明 |
|---|---|---|
| 颜色 | token 常量类（`Color(0xFF…)`）；`ThemeData.colorScheme` / `ColorScheme.fromSeed` | 优先改 token 常量；`ThemeData` 里集中覆盖；组件内散落的 `Color(0x…)` 是最后手段 |
| 间距 | `EdgeInsets.all/symmetric/only`、`SizedBox(width/height:)`、`Padding(padding:)`、`Row`/`Column` 的 `mainAxisSpacing` / `crossAxisSpacing` | Flutter 没有 `dimens.xml` 式集中资源：间距常量要么进 token 类，要么留在组件里 |
| 圆角 | `BorderRadius.circular(n)`、`BoxDecoration(borderRadius:)`、`RoundedRectangleBorder(borderRadius:)`、`CardTheme` / `shape` | 改形状参数，不改容器层级 |
| 字号 | `TextStyle(fontSize:)`、`ThemeData.textTheme`（`bodyLarge` 等）、`TextTheme` | 先看这段文本用的是不是主题里的 style；是就改主题 |
| 字重 | `TextStyle(fontWeight: FontWeight.w400 … w700)`、`ThemeData.textTheme` | Flutter 用 `FontWeight.wNNN`，不是 CSS 的 `400` / `bold` |
| 布局方向 | `Directionality` / `textDirection:`、`Row`/`Column` 的轴与 `MainAxisAlignment` / `CrossAxisAlignment`、`Axis.horizontal` / `Axis.vertical` | **方向改动影响阅读顺序与无障碍语义**，只在设计明确要求时改 |

- **落点优先级**：token 常量类 → `ThemeData` / `ThemeExtension` → 组件内字面量。
- **只改目标页**：优先改 `pages[].code.file` 列出的文件；改公共主题前先确认影响面（`ThemeData` 是全局的）。
- **不改无关页**：同步一个页面的样式时，不要把同一主题的调整顺手扩散到别的页面（反向回写会因此对不上设计稿）。

---

## 4. Dart token 常量类输出格式（spec §9.2）

设计变量由 `Print(GetVariables())` 读出后，Flutter 侧的产物是一个 Dart 常量类：

```dart
// 需要 Color 时引入（Color 来自 dart:ui，经 material.dart 转出）
import 'package:flutter/material.dart';

class YxsTokens {
  static const primary = Color(0xFF…);
  static const radius = 8.0;
  static const spacingMd = 16.0;
}
```

- 类名默认 `YxsTokens`（取自设计变量的 `yxs` 前缀）；颜色写 `Color(0xAARRGGBB)` —— **8 位十六进制里 alpha 在前**。
- 非颜色变量（间距 / 圆角 / 字号）用 `double` 或 `int` 常量，同放这个类里，不要另起一套命名。
- **落地位置**：写进项目**已有**的常量目录（如 `lib/constants/`、`lib/theme/`、`lib/design_system/`），选项目里已有的那一处；不要为 token 新建目录结构。
- 生成的文件同样不得含绝对路径（本套装全仓库禁用）。

---

## 5. 变量引用的映射（`"$yxs-primary"` → Dart 常量名）

设计稿里的变量引用形如 `"$yxs-primary"`。映射规则**逐字**如下：

1. **去掉前导 `$`** ⇒ `yxs-primary`。
2. **按 `-` 拆分，非首段转小驼峰** ⇒ `primary`；`spacing-md` → `spacingMd`。
3. **首段是套装前缀 `yxs` 时提到类名** ⇒ `$yxs-primary` 落成 `YxsTokens.primary`；首段不是 `yxs` 时（如 `$ink`），整段成为一个常量名。

对照表：

| 设计变量 | Dart 落成 |
|---|---|
| `"$yxs-primary"` | `YxsTokens.primary` |
| `"$yxs-radius"` | `YxsTokens.radius` |
| `"$yxs-spacing-md"` | `YxsTokens.spacingMd` |
| `"$ink"` | `YxsTokens.ink`（平铺写法则用 `ink`） |

- 归一化后必须再检查一次：结果得是合法 Dart 标识符（不以数字开头、不含保留字、不含 `-`）。
- `design-map.yaml` 的 `pages[].tokens` 记的是**设计侧变量名**（如 `primary: "$yxs-primary"`），不记 Dart 侧名字 —— Dart 名字由本节规则推导，规则是唯一来源。

---

## 6. 边界：不改结构，不改文案

- **不改结构**：不加 / 删 / 挪 widget，不改 `children` 顺序与嵌套层级，不改路由。设计稿上出现新节点不等于「可以改代码结构」。
- **不改文案**：`Text('…')` 的字面量、l10n 的 `key` 与 `arb` 条目、常量字符串一律不动。设计稿上的文字变化不在本套装的同步范围内。
- 允许动的只有：§3 表里的样式属性 + §4 的 token 常量类。
- 拿不准时**停下问用户**，不要靠「看起来一样」猜。

---

## 相关 reference

- `../pencil-bridge/references/design-map.md` —— `pages[].code.selector` / `code.file` / `tokens` 的协议与 `design-map.yaml` 全 schema
- `../pencil-bridge/references/assets-extraction.md` —— token 输出格式的来源约定（spec §9.2）与四类素材的取法
- `../pencil-bridge/references/write-safety.md` —— 反向（代码 → 设计稿）回写时的写操作安全规程
