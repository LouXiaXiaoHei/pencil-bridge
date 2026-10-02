# stack-kotlin —— Kotlin / Android 栈的项目识别、页面定位与 token 落点

本文是 pencil-bridge 套装里 Kotlin / Android 栈的**唯一**分栈参考；`/pencil-map`（建映射）与 `/pencil-assets`（出 token）探测到 Gradle 构建文件或 `AndroidManifest.xml` 时按需加载它，`/pencil-sync` 沿用它定「样式改哪里」。来源：spec §12（分栈清单）与 §9.2（三栈 token 输出格式）。
本文里的 `§N` 指本文小节号，`spec §N` 指设计规范章节号。

先记住四条：

- 识别要同时认 `build.gradle` 与 `build.gradle.kts`；**只有 `AndroidManifest.xml` 才能确定这是 Android 模块**（§1）。
- 页面定位分 **XML 布局**与 **Jetpack Compose** 两条路径，锚点写法不同（§2）。
- 样式优先落到 `res/values/` 资源；只有 Compose 项目才落到 Kotlin 里的主题（§3）。
- 边界是**只动样式，不动结构与文案**（§6）。

---

## 1. 项目识别

- 命中文件（`/pencil-map` 的栈判定表）：
  - `build.gradle` —— Gradle **Groovy DSL**；
  - `build.gradle.kts` —— Gradle **Kotlin DSL**。
  - **两种都在真实工程里并存**，识别时两个扩展名都要认，不要只写其中一个。
- `AndroidManifest.xml` 是「这是 Android 模块」的确定标志。只有 `build.gradle(.kts)` 而没有 manifest 的，可能是纯 JVM / Kotlin 项目 —— 那些没有 `res/` 资源目录，Android 资源那一套（§3–§5）不适用。
- **⚠️ 跨平台框架的 Android 宿主壳不是独立栈**：Flutter / React Native / Expo / Capacitor 工程的 `android/` 目录里确实有 `build.gradle(.kts)` 与 `AndroidManifest.xml`，但它们属于**父栈**（父栈根是含 `pubspec.yaml` 或根 `package.json` 的那一层），**不计入 `stacks`**。判据：该 `android/` 的同级或上级存在父栈清单文件。
- 模块结构：`settings.gradle(.kts)` 列模块；模块级构建文件在 `<module>/build.gradle(.kts)`（`app/` 是默认名，但不保证）。资源与源码根是 `<module>/src/main/`。
- **单仓多栈**：一个仓库可以同时有 `client/` 与 `admin/` 这类多栈根；此时 `design-map.yaml` 用 `stacks` 列表，每条 `{ stack, root }`，各栈分别加载自己那份 reference（见 `../pencil-bridge/references/design-map.md` §2）。
- `project.root` 是所选 `stacks[].root`；`pages[].code.file` 一律**相对它**写，不要写绝对路径。

---

## 2. 页面定位

两条路径，先判项目用的是哪条（Compose 与 XML 也可能在同一模块里共存）：

### 2.1 XML 布局路径

- 布局文件：`<module>/src/main/res/layout/<name>.xml`。
- 页面类：Activity / Fragment 在 `<module>/src/main/java/…` 或 `<module>/src/main/kotlin/…` —— **实际用哪个取决于 `sourceSets`，不要凭目录名假设**。
- selector 锚点用**代码类名**：`class HomeActivity`、`class HomeFragment`、`class HomeScreen`。布局文件名进 `code.file`。
- 反查手法：代码里 `setContentView(R.layout.xxx)` / `inflate(R.layout.xxx, …)` 从布局名找到宿主类。

### 2.2 Jetpack Compose 路径

- 没有布局 XML：界面是 `@Composable` 函数。
- selector 锚点写函数签名：`fun HomeScreen`（或 `@Composable fun HomeScreen`）。
- 导航靠 `NavHost` / `composable("route") { … }`：从路由串找目标 `@Composable`。
- 命名约定随项目而异（`*Screen` / `*Page` / `*Route`），以扫描结果为准。

### 2.3 写进 `design-map.yaml`

```yaml
pages:
  - design: { node: "C01 · 首页", id: JiRbS }
    code:
      file: app/src/main/res/layout/activity_home.xml   # 相对 stacks[].root
      selector: "class HomeActivity"
```

- `code.selector` 是自由文本锚点，写能被 `grep -F` 命中的串（类名或 Composable 函数名）。
- 布局重构会让布局文件名漂移，**类名更稳**；能锚类名就不要只锚 `R.layout.*`。

---

## 3. 样式改动落点

