<img src=".github/assets/EdgeMark.svg" alt="EdgeMark" width="128" align="left" />

<b><font>EdgeMark</font></b>

 Eine native macOS-Seitenleisten-App für Markdown-Notizen. Immer eine Kante entfernt.

<br clear="all" />

<p align="center">
  <a href="README.md">English</a> · <a href="README-zh-Hans.md">简体中文</a> · <a href="README-hi.md">हिन्दी</a> · <a href="README-ES.md">Español</a> · <b>Deutsch</b>
</p>

<p align="center">
  <a href="https://github.com/Ender-Wang/EdgeMark/releases"><img src="https://img.shields.io/github/v/release/Ender-Wang/EdgeMark?label=Latest%20Release&color=green" alt="Latest Release" /></a>
  <a href="https://github.com/Ender-Wang/EdgeMark/releases"><img src="https://img.shields.io/github/downloads/Ender-Wang/EdgeMark/total?color=green" alt="Total Downloads" /></a>
  <br />
  <img src="https://img.shields.io/badge/Swift-6.2-orange?logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/macOS-15.7+-black?logo=apple" alt="macOS" />
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Ender-Wang/EdgeMark?color=blue" alt="License" /></a>
</p>

**Warum es EdgeMark gibt:** [SideNotes](https://www.apptorium.com/sidenotes) hat die Interaktion perfekt hingekriegt — ein Notizen-Panel, das von der Bildschirmkante hereinfliegt, immer eine Geste entfernt. Aber es ist Closed-Source und kostenpflichtig — ohne Möglichkeit beizutragen, anzupassen oder zu prüfen, was es mit deinen Daten macht.

EdgeMark ist die Open-Source-Alternative: **leichtgewichtig, Markdown-first**, und zum Inspectieren, Modifizieren und Erweitern deins. Deine Notizen sind einfache `.md`-Dateien auf der Platte — öffne sie in jedem Editor, synchronisiere sie mit jedem Dienst, sichere sie, wie du willst.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/screenshot-dark.png" />
    <source media="(prefers-color-scheme: light)" srcset=".github/assets/screenshot-light.png" />
    <img alt="EdgeMark Screenshots" src=".github/assets/screenshot-light.png" />
  </picture>
</p>

# Installation

```bash
brew install --cask ender-wang/tap/edgemark
```

Oder lade das neueste `.dmg` von [Releases](https://github.com/Ender-Wang/EdgeMark/releases) herunter, installiere es und führe danach diesen Befehl im Terminal aus:

```bash
xattr -cr /Applications/EdgeMark.app
```

---

# Funktionen

🪟 **Seitenleiste**

- 🔲 Rahmenloses, schwebendes Panel, volle Höhe, immer im Vordergrund
- 🖥️ Funktioniert auf jedem virtuellen Desktop und neben Vollbild-Apps
- ✨ Sanftes Rein-/Rausfliegen oder Fade-Animation (konfigurierbar) mit Kantenaktivierung — Maus an die Bildschirmkante bewegen, um es einzublenden
- 🖱️ Schließen per Klick außerhalb, Escape oder Auto-Ausblenden
- 📌 Anheften, um das Panel offen zu halten — übersteht Fokuswechsel, Maus-Austritt und Space-Wechsel (praktisch für Hin- und Her-Kopieren)
- 🔘 Edge-toggle-Modus — Kante berühren, um das Panel zu öffnen und beim Hin- und Her-Kopieren von Text offen zu halten, erneut berühren zum Schließen (kein ⌘P nötig); Auto-hide bleibt Standard
- 📐 Multi-Monitor-Support mit konfigurierbarer linker oder rechter Kante — nur die äußere Bildschirmkante löst aus, sodass die Maus zwischen Displays nicht versehentlich öffnet
- ↔️ Anpassbare Breite — innere Kante ziehen zum Ändern der Größe, wird über Neustarts hinweg gespeichert
- 🪟 Panel-Stil — Wechsel zwischen Transluzentem und Deckendem Panel-Hintergrund
- 🎨 Panel-Tönung — wähle aus einer kuratierten Palette (System, Graphit, Schiefer, Sand, Salbei, Rose)

✍️ **Markdown-Bearbeitung**

- 👁️ Nativer TextKit-2-WYSIWYG-Editor — angetrieben von [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine), ohne JavaScript oder WebKit
- 📝 Vollständiges Markdown: Überschriften, Fett, Kursiv, Code, Listen, Aufgabenlisten, Zitate, Links, Tabellen, Wiki-Links
- 🖼️ Inline-Bilder — einfügen (`⌘V`) oder hineinziehen; als mitgelagerte Asset-Dateien neben der Notiz gespeichert
- ✅ Abgehakte Aufgaben werden automatisch durchgestrichen; Abhacken aufheben, um wiederherzustellen
- ▫️ Eigene Task-Checkbox-Symbole — wähle die Form für `- [ ]`/`- [x]`-Aufgaben (Quadrat, Kreis, Raute, Schild, Dreieck, Stern, Sechseck, Herz) in den Einstellungen; nur Anzeige, Notizen bleiben Standard-Markdown
- 📋 Ein-Klick-Kopieren-Button auf Code-Blöcken
- 🔴 Native Rechtschreib-, Grammatikprüfung und Autokorrektur (macOS-Systemwörterbuch)
- ⚡ Slash-Befehle (`/h1`, `/todo`, `/code`, `/quote`, `/table`, `/divider` und mehr)
- ⌨️ Formatierungs-Kürzel: `⌘B` Fett, `⌘I` Kursiv, `⌘E` Inline-Code, `⌘K` Link, `⇧⌘X` Durchgestrichen
- 🔗 Auf einen gerenderten Link klicken, um ihn im Browser zu öffnen
- 🔍 Suchen & Ersetzen (`⌘F`)
- 🔤 Anpassbare Editor-Schriftart und -Größe — wähle jede installierte Schriftart über das System-Schriftfenster mit Live-Vorschau
- 🧮 LaTeX-Rendering — Block (`$$...$$`) und Inline (`$...$`) via SwiftMath

🗂️ **Notizen & Speicher**

- 📄 Einfache `.md`-Dateien ohne eingefügte Header — in jedem Editor öffnen, mit jedem Dienst synchronisieren; Metadaten leben in einer versteckten `.edgemark/meta.json`-Sidecar-Datei
- 📁 Ordnerbasierte Organisation mit Drag-and-Drop
- 🎨 Eigene Ordnerfarben — jedes Ordner-Icon über Rechtsklick → Ordnerfarbe mit einer Palettenfarbe tönen
- 📂 Mehrere Speicherorte — wechsle zwischen separaten Notizordnern (z. B. Arbeit und Privat) über die Menüleiste (ein schneller Wechsel, der beim Neustart zurückgesetzt wird) oder die Einstellungen; optional bei jedem App-Start einen wählen
- 💾 1-Sekunden-entbouncstes Auto-Speichern
- 🔍 Suche zeigt bei leerer Anfrage alle Notizen, sortiert nach zuletzt geändert — ein schneller „Zuletzt"-Feed
- 🏷️ Finder-artige Farb-Tags (Rot, Orange, Gelb, Grün, Blau, Lila, Grau) mit umbenennbaren Labels; mehrere Tags pro Notiz
- 🎯 Tag-Filter innerhalb der Suche — auf Tag-Punkte klicken, um einzugrenzen, Mehrfachauswahl wirkt als ODER, kombinierbar mit Textsuche
- ☑️ Native macOS-Mehrfachauswahl — Klick / ⇧-Klick / ⌘-Klick auf Zeilen, Auswahl-Rechteck ziehen, dann per Rechtsklick-Menü stapelweise **Verschieben**, **Taggen** oder **Löschen**; Konflikte im Stapel werden eingereiht und sind auflösbar
- 🔄 Externe Datei-Synchronisation — Änderungen anderer Apps werden beim Öffnen des Panels erkannt; bei beidseitigen Änderungen wird nachgefragt
- 🗑️ Papierkorb mit 30-Tage-Auto-Löschung und schreibgeschützter Vorschau
- 👁️ Drüberfahren-Vorschau — über einer Notiz- oder Ordnerzeile die Maus halten, um den Inhalt in einem schwebenden Panel neben der Liste anzuzeigen; Notiz-Vorschauen rendern vollständiges Markdown inklusive Bilder, Ordner-Vorschauen zeigen Unterordner und alle enthaltenen Notizen

⌨️ **Tastatur & Kürzel**

- 🌐 Globales Kürzel: `Ctrl+Shift+Space` schaltet aus jeder App um (anpassbar)
- 🎹 Voll anpassbare lokale Kürzel — neue Notiz, neuer Ordner, Suche, anheften, vorh./nächste Notiz — alle in den Einstellungen neu bindbar mit Konflikterkennung
- ⏱️ Konfigurierbare Aktivierungsverzögerung und Eckenausschlusszonen
- 🔑 Standard-Kürzel: `⌘N` neue Notiz, `⇧⌘N` neuer Ordner, `⌘F` Suche, `⌘P` anheften/lösen
- 👁️ `Leertaste` zur Quick-Look-Vorschau — Notiz oder Ordner auswählen und `Leertaste` drücken; `↑↓` blättern, `Leertaste`/`ESC` schließen
- 👆 Zweifinger-Wipe nach rechts auf dem Header, um zurückzugehen (umschaltbar mit Empfindlichkeit)
- 👆 Zweifinger-Wipe nach links/rechts im Editor oder `⌘←`/`⌘→`, um zwischen den Notizen im aktuellen Ordner zu wechseln

🔄 **Auto-Update & CI/CD**

- 🔔 In-App-Update-Prüfung (GitHub Releases, 24 h Drosselung)
- 📦 Download mit Fortschrittsbalken, SHA256-Verifikation, Installieren & Neustarten
- ⚙️ GitHub-Actions-Build-Pipeline (unsigniertes Release, DMG, SHA256)
- 🍺 Homebrew-Cask-Installation

🌟 **Quality of Life**

- 🌗 Erscheinungsbild-Override: System, Hell oder Dunkel
- 📌 Menüleisten-Resident (kein Dock-Icon)
- 🚀 Start beim Login
- 📋 Kopieren als Klartext, Markdown oder Rich Text — im Editor auswahlbewusst über Rechtsklick-Kontextmenü
- 🎨 SF-Symbol-Icons in allen Kontextmenüs
- 🔀 Sanfte, gerichtete Seitenübergänge
- 🌍 English + 简体中文 + हिन्दी + Español + Deutsch (JSON-basiert, einfach zu erweitern)

---

# Mitwirken

Architektur-Übersicht, Quell-Baum, wichtige Patterns, Lokalisierungs-Leitfaden und Entwicklungs-Setup findest du in [CONTRIBUTING.md](CONTRIBUTING.md).

---

# Lizenz

EdgeMark ist unter der [GNU General Public License v3.0](LICENSE) lizenziert.

# Danksagung

EdgeMark baut auf diesen Open-Source-Projekten auf:

| Projekt | Lizenz | Beschreibung |
|---------|---------|-------------|
| [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine) | Apache 2.0 | TextKit-2-/NSTextView-WYSIWYG-Markdown-Editor — treibt die Bearbeitung. Bündelt [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) für Code-Block-Syntax-Highlighting und [SwiftMath](https://github.com/mgriebling/SwiftMath) für LaTeX-Rendering. |
| [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) | MIT | Code-Formatierungswerkzeug in der Build-Pipeline |

---

# Star-Historie

<a href="https://star-history.com/#Ender-Wang/EdgeMark&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date" />
 </picture>
</a>
