<img src=".github/assets/EdgeMark.svg" alt="EdgeMark" width="128" align="left" />

<b><font>EdgeMark</font></b>

 Una aplicación nativa de macOS para tomar notas en Markdown con un panel lateral. Siempre a un borde de distancia.

<br clear="all" />

<p align="center">
  <a href="README.md">English</a> · <a href="README-zh-Hans.md">简体中文</a> · <a href="README-hi.md">हिन्दी</a> · <b>Español</b> · <a href="README-de.md">Deutsch</a>
</p>

<p align="center">
  <a href="https://github.com/Ender-Wang/EdgeMark/releases"><img src="https://img.shields.io/github/v/release/Ender-Wang/EdgeMark?label=Latest%20Release&color=green" alt="Latest Release" /></a>
  <a href="https://github.com/Ender-Wang/EdgeMark/releases"><img src="https://img.shields.io/github/downloads/Ender-Wang/EdgeMark/total?color=green" alt="Total Downloads" /></a>
  <br />
  <img src="https://img.shields.io/badge/Swift-6.2-orange?logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/macOS-15.7+-black?logo=apple" alt="macOS" />
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Ender-Wang/EdgeMark?color=blue" alt="License" /></a>
</p>

**Por qué existe EdgeMark:** [SideNotes](https://www.apptorium.com/sidenotes) logró la interacción perfecta: un panel de notas que se desliza desde el borde de la pantalla, siempre a un gesto de distancia. Pero es de código cerrado y de pago, sin forma de contribuir, personalizar o verificar qué hace con tus datos.

EdgeMark es la alternativa de código abierto: **ligero, con enfoque en Markdown**, y tuyo para inspeccionar, modificar y extender. Tus notas son archivos `.md` simples en disco — ábrelos en cualquier editor, sincronízalos con cualquier servicio, respáldalos como quieras.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/screenshot-dark.png" />
    <source media="(prefers-color-scheme: light)" srcset=".github/assets/screenshot-light.png" />
    <img alt="EdgeMark Screenshots" src=".github/assets/screenshot-light.png" />
  </picture>
</p>

# Instalación

```bash
brew install --cask ender-wang/tap/edgemark
```

O descarga el último `.dmg` desde [Releases](https://github.com/Ender-Wang/EdgeMark/releases), instálalo, y luego ejecuta este comando en Terminal:

```bash
xattr -cr /Applications/EdgeMark.app
```

---

# Características

🪟 **Panel Lateral**

- 🔲 Panel flotante sin bordes, de altura completa, siempre encima
- 🖥️ Funciona en todos los escritorios virtuales y junto a apps en pantalla completa
- ✨ Animación suave de deslizamiento o desvanecimiento (configurable) con activación por borde — mueve el ratón al borde de la pantalla para revelarlo
- 🖱️ Haz clic fuera, Escape, o desactivación automática al ocultar
- 📌 Fija el panel para mantenerlo abierto — sobrevive cambios de foco, salida del ratón y cambio de Espacios (ideal para copiar y pegar)
- 📐 Soporte multi-monitor con borde izquierdo o derecho configurable
- ↔️ Ancho ajustable — arrastra el borde interno para redimensionar, guardado entre reinicios
- 🎨 Tono del panel — elige de una paleta curada (System, Graphite, Slate, Sand, Sage, Rose)

✍️ **Edición Markdown**

- 👁️ Editor WYSIWYG nativo con TextKit 2 — impulsado por [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine), sin JavaScript ni WebKit
- 📝 Markdown completo: encabezados, negrita, cursiva, código, listas, listas de tareas, citas, enlaces, tablas, wiki-links
- 🖼️ Imágenes en línea — pega (`⌘V`) o arrastra para insertar; almacenadas como archivos de recursos junto a la nota
- ✅ Las tareas completadas se tachan automáticamente; desmarca para restaurar
- 📋 Botón de Copiar con un clic en bloques de código delimitados
- 🔴 Corrección ortográfica, gramatical y autocorrección nativas (diccionario del sistema macOS)
- ⚡ Comandos de barra (`/h1`, `/todo`, `/code`, `/quote`, `/table`, `/divider`, y más)
- ⌨️ Atajos de formato: `⌘B` negrita, `⌘I` cursiva, `⌘E` código en línea, `⌘K` enlace, `⇧⌘X` tachado
- 🔗 Haz clic en un enlace renderizado para abrirlo en el navegador
- 🔍 Buscar y reemplazar (`⌘F`)
- 🔤 Fuente y tamaño del editor personalizables — elige cualquier fuente instalada mediante el panel de fuentes del sistema con vista previa en vivo
- 🧮 Renderizado LaTeX — bloque (`$$...$$`) e inline (`$...$`) vía SwiftMath

🗂️ **Notas y Almacenamiento**

- 📄 Archivos `.md` simples sin encabezados inyectados — ábrelos en cualquier editor, sincronízalos con cualquier servicio; los metadatos viven en un sidecar oculto `.edgemark/meta.json`
- 📁 Organización por carpetas con arrastrar y soltar
- 🎨 Colores de carpeta personalizados — tiñe el ícono de cualquier carpeta con un color de la paleta mediante clic derecho → Folder Color
- 📂 Directorio de almacenamiento configurable
- 💾 Auto-guardado con anti-rebote de 1 segundo
- 🔍 La búsqueda muestra todas las notas ordenadas por última modificación cuando la consulta está vacía — un feed rápido de "notas recientes"
- 🏷️ Etiquetas de color estilo Finder (Rojo, Naranja, Amarillo, Verde, Azul, Púrpura, Gris) con nombres editables; múltiples etiquetas por nota
- 🎯 Filtro de etiquetas en la búsqueda — haz clic en los puntos de las etiquetas para reducir resultados, la selección múltiple actúa como OR, y se combina con la búsqueda de texto
- ☑️ Selección múltiple nativa de macOS — clic / ⇧-clic / ⌘-clic en filas, arrastrar para seleccionar en bloque, luego **Mover**, **Etiquetar** o **Eliminar** en lote desde el menú contextual; los conflictos en lote se encolan y resuelven
- 🔄 Sincronización de archivos externos — las ediciones de otras apps se detectan al abrir el panel; solicita cuando ambos lados cambiaron
- 🗑️ Papelera con purga automática de 30 días y vista previa de solo lectura
- 👁️ Vista previa al pasar el ratón — pasa el ratón sobre una nota o carpeta para previsualizar su contenido en un panel flotante junto a la lista; las vistas previas de notas renderizan Markdown completo con imágenes, las de carpetas muestran subcarpetas y todas las notas dentro

⌨️ **Atajos de Teclado**

- 🌐 Atajo global: `Ctrl+Shift+Space` alterna desde cualquier app (personalizable)
- 🎹 Atajos locales completamente personalizables — nueva nota, nueva carpeta, buscar, fijar, nota anterior/siguiente — todos reasignables en Ajustes con detección de conflictos
- ⏱️ Retardo de activación y zonas de exclusión de esquina configurables
- 🔑 Atajos del panel predeterminados: `⌘N` nueva nota, `⇧⌘N` nueva carpeta, `⌘F` buscar, `⌘P` fijar/desfijar
- 👁️ `Space` para Vista Rápida — selecciona una nota o carpeta y presiona `Space` para previsualizar; `↑↓` para navegar, `Space`/`ESC` para cerrar
- 👆 Desliza dos dedos a la derecha en el encabezado para retroceder (toggle y sensibilidad configurables)
- 👆 Desliza dos dedos a la izquierda/derecha en el editor o `⌘←`/`⌘→` para navegar entre notas en la carpeta actual

🔄 **Actualización Automática y CI/CD**

- 🔔 Verificación de actualizaciones en la app (GitHub Releases, límite de 24h)
- 📦 Descarga con barra de progreso, verificación SHA256, instalación y reinicio
- ⚙️ Pipeline de construcción con GitHub Actions (Release sin firmar, DMG, SHA256)
- 🍺 Instalación con Homebrew Cask

🌟 **Calidad de Vida**

- 🌗 Apariencia: Sistema, Claro u Oscuro
- 📌 Residente en la barra de menú (sin icono en el Dock)
- 🚀 Iniciar al iniciar sesión
- 📋 Copiar como Texto plano, Markdown o Texto enriquecido — sensible a la selección en el editor con menú contextual
- 🎨 Iconos SF Symbol en todos los menús contextuales
- 🔀 Transiciones de página suaves con dirección
- 🌍 Inglés + Chino simplificado + Hindi + Español + Alemán (basado en JSON, fácil de contribuir)

---

# Contribuir

Consulta [CONTRIBUTING.md](CONTRIBUTING.md) para una visión general de la arquitectura, árbol de código fuente, patrones clave, guía de localización y configuración de desarrollo.

---

# Licencia

EdgeMark está licenciado bajo la [GNU General Public License v3.0](LICENSE).

# Agradecimientos

EdgeMark está construido sobre estos proyectos de código abierto:

| Proyecto | Licencia | Descripción |
|---------|---------|-------------|
| [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine) | Apache 2.0 | Editor WYSIWYG con TextKit 2 / NSTextView — impulsa la experiencia de edición. Incluye [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) para resaltado de sintaxis en bloques de código y [SwiftMath](https://github.com/mgriebling/SwiftMath) para renderizado LaTeX. |
| [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) | MIT | Herramienta de formato de código usada en el pipeline de construcción |

---

# Historial de Estrellas

<a href="https://star-history.com/#Ender-Wang/EdgeMark&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date" />
 </picture>
</a>
