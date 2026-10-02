# stack-web —— Web 栈的项目识别、页面定位与 token 落点

本文是 pencil-bridge 套装里 Web 栈的**唯一**分栈参考；`/pencil-map`（建映射）与 `/pencil-assets`（出 token）探测到 Web 项目时按需加载它，`/pencil-sync` 沿用它定「样式改哪里」。来源：spec §12（分栈清单）与 §9.2（三栈 token 输出格式）。
本文里的 `§N` 指本文小节号，`spec §N` 指设计规范章节号。

先记住四条：

- 识别要同时认**构建型**与**纯静态**两种 Web 项目，`package.json` 不是可靠判据（§1）。
- 页面定位：构建型看路由 → 组件文件，纯静态看散装 `*.html`（§2）。
- 样式落点优先级：CSS 自定义属性 → 类规则 → 行内样式（§3）。
- 边界是**只动样式，不动结构与文案**（§6）。

---

## 1. 项目识别

Web 项目分两型，判据是「**有没有构建器配置** + 页面文件长什么样」，不是文件名本身：

- **构建型**：有 `package.json`，且配 lockfile 与构建器配置之一（`vite.config.*` / `next.config.*` / `nuxt.config.*` / `angular.json` / `webpack.config.*` / `svelte.config.*`）。页面由 `src/` 下的组件编译产出。
- **纯静态**：没有 `package.json`、没有构建器配置，页面是**散装 `*.html`** —— 例如某纯静态站点目录里就是几个 `*-index.html`，每个文件自成一个页面，样式在页内 `<style>` 块或同目录 `.css` 里。
- **⚠️ 有 `package.json` 不等于构建型**：仓库根可能同时有 `package.json` 与散装 `*-index.html`（实测：某桌面应用发布目录的 `package.json` 描述的是 Electron 桌面应用，页面仍是几个散装 `*-index.html`）。要再看依赖里有没有 UI 框架 / 构建器，以及页面文件的实际形态。
- **⚠️ 跨平台框架的平台壳不是 Web 栈**：Flutter / React Native / Expo / Capacitor 的 `android/` / `ios/` / `web/` 目录属于**父栈**，不要因为里面有 `index.html` 就判成「纯静态 Web」。
- **框架产物目录与依赖目录不参与探测**：`.next/` / `.nuxt/` / `.svelte-kit/` / `.output/` / `build/` / `dist/`，以及 `node_modules/`，一律**不要扫进去**。
- **⚠️ 探测要钉在项目根上跑 git，并排除自带工具链与忽略目录**：用 git 跟踪状态收敛时必须钉在项目根上跑 `git -C <项目根> ls-files`（等价 `cd <项目根> && git ls-files`），**绝不**裸跑 `git ls-files` —— 它只列**当前目录**下的文件，且输出路径**相对当前目录**。跟踪状态只是**收敛手段、不是判定前提**：不在 git 工作树内（`git rev-parse --is-inside-work-tree` 失败）或 `git ls-files` 结果为空时，退回「递归扫描 + 排除类」；跟踪层给出零命中时**不得**据此判定「本项目没有栈」，零命中只说明这一层不适用。**仓库内自带的工具链 / 第三方源码副本**（如 `tools/<sdk>/`、`vendor/`、`third_party/`）与 **`.gitignore` 忽略目录**同样不参与探测（判据是它是不是本项目的应用代码；忽略目录可用 `git check-ignore -q <目录>` 判定）。
- **单仓多栈**：同一仓库可同时有 `admin/`（构建型 Web）与 `client/`（别的栈）；此时 `design-map.yaml` 用 `stacks` 列表，每条 `{ stack, root }`，各栈分别加载自己那份 reference（见 `../pencil-bridge/references/design-map.md` §2）。
- `stacks[].root` 是**这一栈的栈根**（相对 `project.root` 写）；`project.root` 始终是**项目根**（含 `.git` 的最近祖先；无 `.git` 则回落 cwd，见 `../pencil-bridge/references/design-map.md` §1）。`pages[].code.file` 一律**相对 `project.root`** 写，不要写绝对路径。

---

## 2. 页面定位

### 2.1 构建型

- 页面 = 路由 → 组件文件。先读路由配置（`src/router*` / `src/routes/` / `app/` 目录约定 / 框架自己的约定），再由路由串找到组件文件。
- 目录约定**随框架与项目而异**：React 常见 `src/pages/*.tsx`，Vue 常见 `src/views/*.vue`，Svelte / Angular 各有各的；**不要假设固定路径**，以项目实际结构为准。
- `code.selector` 写组件名（`HomePage`）或路由 `path`（`/home`）—— 选能唯一 `grep` 到的那个。

### 2.2 纯静态

- **每个 `*-index.html` 就是一个页面**；`code.file` 写该 html 的相对路径。
- `code.selector` 写页内稳定的 CSS 选择器（见下）。
- 样式常在同一文件的 `<style>` 块里，或同目录 / 上级的 `.css` 文件里。

### 2.3 CSS 选择器的稳定性

