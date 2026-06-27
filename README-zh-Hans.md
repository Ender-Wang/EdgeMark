<img src=".github/assets/EdgeMark.svg" alt="EdgeMark" width="128" align="left" />

<b><font>EdgeMark</font></b>

 一款原生 macOS 侧边栏 Markdown 笔记应用。离你永远只有一次边缘滑动之遥。

<br clear="all" />

<p align="center">
  <a href="README.md">English</a> · <b>简体中文</b> · <a href="README-hi.md">हिन्दी</a> · <a href="README-ES.md">Español</a>
</p>

<p align="center">
  <a href="https://github.com/Ender-Wang/EdgeMark/releases"><img src="https://img.shields.io/github/v/release/Ender-Wang/EdgeMark?label=Latest%20Release&color=green" alt="Latest Release" /></a>
  <a href="https://github.com/Ender-Wang/EdgeMark/releases"><img src="https://img.shields.io/github/downloads/Ender-Wang/EdgeMark/total?color=green" alt="Total Downloads" /></a>
  <br />
  <img src="https://img.shields.io/badge/Swift-6.2-orange?logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/macOS-15.7+-black?logo=apple" alt="macOS" />
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Ender-Wang/EdgeMark?color=blue" alt="License" /></a>
</p>

**EdgeMark 的由来：** [SideNotes](https://www.apptorium.com/sidenotes) 把交互做到了极致——一个从屏幕边缘滑出的笔记面板，永远只需一次手势。但它是闭源且付费的，无法贡献、定制，也无法核实它如何处理你的数据。

EdgeMark 是开源替代方案：**轻量、Markdown 优先**，供你审查、修改和扩展。你的笔记是磁盘上的纯 `.md` 文件——可在任何编辑器中打开，用任何服务同步，按你喜欢的方式备份。

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/screenshot-dark.png" />
    <source media="(prefers-color-scheme: light)" srcset=".github/assets/screenshot-light.png" />
    <img alt="EdgeMark Screenshots" src=".github/assets/screenshot-light.png" />
  </picture>
</p>

# 安装

```bash
brew install --cask ender-wang/tap/edgemark
```

或从 [Releases](https://github.com/Ender-Wang/EdgeMark/releases) 下载最新 `.dmg`，安装后在终端运行：

```bash
xattr -cr /Applications/EdgeMark.app
```

---

# 功能特性

🪟 **侧边面板**

- 🔲 无边框浮动面板，全高度，始终置顶
- 🖥️ 在所有虚拟桌面及全屏应用旁均可使用
- ✨ 平滑的滑入/滑出或渐变动画（可配置），支持边缘激活——将鼠标移至屏幕边缘即可唤出
- 🖱️ 点击外部、Escape 或自动隐藏退出
- 📌 固定以保持面板开启——不受焦点切换、鼠标移出和空间切换影响（方便来回复制粘贴）
- 📐 多显示器支持，可配置左边缘或右边缘
- ↔️ 可调宽度——拖动内侧边缘调整，重启后保留
- 🪟 面板样式——在半透明和不透明面板背景之间切换
- 🎨 面板色调——从精选配色中选择（系统、石墨灰、板岩蓝、沙色、鼠尾草绿、玫瑰粉）

✍️ **Markdown 编辑**

- 👁️ 原生 TextKit 2 WYSIWYG 编辑器——由 [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine) 驱动，不依赖 JavaScript 或 WebKit
- 📝 完整 Markdown：标题、粗体、斜体、代码、列表、任务列表、引用、链接、表格、wiki 链接
- 🖼️ 内联图片——粘贴（`⌘V`）或拖拽嵌入；作为附属资源文件与笔记同目录存放
- ✅ 已勾选的任务项自动加删除线；取消勾选即恢复
- 📋 围栏代码块一键复制按钮
- 🔴 原生拼写检查、语法检查和自动更正（macOS 系统词典）
- ⚡ 斜杠命令（`/h1`、`/todo`、`/code`、`/quote`、`/table`、`/divider` 等）
- ⌨️ 格式化快捷键：`⌘B` 粗体、`⌘I` 斜体、`⌘E` 行内代码、`⌘K` 链接、`⇧⌘X` 删除线
- 🔗 点击渲染后的链接在浏览器中打开
- 🔍 查找与替换（`⌘F`）
- 🔤 可自定义编辑器字体和字号——通过系统字体面板选择任意已安装字体并实时预览
- 🧮 LaTeX 渲染——块级（`$$...$$`）和行内（`$...$`），由 SwiftMath 驱动

🗂️ **笔记与存储**

- 📄 纯 `.md` 文件，无注入头部——可在任何编辑器打开，用任何服务同步；元数据存放在隐藏的 `.edgemark/meta.json` 附属文件中
- 📁 基于文件夹的组织，支持拖放
- 🎨 自定义文件夹颜色——右键 → 文件夹颜色，用配色为任意文件夹图标着色
- 📂 可配置的存储目录
- 💾 1 秒防抖自动保存
- 🔍 搜索在查询为空时显示按最近修改排序的全部笔记——一个快捷的“最近笔记”流
- 🏷️ Finder 风格的颜色标签（红、橙、黄、绿、蓝、紫、灰），标签可重命名；每条笔记支持多标签
- 🎯 搜索内的标签筛选——点击标签圆点缩小结果，多选为“或”关系，可与文本搜索组合
- ☑️ 原生 macOS 多选——点击 / ⇧-点击 / ⌘-点击行，框选拖拽批量选中，再从右键菜单批量**移动**、**打标签**或**删除**；批量中的冲突会排队并可逐一解决
- 🔄 外部文件同步——面板打开时检测来自其他应用的编辑；双方都改动时弹出提示
- 🗑️ 废纸篓，30 天自动清除，只读预览
- 👁️ 悬停预览——将鼠标悬停在笔记或文件夹行上，即可在列表旁的浮动面板中预览其内容；笔记预览渲染完整 Markdown（含图片），文件夹预览显示子文件夹和其中的所有笔记

⌨️ **键盘与快捷键**

- 🌐 全局快捷键：`Ctrl+Shift+Space` 从任意应用切换（可自定义）
- 🎹 完全可自定义的局部快捷键——新建笔记、新建文件夹、搜索、固定、上一条/下一条笔记——均可在设置中重绑并检测冲突
- ⏱️ 可配置的激活延迟和角落排除区
- 🔑 默认面板快捷键：`⌘N` 新建笔记、`⇧⌘N` 新建文件夹、`⌘F` 搜索、`⌘P` 固定/取消固定
- 👁️ `空格` 快速预览——选中笔记或文件夹后按 `空格` 预览；`↑↓` 浏览，`空格`/`ESC` 关闭
- 👆 在标题栏双指右滑返回（可配置开关和灵敏度）
- 👆 在编辑器上双指左/右滑动或 `⌘←`/`⌘→` 在当前文件夹的笔记之间切换

🔄 **自动更新与 CI/CD**

- 🔔 应用内更新检查（GitHub Releases，24 小时节流）
- 📦 带进度条下载、SHA256 校验、安装并重启
- ⚙️ GitHub Actions 构建流水线（未签名 Release、DMG、SHA256）
- 🍺 Homebrew Cask 安装

🌟 **体验优化**

- 🌗 外观覆盖：系统、浅色或深色模式
- 📌 常驻菜单栏（无 Dock 图标）
- 🚀 登录时启动
- 📋 复制为纯文本、Markdown 或富文本——编辑器内选中感知的右键菜单
- 🎨 所有右键菜单均使用 SF Symbol 图标
- 🔀 平滑的定向页面过渡
- 🌍 English + 简体中文 + हिन्दी + Español（基于 JSON，易于贡献）

---

# 贡献

架构概览、源码目录树、关键模式、本地化指南和开发环境配置，见 [CONTRIBUTING.md](CONTRIBUTING.md)。

---

# 许可证

EdgeMark 基于 [GNU General Public License v3.0](LICENSE) 授权。

# 致谢

EdgeMark 构建于以下开源项目之上：

| 项目 | 许可证 | 说明 |
|---------|---------|-------------|
| [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine) | Apache 2.0 | TextKit 2 / NSTextView WYSIWYG Markdown 编辑器——支撑编辑体验。内置 [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) 用于代码块语法高亮，[SwiftMath](https://github.com/mgriebling/SwiftMath) 用于 LaTeX 渲染。 |
| [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) | MIT | 构建流水线中使用的代码格式化工具 |

---

# Star 历史

<a href="https://star-history.com/#Ender-Wang/EdgeMark&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date" />
 </picture>
</a>