| 设计属性 | Android 落点 | 说明 |
|---|---|---|
| 颜色 | `res/values/colors.xml`（引用 `@color/yxs_primary`）；Compose → `MaterialTheme.colorScheme` | 优先改资源；Compose 项目改 Kotlin 里的主题 |
| 间距 | `res/values/dimens.xml`（`@dimen/...`）、XML 的 `android:layout_margin*` / `android:padding*`；Compose → `Modifier.padding(...)` / `Arrangement.spacedBy(...)` | 间距常量进 `dimens.xml`；单位用 `dp` |
| 圆角 | XML 的 `app:cardCornerRadius`、`shape` drawable 的 `<corners android:radius>`；Compose → `RoundedCornerShape(...)` | 改形状参数，不改层级 |
| 字号 | `res/values/styles.xml` 的 `<item name="android:textSize">` / `TextAppearance`；Compose → `MaterialTheme.typography` / `TextStyle(fontSize = ...sp)` | 字号单位用 `sp`（随系统字体缩放） |
| 字重 | `android:textStyle`（`bold` / `italic`）、`android:textFontWeight`（API 28+）；Compose → `FontWeight.W400 … W700` | `textFontWeight` 有 API 门槛，低版本要看项目 minSdk |
| 布局方向 | `android:layoutDirection`、`LinearLayout` 的 `android:orientation`、ConstraintLayout 约束；Compose → `Row` / `Column` + `LayoutDirection` | **方向改动影响阅读顺序与无障碍语义**，只在设计明确要求时改 |

- **落点优先级**：`res/values/` 资源 → 布局 / 组件内的 `android:*` 属性 → Compose 主题。
- **只改目标页**：`pages[].code.file` 是布局就改布局，是 Composable 文件就改该文件；主题是全局的，改前先确认影响面。

---

## 4. `colors.xml` 输出格式（spec §9.2）

设计变量读出后，Kotlin / Android 侧的产物是 `colors.xml`（需要时再加 `dimens.xml` / `styles.xml`）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
  <color name="yxs_primary">#FF1A73E8</color>
  <color name="yxs_surface">#FFFFFFFF</color>
</resources>
```

- **颜色位数**：写 `#AARRGGBB`（**alpha 在前**），与 CSS 的 `#RRGGBBAA` 顺序**相反**；也接受 `#RGB` / `#ARGB` / `#RRGGBB` 缩写形式，但产物统一写 8 位以免歧义。
- **名字规则与 Dart 侧一致**（去掉前导 `$`、按 `-` 分段），**但分隔符是 `_` 而不是驼峰**：Android 资源名只允许 `[a-z0-9_]`，不允许 `-`、不允许大写。
  - `"$yxs-primary"` → `name="yxs_primary"`
  - `"$yxs-spacing-md"` → `name="yxs_spacing_md"`
- 其它资源同理，各自的前缀与单位不同：

```xml
<dimen name="yxs_spacing_md">16dp</dimen>
<style name="TextAppearance.Yxs.Body">…</style>
```

- **落地位置**：`<module>/src/main/res/values/` 下已有的同名文件就**追加**，没有才新建；不要为一个 token 另起资源文件命名体系。

---

## 5. 资源目录约定

- `res/values/` —— 默认资源（浅色）。`colors.xml` / `dimens.xml` / `styles.xml` 都在这里。
- `res/values-night/` —— **同名键的暗色覆盖**，系统深色模式自动选用；**只放要覆盖的键**，不要整份复制。实测它在真实 Android 工程里大量存在（本机多个工程都有 `values-night/`），`colors.xml` / `dimens.xml` / `styles.xml` 与 `res/values/` 也都有实测样本。
- 其它限定符目录（`values-zh-rCN`、`values-v31`、`values-sw600dp` 等）按需使用：**Android 的多维主题靠目录限定符分组**，不是靠一套主题名。
- `res/` 下还有 `drawable/` / `mipmap/` / `layout/`；本技能只动 §3 表里的样式资源与前一条的 token 文件，不动图标与布局结构。
- 上面提到的目录名只用于说明形状，**不要把具体工程名或模块名写死成规范**。

---

## 6. 边界：不改结构，不改文案

- **不改结构**：不改布局层级与 `View` 的父子关系，不改 `ConstraintLayout` 约束拓扑，不改 Compose 的 composable 调用树，不改导航图。设计稿上的新增节点不等于「可以改结构」。
- **不改文案**：布局里的 `android:text`、`strings.xml` 的词条与 `name`、Compose 里的字符串字面量一律不动。文字变化不在本套装的同步范围内。
- 允许动的只有：§3 表里的样式属性 + §4 的 token 资源。
- 拿不准时**停下问用户**。

---

## 相关 reference

- `../pencil-bridge/references/design-map.md` —— `pages[].code.selector` / `code.file` / `tokens` 的协议与 `design-map.yaml` 全 schema
- `../pencil-bridge/references/assets-extraction.md` —— token 输出格式的来源约定（spec §9.2）与四类素材的取法
- `../pencil-bridge/references/write-safety.md` —— 反向（代码 → 设计稿）回写时的写操作安全规程