- 优先用 **`id`**、**`data-*` 属性**、**语义化 class**（`.hero` / `.pricing-card` 这类）。
- **避开**自动生成或带 hash 后缀的类名（CSS Modules、styled-components、Tailwind 的任意值类都可能是构建产物）—— 它们会随构建变化，锚上去下次就失效。
- 锚点要能被 `grep -F` 命中；命中多个时加父级限定。

---

## 3. 样式改动落点

按优先级从上到下，**命中即停**：

1. **CSS 自定义属性**（`:root` / `[data-theme]` 里的 `--xxx`）—— 首选。改一处全站生效，也最贴近设计变量的语义。
2. **类规则**（`.css` 文件或页内 `<style>` 块里的选择器）。
3. **行内样式**（`style="…"`）—— 散装 HTML 里常见。最直接，但优先级最高、会盖掉变量与类，且破坏复用；**只在目标元素没有可用的变量 / 类时才动**。
4. **Tailwind 工具类**（`class="bg-… text-…"`）—— 改它等于改组件标记，只加 / 改样式类，不顺手改 DOM 结构（§6）。优先改成引用 §5 映射出来的 token 类。

- 能改变量就不要改类，能改类就不要改行内。
- 只改目标页涉及的样式来源；改全站入口的变量文件前先确认影响面。

---

## 4. CSS 变量输出格式（spec §9.2）

设计变量读出后，Web 侧的产物是一份 CSS 自定义属性文件：

```css
:root {
  --yxs-primary: #1a73e8;
  --yxs-radius: 8px;
}

[data-theme="dark"] {
  --yxs-primary: #8ab4f8;
}

@media (prefers-color-scheme: dark) {
  :root {
    --yxs-primary: #8ab4f8;
  }
}
```

- **变量名规则**：去掉前导 `$`，其余**原样**（CSS 自定义属性允许 `-` 与小写），并加 `--` 前缀。
  - `"$yxs-primary"` → `--yxs-primary`
  - `"$yxs-spacing-md"` → `--yxs-spacing-md`
  - 与 Flutter / Android 侧相比，Web 侧**不做驼峰或下划线转换**，是唯一保持连字符的栈。
- **多维主题**（`themes` 里的 `mode` / `locale` 等）在 Web 侧按分组展开：主题维度用 `[data-theme="dark"]`，语言维度用 `[data-locale="en"]`；只看系统偏好的用 `@media (prefers-color-scheme: dark)`。
- **两种深色机制只选一种**，跟随项目**已有**的那一种，不要两套并上（`[data-theme]` 是显式可控的，`prefers-color-scheme` 是跟随系统的；同时存在会互相打架）。
- **产物落地**：写到项目**已有**的样式入口（如 `styles/variables.css` 并在主入口 `@import` / 引入），不要只丢一个没人引用的文件。

---

## 5. Tailwind 映射约定（若项目有 Tailwind）

先确认项目**是否真的用了 Tailwind**（`package.json` 里有 `tailwindcss`，且有配置文件或 `@theme` / `@import "tailwindcss"`）。

- **有 Tailwind（v3 及以前，`tailwind.config.js`）**：把设计变量接到 `theme.extend`，值直接引用 §4 的 CSS 变量 —— 这样切换主题时工具类跟着变：

```js
module.exports = {
  theme: {
    extend: {
      colors: { yxs: { primary: 'var(--yxs-primary)' } },
      borderRadius: { 'yxs-md': 'var(--yxs-radius)' },
    },
  },
};
```

- **有 Tailwind v4**：配置是 **CSS-first** 的 —— 用样式表里的 `@theme` 块声明 token，`tailwind.config.js` 不再是唯一来源。先看项目装的是哪个大版本与实际写法，跟随它，不要两套配置并上。
- **没有 Tailwind 就不要引入**：本技能的 token 产物就是 §4 那份 CSS 变量文件，**不新增依赖、不改构建配置**。Tailwind 是「项目已有才映射」，不是本技能的产出。
- 映射只加 token 键，不改动既有的 `theme` 结构。

---

## 6. 边界：不改结构，不改文案

- **不改结构**：不动 DOM 层级与标签，不增删元素与属性集合，不拆分 / 合并组件，不改路由。Tailwind 项目里改 `class` 时只动样式类，不借机调整结构。设计稿上出现新节点不等于「可以改结构」。
- **不改文案**：可见文本、`alt` / `title` / `placeholder` / `aria-label`、i18n 词条一律不动。文字变化不在本套装的同步范围内。
- 允许动的只有：§3 的样式落点、§4 的 CSS 变量文件、§5 的 Tailwind token 映射。
- 拿不准时**停下问用户**。

---

## 相关 reference

- `../pencil-bridge/references/design-map.md` —— `pages[].code.selector` / `code.file` / `tokens` 的协议与 `design-map.yaml` 全 schema
- `../pencil-bridge/references/assets-extraction.md` —— token 输出格式的来源约定（spec §9.2）与四类素材的取法
- `../pencil-bridge/references/write-safety.md` —— 反向（代码 → 设计稿）回写时的写操作安全规程
