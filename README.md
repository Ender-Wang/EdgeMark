<img src=".github/assets/EdgeMark.svg" alt="EdgeMark" width="128" align="left" />

<b><font>EdgeMark</font></b>

 A native macOS side-panel Markdown notes app. Always one edge away.

<br clear="all" />

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

# Install

```bash
brew install --cask ender-wang/tap/edgemark
```

Or download the latest `.dmg` from [Releases](https://github.com/Ender-Wang/EdgeMark/releases).

---

# Roadmap

## M1: The Bone — Side Panel + Animation ✅

- [x] Borderless floating panel (400px, full height, stays on top)
- [x] Works on every virtual Desktop + alongside fullscreen apps
- [x] Butter-smooth slide-in/out animation (0.2s)
- [x] Edge activation (mouse to screen edge to reveal)
- [x] Click outside / Escape / auto-hide dismissal
- [x] Global shortcut: `Ctrl+Shift+Space` toggles from any app
- [x] Menu bar icon + menu (Toggle, Settings, Quit)
- [x] Multi-monitor support
- [x] Corner exclusion (avoid conflict with macOS hot corners)

## M2: Markdown Notes — Core Editing ✅

- [x] Note model + folder-based organization
- [x] File storage: plain `.md` files with YAML front matter in `~/Documents/EdgeMark/`
- [x] Configurable notes storage directory
- [x] CodeMirror 6 WYSIWYG editor with cursor-aware live preview (hides syntax, reveals on cursor line)
- [x] Full Markdown support (headings, bold, italic, code, lists, task lists, blockquotes, links)
- [x] Slash commands (`/h1`, `/todo`, `/code`, `/quote`, `/table`, and more)
- [x] Note list UI: folder picker → note cards → editor
- [x] 1-second debounced auto-save
- [x] Trash: `.trash/` directory storage with read-only preview

## M3: Settings + Polish ✅

- [x] Settings window (General, Keyboard, About tabs)
- [x] Configurable: left/right edge, activation delay, corner exclusion, auto-hide
- [x] Custom global shortcut recorder
- [x] Launch at login
- [x] Auto-update: check, download with progress, SHA256 verify, install & restart
- [x] ~~Note card colors, search, drag-and-drop reorder~~
- [x] Find & Replace (Cmd+F)
- [x] Localization: JSON-based i18n (English + Simplified Chinese)

## M4: CI/CD + Auto-Update ✅

- [x] GitHub Actions build pipeline (unsigned Release, DMG, SHA256, GitHub Releases)
- [x] Homebrew Cask auto-generated
- [x] In-app update check (check GitHub Releases, 24h throttle)
- [x] Download + install update UI (progress, verify, install, restart)
- [x] OSLog with categorized loggers

## M5: Sharing + Export ✅

- [x] Copy as plain text / Markdown source / ~~Copy as image~~
- [x] ~~Save as image (configurable margins/background)~~
- [x] ~~System share sheet~~
- [x] ~~`edgemark://` URL scheme~~

## M6: Advanced Markdown (Typora-style) ✅

- [x] Cursor-aware inline rendering — hide Markdown syntax when cursor isn't on the element (via CodeMirror 6 WYSIWYG plugin)

---

# Localization

EdgeMark uses a custom JSON-based i18n system. Currently supported:

| Language | File | Status |
|----------|------|--------|
| English | `Resources/Locales/en.json` | ✅ |
| Simplified Chinese | `Resources/Locales/zh-Hans.json` | ✅ |

## Contributing a Translation

1. Copy `Resources/Locales/en.json`
2. Rename to your language code (e.g. `ja.json`, `ko.json`, `fr.json`, `de.json`)
3. Translate the values (keep the keys as-is)
4. Submit a PR

No code changes needed — the app picks up new locale files automatically.

---

# Contributing

**Requirements:** macOS 15.7+, Xcode 16.2+, [Homebrew](https://brew.sh)

```bash
brew install swiftformat
```

Code style is enforced by [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) via CI — rules are in `.swiftformat` at the project root.

---

# License

EdgeMark is licensed under the [GNU General Public License v3.0](LICENSE).

---

# Star History

<a href="https://star-history.com/#Ender-Wang/EdgeMark&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date" />
 </picture>
</a>
