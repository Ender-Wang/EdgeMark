<img src=".github/assets/EdgeMark.svg" alt="EdgeMark" width="128" align="left" />

<b><font>EdgeMark</font></b>

 A native macOS side-panel Markdown notes app. Always one edge away.

<br clear="all" />

<p align="center">
  <b>English</b> · <a href="README-zh-Hans.md">简体中文</a> · <a href="README-hi.md">हिन्दी</a> · <a href="README-ES.md">Español</a>
</p>

<p align="center">
  <a href="https://github.com/Ender-Wang/EdgeMark/releases"><img src="https://img.shields.io/github/v/release/Ender-Wang/EdgeMark?label=Latest%20Release&color=green" alt="Latest Release" /></a>
  <a href="https://github.com/Ender-Wang/EdgeMark/releases"><img src="https://img.shields.io/github/downloads/Ender-Wang/EdgeMark/total?color=green" alt="Total Downloads" /></a>
  <br />
  <img src="https://img.shields.io/badge/Swift-6.2-orange?logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/macOS-15.7+-black?logo=apple" alt="macOS" />
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Ender-Wang/EdgeMark?color=blue" alt="License" /></a>
</p>

**Why EdgeMark exists:** [SideNotes](https://www.apptorium.com/sidenotes) nailed the interaction — a notes panel that slides in from the screen edge, always one gesture away. But it's closed-source and paid, with no way to contribute, customize, or verify what it does with your data.

EdgeMark is the open-source alternative: **lightweight, Markdown-first**, and yours to inspect, modify, and extend. Your notes are plain `.md` files on disk — open them in any editor, sync with any service, back them up however you want.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/screenshot-dark.png" />
    <source media="(prefers-color-scheme: light)" srcset=".github/assets/screenshot-light.png" />
    <img alt="EdgeMark Screenshots" src=".github/assets/screenshot-light.png" />
  </picture>
</p>

# Install

```bash
brew install --cask ender-wang/tap/edgemark
```

Or download the latest `.dmg` from [Releases](https://github.com/Ender-Wang/EdgeMark/releases), install it, and then run this command in Terminal:

```bash
xattr -cr /Applications/EdgeMark.app
```

---

# Features

🪟 **Side Panel**

- 🔲 Borderless floating panel, full-height, always on top
- 🖥️ Works on every virtual Desktop and alongside fullscreen apps
- ✨ Smooth slide-in/out or fade animation (configurable) with edge activation — move mouse to screen edge to reveal
- 🖱️ Click outside, Escape, or auto-hide dismissal
- 📌 Pin to keep the panel open — survives focus changes, mouse exit, and Space switches (great for copy-pasting back and forth)
- 📐 Multi-monitor support with configurable left or right edge
- ↔️ Adjustable width — drag the inner edge to resize, saved across restarts
- 🪟 Panel style — toggle between Translucent and Opaque panel backgrounds
- 🎨 Panel tint — pick from a curated palette (System, Graphite, Slate, Sand, Sage, Rose)

✍️ **Markdown Editing**

- 👁️ Native TextKit 2 WYSIWYG editor — powered by [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine), no JavaScript or WebKit involved
- 📝 Full Markdown: headings, bold, italic, code, lists, task lists, blockquotes, links, tables, wiki-links
- 🖼️ Inline images — paste (`⌘V`) or drag to embed; stored as co-located asset files alongside the note
- ✅ Checked task items are automatically struck through; uncheck to restore
- 📋 One-click Copy button on fenced code blocks
- 🔴 Native spell check, grammar check, and autocorrect (macOS system dictionary)
- ⚡ Slash commands (`/h1`, `/todo`, `/code`, `/quote`, `/table`, `/divider`, and more)
- ⌨️ Formatting shortcuts: `⌘B` bold, `⌘I` italic, `⌘E` inline code, `⌘K` link, `⇧⌘X` strikethrough
- 🔗 Click a rendered link to open it in the browser
- 🔍 Find & Replace (`⌘F`)
- 🔤 Customizable editor font and size — pick any installed font via the system font panel with live preview
- 🧮 LaTeX rendering — block (`$$...$$`) and inline (`$...$`) via SwiftMath

🗂️ **Notes & Storage**

- 📄 Plain `.md` files with no injected headers — open in any editor, sync with any service; metadata lives in a hidden `.edgemark/meta.json` sidecar
- 📁 Folder-based organization with drag-and-drop
- 🎨 Custom folder colors — tint any folder's icon with a palette color via right-click → Folder Color
- 📂 Configurable storage directory
- 💾 1-second debounced auto-save
- 🔍 Search shows all notes sorted by most recently modified when the query is empty — a quick "recent notes" feed
- 🏷️ Finder-style color tags (Red, Orange, Yellow, Green, Blue, Purple, Gray) with rename-able labels; multi-tag per note
- 🎯 Tag filter inside search — click tag dots to narrow results, multi-select acts as OR, combines with text search
- ☑️ Native macOS multi-selection — click / ⇧-click / ⌘-click rows, marquee-drag to box-select, then batch **Move**, **Tag**, or **Trash** from the right-click menu; conflicts in a batch are queued and resolvable
- 🔄 External file sync — edits from other apps are detected on panel open; prompts when both sides changed
- 🗑️ Trash with 30-day auto-purge and read-only preview
- 👁️ Hover-to-peek — hover over a note or folder row to preview its contents in a floating panel alongside the list; note previews render full Markdown with images, folder previews show subfolders and all notes inside

⌨️ **Keyboard & Shortcuts**

- 🌐 Global shortcut: `Ctrl+Shift+Space` toggles from any app (customizable)
- 🎹 Fully customizable local shortcuts — new note, new folder, search, pin, prev/next note — all rebindable in Settings with conflict detection
- ⏱️ Configurable activation delay and corner exclusion zones
- 🔑 Default panel shortcuts: `⌘N` new note, `⇧⌘N` new folder, `⌘F` search, `⌘P` pin/unpin
- 👁️ `Space` to Quick Look — select a note or folder and press `Space` to preview; `↑↓` to browse, `Space`/`ESC` to dismiss
- 👆 Two-finger trackpad swipe right on the header to navigate back (configurable toggle and sensitivity)
- 👆 Two-finger swipe left/right on the editor or `⌘←`/`⌘→` to navigate between notes in the current folder

🔄 **Auto-Update & CI/CD**

- 🔔 In-app update check (GitHub Releases, 24h throttle)
- 📦 Download with progress bar, SHA256 verification, install & restart
- ⚙️ GitHub Actions build pipeline (unsigned Release, DMG, SHA256)
- 🍺 Homebrew Cask installation

🌟 **Quality of Life**

- 🌗 Appearance override: System, Light, or Dark mode
- 📌 Menu bar resident (no Dock icon)
- 🚀 Launch at login
- 📋 Copy as Plain Text, Markdown, or Rich Text — selection-aware in editor with right-click context menu
- 🎨 SF Symbol icons throughout all context menus
- 🔀 Smooth directional page transitions
- 🌍 English + Simplified Chinese + Hindi + Spanish (JSON-based, easy to contribute)

---

# Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for architecture overview, source tree, key patterns, localization guide, and development setup.

---

# License

EdgeMark is licensed under the [GNU General Public License v3.0](LICENSE).

# Acknowledgments

EdgeMark is built on top of these open-source projects:

| Project | License | Description |
|---------|---------|-------------|
| [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine) | Apache 2.0 | TextKit 2 / NSTextView WYSIWYG Markdown editor — powers the editing experience. Bundles [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) for code block syntax highlighting and [SwiftMath](https://github.com/mgriebling/SwiftMath) for LaTeX rendering. |
| [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) | MIT | Code formatting tool used in the build pipeline |

---

# Star History

<a href="https://star-history.com/#Ender-Wang/EdgeMark&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date" />
 </picture>
</a>
