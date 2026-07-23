# Contributing to EdgeMark

**Requirements:** macOS 15.7+, Xcode 16.2+, [Homebrew](https://brew.sh)

```bash
brew install swiftformat
```

Code style is enforced by [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) via CI — rules are in `.swiftformat` at the project root.

---

# Architecture

## Data Flow

```mermaid
graph TD
    EM["EdgeDetector<br/>(mouse monitor)"] -->|"edge hit"| SP["SidePanelController<br/>(NSWindow)"]
    HK["ShortcutManager<br/>(Carbon hotkey)"] -->|"toggle"| SP
    SP -->|"host"| SUI["SwiftUI Views"]

    SUI -->|"observe"| NS["NoteStore (@Observable)"]
    NS -->|"read / write"| FS["FileStorage"]
    FS -->|".md files"| Disk[("~/Documents/EdgeMark/")]
    FS -->|"metadata"| SC["SidecarStore<br/>(.edgemark/meta.json)"]

    SUI -->|"observe"| AS["AppSettings (@Observable)"]
    AS -->|"persist"| UD["UserDefaults"]

    SUI -->|"observe"| US["UpdateState (@Observable)"]
    US -->|"check · download · install"| UC["UpdateChecker / Installer"]
    UC -->|"GitHub API"| GH["GitHub Releases"]

    SUI -->|"embed"| ED["MarkdownEditorView<br/>(NativeTextViewWrapper)"]
    ED -->|"@Binding text"| NS
    ED -->|"onPasteImage / drag"| FS

    NS -.->|"log"| Log["OSLog"]
    ED -.->|"log"| Log
    SP -.->|"log"| Log
    Log -.->|"Console.app"| CA["Diagnostic Logs"]
```

## Source Tree

```
EdgeMark/
├── App/                            # Entry point + global state
│   ├── EdgeMarkApp.swift           #   @main, menu bar utility (LSUIElement)
│   ├── AppDelegate.swift           #   Lifecycle, sidecar migration, shortcut setup, switchRoot + menu-bar storage submenu
│   └── ContentView.swift           #   Navigation shell (folders → notes → editor)
│
├── Core/                           # Business logic — no SwiftUI imports
│   ├── Editor/
│   │   ├── MarkdownEditorView.swift      # SwiftUI wrapper around NativeTextViewWrapper
│   │   │                                #   (swift-markdown-engine). Heading strip,
│   │   │                                #   debounced save, image conversion layer,
│   │   │                                #   slash command integration.
│   │   ├── EditorConfigFactory.swift      # Shared MarkdownEditorConfiguration (insets,
│   │   │                                #   highlight/strikethrough extensions, task-checkbox
│   │   │                                #   symbols, image/syntax/latex services) for both editors
│   │   ├── ReadOnlyMarkdownView.swift    # Non-editable preview (trash)
│   │   ├── SlashCommandHandler.swift     # /h1, /todo, /code, /quote — NSTextView insertion
│   │   ├── SlashCommandPopup.swift       # Floating autocomplete panel
│   │   └── ImageDropHandler.swift        # Transparent NSView overlay for image drag-and-drop
│   ├── Settings/
│   │   └── AppSettings.swift       #   @Observable — sort order, date format, panel style/tint, spell-check prefs, task-checkbox symbols
│   ├── Shortcuts/
│   │   ├── ShortcutManager.swift   #   Carbon RegisterEventHotKey global shortcut
│   │   ├── ShortcutSettings.swift  #   6 customizable local shortcuts + storage roots (multi-location) + persistence
│   │   └── KeyCodeTranslator.swift #   Virtual key code → display string mapping
│   ├── Storage/
│   │   ├── NoteStore.swift         #   @Observable — note CRUD, trash, folders, tag filter, multi-selection + batch ops, move-conflict queue
│   │   ├── FileStorage.swift       #   Plain .md file I/O (no YAML); asset dir management
│   │   ├── SidecarStore.swift      #   In-memory .edgemark/meta.json store + persistence
│   │   ├── SidecarMigration.swift  #   One-time migration: strips YAML, restores timestamps
│   │   ├── Note.swift              #   Note model (id, title, body, timestamps, tags, savedAt)
│   │   ├── Folder.swift            #   Folder model
│   │   ├── TagColor.swift          #   Finder-style 7-color tag palette
│   │   └── TrashedFolder.swift     #   Trashed folder with expiry metadata
│   ├── Updates/
│   │   ├── UpdateChecker.swift     #   GitHub Releases API, version comparison
│   │   ├── UpdateDownloader.swift  #   URLSession delegate with progress tracking
│   │   ├── UpdateInstaller.swift   #   DMG mount → verify → copy → replace → restart
│   │   ├── UpdateModels.swift      #   GitHubRelease, UpdateProgress, UpdateError
│   │   ├── UpdateState.swift       #   @Observable — update UI state machine
│   │   └── ChecksumVerifier.swift  #   SHA256 verification via CryptoKit
│   └── Window/
│       ├── SidePanelController.swift     # NSWindowController — show/hide/animate
│       ├── EdgeDetector.swift            # Global mouse monitor → edge activation
│       ├── SettingsWindowController.swift # Settings window lifecycle
│       └── UpdateWindowController.swift  # Update window lifecycle
│
├── UI/                             # SwiftUI views
│   ├── EditorScreen.swift          #   Editor chrome (header, editor, footer)
│   ├── Navigation/
│   │   ├── HomeFolderView.swift    #   Folder list with create/rename/trash; hosts the ask-on-launch storage picker (in-card mode)
│   │   ├── NoteListView.swift      #   Note cards with search, sort, context menus
│   │   └── TrashView.swift         #   Trash browser with restore/delete/empty
│   ├── Components/
│   │   ├── ContentFooterBar.swift  #   Bottom toolbar (word count, copy format picker)
│   │   ├── DateFormatting.swift    #   Shared date → display string helpers
│   │   ├── EmptyStateView.swift    #   Icon + title + subtitle placeholder
│   │   ├── FontPickerButton.swift  #   NSFontPanel button with live changeFont(_:) preview
│   │   ├── HeaderIconButton.swift  #   Standard icon button with hover UX
│   │   ├── InlineRenameEditor.swift#   Inline text field with "Name taken" overlay
│   │   ├── MoveConflictAlerts.swift#   View extension: note + folder move conflict dialogs
│   │   ├── NSContextMenuModifier.swift  # NSMenu context menus with SF Symbol icons
│   │   ├── NoteCardView.swift      #   Note list row (title, preview, date)
│   │   ├── NoteListMenus.swift     #   Note/folder context menu builders (incl. Tags submenu)
│   │   ├── PageLayout.swift        #   Navigation page chrome (header + content + footer)
│   │   ├── PinButton.swift         #   Toggle for ShortcutSettings.isPanelPinned
│   │   ├── ShortcutRecorderView.swift   # Key capture field for shortcut settings
│   │   ├── SwipeDetectorView.swift #   NSView wrapper for two-finger swipe gestures
│   │   ├── TagDotsView.swift       #   Inline colored dots for note rows
│   │   ├── TagFilterBar.swift      #   Search-context tag filter strip
│   │   └── VisualEffectView.swift  #   NSVisualEffectView wrapper with optional tint sublayer
│   └── Settings/
│       ├── SettingsView.swift      #   Tab container (General, Behavior, Tags, Keyboard, About)
│       ├── GeneralSettingsTab.swift #   Appearance (incl. panel style/tint), editor font, language, multi-root storage list
│       ├── BehaviorSettingsTab.swift#   Panel position, edge activation, auto-hide
│       ├── TagsSettingsTab.swift   #   Rename color tag labels
│       ├── KeyboardSettingsTab.swift#   Global + 6 customizable local shortcut recorders
│       ├── AboutSettingsTab.swift   #   Version info, links, copyright
│       └── UpdateView.swift        #   Download progress, verify, install UI
│
├── Shared/Utils/
│   ├── L10n.swift                  #   JSON-based i18n runtime
│   ├── Log.swift                   #   OSLog — 6 categories
│   └── Debouncer.swift             #   Generic debounce utility
│
└── Resources/
    └── Locales/                    # i18n strings
        ├── en.json                 #   English
        ├── zh-Hans.json            #   Simplified Chinese
        ├── hi.json                 #   Hindi
        ├── es.json                 #   Spanish
        └── de.json                 #   German
```

## Key Patterns

| Pattern | Detail |
|---------|--------|
| **@Observable** | `NoteStore`, `AppSettings`, and `UpdateState` use the `@Observable` macro — views read properties directly, no `@Published` needed |
| **MainActor by default** | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. All types are `@MainActor` unless explicitly opted out |
| **AppKit + SwiftUI hybrid** | `NSHostingView` embeds SwiftUI inside a borderless `NSWindow`. Panel lifecycle managed by `SidePanelController` (AppKit), UI rendered by SwiftUI |
| **Native editor (swift-markdown-engine)** | `MarkdownEditorView` wraps `NativeTextViewWrapper` (NSViewRepresentable from swift-markdown-engine). Text flows via `@Binding<String>`. Heading stripping, image display-layer conversion (`![](path)` ↔ `![[path]]`), and save debouncing are handled in `MarkdownEditorView`. Both editors build their `MarkdownEditorConfiguration` via `EditorConfigFactory.makeEdgeMarkConfig` (shared insets, highlight/strikethrough extensions, task-checkbox symbols from `AppSettings.taskCheckboxPreset`, and image/syntax/latex services) — so previews match the editor. Changing the checkbox preset rebuilds the view via `.id()` because the engine's `updateNSView` doesn't sync `taskCheckbox` live. |
| **Sidecar metadata** | Notes are plain `.md` files with no headers. Metadata (UUID, timestamps, tags, trash state) lives in `.edgemark/meta.json` keyed by UUID. `SidecarMigration` strips YAML on first launch and restores original file timestamps. `savedAt` (last EdgeMark write) is the external-change sentinel; `modifiedAt` only advances on real content edits. |
| **Image asset co-location** | Images are stored in a hidden dot-prefix directory next to the note (`.NoteTitle/IMG-uuid.png`). Paths in `.md` files are standard `![](path)` — relative, readable in any external editor. The editor display layer converts them to `![[path]]` for rendering via `EmbeddedImageProvider`. `FileStorage` handles create/rename/move/trash/delete of asset dirs alongside their note. |
| **Carbon hotkeys** | Global shortcut uses `RegisterEventHotKey` (Carbon API) since `NSEvent.addGlobalMonitorForEvents` can't intercept key events |
| **Multiple storage locations** | `ShortcutSettings` owns a list of `StorageRoot`s + an `activeRootID` (persistent default) + an in-memory `sessionRootOverride` (menu-bar temporary switch, reverts on restart). `resolvedStorageDirectory` resolves session-override → active root → legacy → default. All storage (`FileStorage.rootURL`, `SidecarStore`, `.trash/`) reads the active root live, so flipping it re-points the whole layer — but in-memory `NoteStore`/`SidecarStore` must be reloaded (`AppDelegate.switchRoot(to:temporary:dismissPicker:)` is the single path: save dirty → set override/activeID → `SidecarStore.load` → `noteStore.loadFromDisk`, wrapped in `withAnimation` for a row crossfade). Per-root isolation: each root has its own sidecar, trash, and external-edit scope. |
| **Local shortcut monitor** | `SidePanelController` installs an `NSEvent.addLocalMonitorForEvents` that checks all six configurable local shortcuts at event time. Settings changes take effect immediately without re-registration. |
| **JSON i18n** | `L10n` loads locale JSON at runtime. Access: `l10n["key"]` or `l10n.t("key", arg1, arg2)` for interpolation |
| **OSLog diagnostics** | 6 categorized loggers (app, storage, window, shortcuts, navigation, updates). View in Console.app with `subsystem:io.github.ender-wang.EdgeMark` |
| **Move conflict queue** | Name-conflict pre-flight uses filesystem-aware helpers (`noteFilenameWouldCollide`, `folderWouldCollide`) that check both in-memory state and the destination on disk. Conflicts are queued, not singletons — `MoveConflictAlerts` reads the queue head and surfaces batch buttons (Keep Both All / Replace All / Skip / Cancel) when more than one is pending. Resolver branches handle orphan files / directories at the destination. |
| **DMG auto-update** | `UpdateChecker` queries GitHub Releases API. `UpdateInstaller`: mount DMG → verify bundle ID → copy → replace → restart |

---

# Localization

EdgeMark uses a custom JSON-based i18n system. Currently supported:

| Language | File | Status |
|----------|------|--------|
| English | `EdgeMark/Resources/Locales/en.json` | ✅ |
| Simplified Chinese | `EdgeMark/Resources/Locales/zh-Hans.json` | ✅ |
| Hindi | `EdgeMark/Resources/Locales/hi.json` | ✅ |
| Spanish | `EdgeMark/Resources/Locales/es.json` | ✅ |
| German | `EdgeMark/Resources/Locales/de.json` | ✅ |

## Contributing a Translation

1. Copy `EdgeMark/Resources/Locales/en.json`
2. Rename to your [BCP-47 language code](https://en.wikipedia.org/wiki/IETF_language_tag) (e.g. `ja.json`, `ko.json`, `fr.json`, `de.json`, `pt-BR.json`)
3. Translate the values — keep the JSON keys unchanged
4. (Optional but appreciated) Add a translated `README-<code>.md` (e.g. `README-ja.md`) modeled on `README.md`, and add your language to the switcher row at the top of every `README*.md` (`English · 简体中文 · हिन्दी · Español · Deutsch · …`), bolding the current language in each file.
5. Submit a PR

No code, project, or build-phase changes are needed. The Xcode project uses Xcode 16 file-system synchronized groups, so any `.json` you drop into the folder is auto-bundled. The language picker enumerates locale files at runtime, and `L10n` matches the system language by prefix — `pt-BR.json` will be selected for any `pt-*` user, and so on. Native-script display names (e.g. "English", "简体中文", "हिन्दी") come from `Locale.localizedString(forIdentifier:)`, so no language-label keys need to be maintained.

### What reviewers check on translation PRs

- All keys from `en.json` are present (no missing strings → no English fallback in the UI).
- No leftover English values where the language has a native term.
- Placeholders (`{0}`, `{1}`, …) preserved in the same order.
- No structural changes to keys, only values.

---

# Submitting a Pull Request

- Target the `main` branch.
- Run `swiftformat EdgeMark/` before pushing — CI fails on lint errors.
- **Do not modify** `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` in `EdgeMark.xcodeproj/project.pbxproj`. Releases are cut by the maintainer from `main`/`develop`; PRs that bump these values will fail the `check-version` CI step.
