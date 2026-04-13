/**
 * Custom WYSIWYG ViewPlugin for CodeMirror 6
 *
 * Hides markdown syntax markers (e.g. #, **, *, `, - ) and reveals them
 * when the cursor is on the same line (Obsidian-style live preview).
 *
 * Uses Lezer's markdown AST (no regex) and CM6's Decoration API with
 * EditorView.atomicRanges for proper cursor skip behavior.
 */

import { syntaxTree } from "@codemirror/language";
import {
  Decoration,
  EditorView,
  ViewPlugin,
  WidgetType,
} from "@codemirror/view";

// ---------------------------------------------------------------------------
// Decoration specs (reused across rebuilds)
// ---------------------------------------------------------------------------

const hideDecoration = Decoration.replace({});
const h1Mark = Decoration.mark({ class: "cm-heading cm-heading-1" });
const h2Mark = Decoration.mark({ class: "cm-heading cm-heading-2" });
const h3Mark = Decoration.mark({ class: "cm-heading cm-heading-3" });
const h4Mark = Decoration.mark({ class: "cm-heading cm-heading-4" });
const h5Mark = Decoration.mark({ class: "cm-heading cm-heading-5" });
const h6Mark = Decoration.mark({ class: "cm-heading cm-heading-6" });
const boldMark = Decoration.mark({ class: "cm-strong" });
const italicMark = Decoration.mark({ class: "cm-emphasis" });
const strikeMark = Decoration.mark({ class: "cm-strikethrough" });
const inlineCodeMark = Decoration.mark({ class: "cm-inline-code" });
function linkTextMark(url) {
  return Decoration.mark({ class: "cm-link-text", attributes: { "data-url": url, style: "cursor: pointer" } });
}

// Heading marks indexed by level (1-based)
const headingMarks = [null, h1Mark, h2Mark, h3Mark, h4Mark, h5Mark, h6Mark];

// Checkbox widget for task lists
class CheckboxWidget extends WidgetType {
  constructor(checked, pos) {
    super();
    this.checked = checked;
    this.pos = pos;
  }

  toDOM(view) {
    const cb = document.createElement("input");
    cb.type = "checkbox";
    cb.checked = this.checked;
    cb.classList.add("cm-task-checkbox");
    cb.setAttribute("aria-label", this.checked ? "checked" : "unchecked");
    cb.dataset.pos = this.pos;

    cb.addEventListener("mousedown", (e) => {
      e.preventDefault();   // prevent browser from toggling checked or moving focus
      e.stopPropagation();  // prevent CM6 from seeing the event and moving cursor
      const pos = parseInt(cb.dataset.pos, 10);
      const line = view.state.doc.lineAt(pos);
      const text = line.text;
      const uncheckedMatch = text.match(/\[ \]/);
      const checkedMatch = text.match(/\[[xX]\]/);

      if (uncheckedMatch) {
        // Checking: toggle [ ] → [x] and wrap task text with ~~
        const cbIdx = line.from + uncheckedMatch.index;
        const textAfterCb = text.slice(uncheckedMatch.index + 3);
        const textMatch = textAfterCb.match(/^(\s+)(.*?)(\s*)$/s);
        const changes = [{ from: cbIdx, to: cbIdx + 3, insert: "[x]" }];
        if (textMatch && textMatch[2].length > 0) {
          const textStart = cbIdx + 3 + textMatch[1].length;
          const textEnd = textStart + textMatch[2].length;
          // Only wrap if not already struck through
          if (!textMatch[2].startsWith("~~") || !textMatch[2].endsWith("~~")) {
            changes.push({ from: textStart, to: textEnd, insert: "~~" + textMatch[2] + "~~" });
          }
        }
        view.dispatch({ changes });
      } else if (checkedMatch) {
        // Unchecking: toggle [x] → [ ] and remove ~~ from task text
        const cbIdx = line.from + checkedMatch.index;
        const textAfterCb = text.slice(checkedMatch.index + 3);
        const textMatch = textAfterCb.match(/^(\s+)(~~)?(.*?)(~~)?(\s*)$/s);
        const changes = [{ from: cbIdx, to: cbIdx + 3, insert: "[ ]" }];
        if (textMatch && textMatch[3].length > 0 && textMatch[2] && textMatch[4]) {
          const spacer = textMatch[1].length;
          const textStart = cbIdx + 3 + spacer;
          const fullLen = textMatch[2].length + textMatch[3].length + textMatch[4].length;
          changes.push({ from: textStart, to: textStart + fullLen, insert: textMatch[3] });
        }
        view.dispatch({ changes });
      }
    });

    return cb;
  }

  updateDOM(dom) {
    dom.checked = this.checked;
    dom.dataset.pos = this.pos;
    dom.setAttribute("aria-label", this.checked ? "checked" : "unchecked");
    return true;
  }

  eq(other) {
    return this.checked === other.checked && this.pos === other.pos;
  }

  ignoreEvent() {
    return true;
  }
}

// Image widget — renders ![alt](src) as an inline <img> off cursor
class ImageWidget extends WidgetType {
  constructor(src, alt) {
    super();
    this.src = src;
    this.alt = alt;
  }

  toDOM() {
    const img = document.createElement("img");
    img.src = this.src;  // already an absolute URL, resolved in buildDecorations
    img.alt = this.alt;
    img.className = "cm-image";
    img.draggable = false;
    img.onerror = () => img.classList.add("cm-image-broken");
    return img;
  }

  eq(other) {
    return other.src === this.src && other.alt === this.alt;
  }

  get estimatedHeight() {
    return 200;
  }

  ignoreEvent() {
    return true;
  }
}

// Copy button widget — overlays the top-right of a fenced code block
class CopyButtonWidget extends WidgetType {
  constructor(code) {
    super();
    this.code = code;
  }

  toDOM() {
    const btn = document.createElement("button");
    btn.className = "cm-copy-button";
    btn.setAttribute("title", "Copy code");
    btn.textContent = "Copy";
    btn.addEventListener("mousedown", (e) => {
      e.preventDefault();
      e.stopPropagation();
      navigator.clipboard.writeText(this.code).then(() => {
        btn.textContent = "Copied!";
        setTimeout(() => { btn.textContent = "Copy"; }, 1500);
      }).catch(() => {
        // Fallback for environments without clipboard API
        const ta = document.createElement("textarea");
        ta.value = this.code;
        document.body.appendChild(ta);
        ta.select();
        document.execCommand("copy");
        document.body.removeChild(ta);
        btn.textContent = "Copied!";
        setTimeout(() => { btn.textContent = "Copy"; }, 1500);
      });
    });
    return btn;
  }

  eq(other) { return this.code === other.code; }
  ignoreEvent() { return true; }
}

// Table widget — renders GFM table as an HTML <table> off cursor
class TableWidget extends WidgetType {
  constructor(rows) {
    super();
    this.rows = rows; // [{cells: string[], isHeader: bool}]
  }

  toDOM() {
    const wrap = document.createElement("div");
    wrap.className = "cm-table-wrap";
    const table = document.createElement("table");
    table.className = "cm-table";
    for (const row of this.rows) {
      const tr = table.insertRow();
      for (const cell of row.cells) {
        const td = document.createElement(row.isHeader ? "th" : "td");
        td.className = row.isHeader ? "cm-table-th" : "cm-table-td";
        td.textContent = cell;
        tr.appendChild(td);
      }
    }
    wrap.appendChild(table);
    return wrap;
  }

  eq(other) {
    return JSON.stringify(this.rows) === JSON.stringify(other.rows);
  }

  get estimatedHeight() {
    return this.rows.length * 32;
  }

  ignoreEvent() { return false; }
}

function parseTableRows(text) {
  const lines = text.split("\n").filter((l) => l.trim());
  const rows = [];
  let isFirst = true;
  for (const line of lines) {
    // Skip separator lines (e.g. | --- | :---: | ---: |)
    if (/^\s*\|?[\s|:\-]+\|?\s*$/.test(line) && line.includes("-")) continue;
    const parts = line.split("|");
    // Strip outer empty parts from leading/trailing pipes
    const cells = (parts[0].trim() === "" ? parts.slice(1) : parts)
      .filter((_, i, arr) => !(i === arr.length - 1 && arr[arr.length - 1].trim() === ""))
      .map((c) => c.trim());
    if (cells.length > 0) {
      rows.push({ cells, isHeader: isFirst });
      isFirst = false;
    }
  }
  return rows;
}

// ---------------------------------------------------------------------------
// Build decorations from the Lezer syntax tree
// ---------------------------------------------------------------------------

function buildDecorations(view) {
  const { state } = view;
  const tree = syntaxTree(state);
  const decorations = [];
  // Track replace decorations separately — only these should be atomic.
  // Mark decorations (styling) must NOT be atomic or backspace deletes whole nodes.
  const atomicDecorations = [];

  // Determine which lines have a cursor so we can reveal markers there
  const cursorLines = new Set();
  for (const range of state.selection.ranges) {
    const startLine = state.doc.lineAt(range.from).number;
    const endLine = state.doc.lineAt(range.to).number;
    for (let ln = startLine; ln <= endLine; ln++) {
      cursorLines.add(ln);
    }
  }

  // ---- Pre-scan: detect GFM tables by line content ----
  // We must do this BEFORE tree.iterate so we can skip table lines there
  // (Lezer doesn't know about tables — it parses them as plain paragraphs,
  //  and tree.iterate would add inline decorations that overlap our replace).
  const tableLineSet = new Set(); // line numbers covered by tables
  {
    const numLines = state.doc.lines;
    let i = 1;
    while (i <= numLines) {
      const line = state.doc.line(i);
      if (!line.text.includes("|")) { i++; continue; }
      if (i + 1 > numLines) { i++; continue; }
      const sepLine = state.doc.line(i + 1);
      if (!/^\s*\|?[\s|:\-]+\|?\s*$/.test(sepLine.text) || !sepLine.text.includes("-")) {
        i++; continue;
      }
      // Found a table — collect consecutive pipe-containing lines
      const tableLines = [line.text];
      let j = i + 1;
      while (j <= numLines) {
        const nl = state.doc.line(j);
        if (!nl.text.includes("|")) break;
        tableLines.push(nl.text);
        j++;
      }
      const startLn = i;
      const endLn = j - 1;
      const cursorInTable = Array.from(
        { length: endLn - startLn + 1 }, (_, k) => startLn + k,
      ).some((ln) => cursorLines.has(ln));
      if (!cursorInTable) {
        for (let ln = startLn; ln <= endLn; ln++) tableLineSet.add(ln);
        const rows = parseTableRows(tableLines.join("\n"));
        if (rows.length > 0) {
          // Line 1: replace with the full rendered table widget (single-line range)
          const firstLine = state.doc.line(startLn);
          decorations.push(
            Decoration.replace({ widget: new TableWidget(rows) }).range(firstLine.from, firstLine.to),
          );
          // Lines 2+: hide content and collapse the line div to zero height
          for (let ln = startLn + 1; ln <= endLn; ln++) {
            const hideLine = state.doc.line(ln);
            if (hideLine.from < hideLine.to) {
              decorations.push(Decoration.replace({}).range(hideLine.from, hideLine.to));
            }
            decorations.push(
              Decoration.line({ class: "cm-table-hidden-line" }).range(hideLine.from),
            );
          }
        }
      }
      i = j;
    }
  }

  // Only iterate visible viewport range (+ buffer) for performance
  const { from: vpFrom, to: vpTo } = view.viewport;

  tree.iterate({
    from: vpFrom,
    to: vpTo,
    enter(node) {
      const { from, to } = node;
      const name = node.type.name;

      // Skip nodes that fall inside a table region (already handled by pre-scan)
      if (tableLineSet.size > 0 && tableLineSet.has(state.doc.lineAt(from).number)) {
        return false;
      }

      // Determine if cursor is on any line this node spans.
      // Require editor focus — unfocused editor renders all lines in preview mode.
      const nodeStartLine = state.doc.lineAt(from).number;
      const isCursorLine = view.hasFocus && cursorLines.has(nodeStartLine);

      // ---- ATX Headings (#, ##, ### ...) ----
      if (name.startsWith("ATXHeading") && !name.includes("Mark")) {
        // The heading node spans the full line.
        // Child "HeaderMark" contains the # characters.
        const level = parseInt(name.replace("ATXHeading", ""), 10);
        const mark = headingMarks[level] || headingMarks[6];

        // Apply heading style to content (the whole heading node)
        if (mark) {
          decorations.push(mark.range(from, to));
        }

        // Hide the "# " prefix if cursor is NOT on this line
        if (!isCursorLine) {
          const headerMark = node.node.getChild("HeaderMark");
          if (headerMark) {
            // Hide from headerMark start to after the space following it
            let hideEnd = headerMark.to;
            const text = state.doc.sliceString(headerMark.to, headerMark.to + 1);
            if (text === " ") hideEnd++;
            const range = hideDecoration.range(headerMark.from, hideEnd);
            decorations.push(range);
            atomicDecorations.push(range);
          }
        }
        return false; // Don't descend into heading children for further processing
      }

      // ---- Emphasis (*text* or _text_) ----
      if (name === "Emphasis") {
        decorations.push(italicMark.range(from, to));
        if (!isCursorLine) {
          // Hide opening and closing markers (EmphasisMark children)
          hideChildMarkers(node, "EmphasisMark", state, decorations, atomicDecorations);
        }
        return false;
      }

      // ---- StrongEmphasis (**text** or __text__) ----
      if (name === "StrongEmphasis") {
        decorations.push(boldMark.range(from, to));
        if (!isCursorLine) {
          hideChildMarkers(node, "EmphasisMark", state, decorations, atomicDecorations);
        }
        return false;
      }

      // ---- Strikethrough (~~text~~) ----
      if (name === "Strikethrough") {
        decorations.push(strikeMark.range(from, to));
        if (!isCursorLine) {
          hideChildMarkers(node, "StrikethroughMark", state, decorations, atomicDecorations);
        }
        return false;
      }

      // ---- InlineCode (`code`) ----
      if (name === "InlineCode") {
        decorations.push(inlineCodeMark.range(from, to));
        if (!isCursorLine) {
          // Hide opening and closing backtick(s)
          const codeMarks = [];
          let child = node.node.firstChild;
          while (child) {
            if (child.type.name === "CodeMark") {
              codeMarks.push(child);
            }
            child = child.nextSibling;
          }
          for (const cm of codeMarks) {
            const range = hideDecoration.range(cm.from, cm.to);
            decorations.push(range);
            atomicDecorations.push(range);
          }
        }
        return false;
      }

      // ---- Links [text](url) ----
      if (name === "Link") {
        if (!isCursorLine) {
          // Find the child nodes
          let url = null;
          let linkStart = null;
          let linkEnd = null;
          let child = node.node.firstChild;
          while (child) {
            if (child.type.name === "LinkMark") {
              if (!linkStart) linkStart = child;
              linkEnd = child;
            }
            if (child.type.name === "URL") url = child;
            child = child.nextSibling;
          }
          // Only hide markup for proper [text](url) links — bare [text] passes through
          if (linkStart && url) {
            const range = hideDecoration.range(linkStart.from, linkStart.to);
            decorations.push(range);
            atomicDecorations.push(range);
          }
          // Hide from ]( to ) inclusive
          if (linkEnd && url) {
            // The "](url)" portion: from the "]" linkEnd.from to the closing ")" which is at `to`
            // Actually, need to find the ](url) portion more carefully
            // Structure: LinkMark([) ... LinkMark(]) LinkMark(() URL LinkMark())
            const marks = [];
            child = node.node.firstChild;
            while (child) {
              if (child.type.name === "LinkMark") marks.push(child);
              child = child.nextSibling;
            }
            // marks[0] = [, marks[1] = ], marks[2] = (, marks[3] = )
            if (marks.length >= 4) {
              const range = hideDecoration.range(marks[1].from, marks[3].to);
              decorations.push(range);
              atomicDecorations.push(range);
            } else if (marks.length >= 2) {
              // Fallback: hide from ] to end of node
              const range = hideDecoration.range(marks[1].from, to);
              decorations.push(range);
              atomicDecorations.push(range);
            }
          }
          // Style the visible text as a link (only when URL exists — bare [text] is not a link)
          if (linkStart && linkEnd && url) {
            const urlText = view.state.doc.sliceString(url.from, url.to);
            decorations.push(
              linkTextMark(urlText).range(linkStart.to, linkEnd.from),
            );
          }
        } else {
          // Cursor on line — show raw markdown, style the text part only if it's a proper link
          let firstMark = null;
          let secondMark = null;
          let urlNode = null;
          let child = node.node.firstChild;
          while (child) {
            if (child.type.name === "LinkMark") {
              if (!firstMark) firstMark = child;
              else if (!secondMark) secondMark = child;
            }
            if (child.type.name === "URL") urlNode = child;
            child = child.nextSibling;
          }
          if (firstMark && secondMark && urlNode) {
            const urlText = view.state.doc.sliceString(urlNode.from, urlNode.to);
            decorations.push(
              linkTextMark(urlText).range(firstMark.to, secondMark.from),
            );
          }
        }
        return false;
      }

      // ---- BulletList / OrderedList markers ----
      if (name === "ListMark") {
        if (!isCursorLine) {
          // Don't hide list markers — they're structural. Instead, style them.
          // Actually, we keep list markers visible (like Obsidian does).
        }
      }

      // ---- Task list items: - [ ] or - [x] ----
      if (name === "TaskMarker") {
        const taskText = state.doc.sliceString(from, to);
        const isChecked = /\[[xX]\]/.test(taskText);
        const line = state.doc.lineAt(from);
        if (!isCursorLine) {
          // Hide the leading "- " with a non-atomic mark (keeps text in layout flow)
          const markerMatch = line.text.match(/^(\s*[-*+]\s+)/);
          if (markerMatch) {
            decorations.push(
              Decoration.mark({ class: "cm-task-list-marker" }).range(
                line.from, line.from + markerMatch[0].length,
              ),
            );
          }
          // Replace [ ] / [x] with checkbox widget
          const cbRange = Decoration.replace({
            widget: new CheckboxWidget(isChecked, from),
          }).range(from, to);
          decorations.push(cbRange);
          atomicDecorations.push(cbRange);
        }
        // Dim checked task text — strikethrough comes from the ~~ Strikethrough node
        if (isChecked && !isCursorLine) {
          const textStart = to + (state.doc.sliceString(to, to + 1) === " " ? 1 : 0);
          if (textStart < line.to) {
            decorations.push(
              Decoration.mark({ class: "cm-task-checked" }).range(textStart, line.to),
            );
          }
        }
      }

      // ---- Blockquote ----
      if (name === "Blockquote") {
        // Apply blockquote styling to each line
        const startLine = state.doc.lineAt(from).number;
        const endLine = state.doc.lineAt(to).number;
        for (let ln = startLine; ln <= endLine; ln++) {
          const line = state.doc.line(ln);
          decorations.push(
            Decoration.line({ class: "cm-blockquote" }).range(line.from),
          );
        }
        // Don't hide ">" markers — let children handle individual QuoteMark nodes
      }

      if (name === "QuoteMark") {
        if (!isCursorLine) {
          // Hide the "> " prefix
          let hideEnd = to;
          const after = state.doc.sliceString(to, to + 1);
          if (after === " ") hideEnd++;
          const range = hideDecoration.range(from, hideEnd);
          decorations.push(range);
          atomicDecorations.push(range);
        }
      }

      // ---- FencedCode ---- (hide fence marks off cursor, style interior)
      if (name === "FencedCode") {
        decorations.push(
          Decoration.mark({ class: "cm-fenced-code" }).range(from, to),
        );
        const startLine = state.doc.lineAt(from).number;
        const endLine = state.doc.lineAt(to).number;
        for (let ln = startLine; ln <= endLine; ln++) {
          const line = state.doc.line(ln);
          const isFirst = ln === startLine;
          const isLast = ln === endLine;
          const cls = ["cm-code-line", isFirst ? "cm-code-line-first" : "", isLast ? "cm-code-line-last" : ""]
            .filter(Boolean).join(" ");
          decorations.push(
            Decoration.line({ class: cls }).range(line.from),
          );
        }
        // Hide ``` fence lines when cursor is not anywhere inside this code block
        const cursorInBlock = Array.from(
          { length: endLine - startLine + 1 },
          (_, i) => startLine + i,
        ).some((ln) => cursorLines.has(ln));
        if (!cursorInBlock) {
          let codeText = "";
          let child = node.node.firstChild;
          while (child) {
            if (child.type.name === "CodeMark") {
              const fenceLine = state.doc.line(state.doc.lineAt(child.from).number);
              decorations.push(
                Decoration.mark({ class: "cm-fence-hidden" }).range(fenceLine.from, fenceLine.to),
              );
            }
            if (child.type.name === "CodeText") {
              codeText = state.doc.sliceString(child.from, child.to);
            }
            child = child.nextSibling;
          }
          // Copy button floats right inside the (hidden) opening fence line
          const openFenceLine = state.doc.line(startLine);
          decorations.push(
            Decoration.widget({ widget: new CopyButtonWidget(codeText), side: 1 }).range(openFenceLine.from),
          );
        }
        return false;
      }

      // ---- Image ---- (always render as <img> widget — raw path never shown)
      if (name === "Image") {
        let urlNode = null;
        let altStart = -1;
        let altEnd = -1;
        let child = node.node.firstChild;
        // Lezer Image: ImageMark(!) LinkMark([) <text> LinkMark(]) LinkMark(() URL LinkMark())
        let linkMarkCount = 0;
        while (child) {
          if (child.type.name === "URL") urlNode = child;
          if (child.type.name === "LinkMark") {
            linkMarkCount++;
            if (linkMarkCount === 1) altStart = child.to; // after "["
            if (linkMarkCount === 2) altEnd = child.from;  // before "]"
          }
          child = child.nextSibling;
        }
        if (urlNode) {
          let src = state.doc.sliceString(urlNode.from, urlNode.to);
          // Resolve relative paths (.NoteTitle/IMG-uuid.png) to absolute file:// URLs.
          // Absolute URLs (file://, https://) pass through unchanged.
          if (!src.includes("://") && window.editorNoteBaseURL) {
            src = window.editorNoteBaseURL + src;
          }
          const alt = altStart >= 0 && altEnd > altStart
            ? state.doc.sliceString(altStart, altEnd)
            : "";
          const imgRange = Decoration.replace({
            widget: new ImageWidget(src, alt),
          }).range(from, to);
          decorations.push(imgRange);
          atomicDecorations.push(imgRange);
        }
        return false;
      }

      // ---- HorizontalRule ---- (style the --- line)
      if (name === "HorizontalRule") {
        decorations.push(
          Decoration.line({ class: "cm-hr" }).range(
            state.doc.lineAt(from).from,
          ),
        );
        if (!isCursorLine) {
          // Hide the --- text with a non-atomic mark so it stays in layout flow
          // (atomic replace shifts CM6's line coordinate cache for all lines below)
          decorations.push(
            Decoration.mark({ class: "cm-hr-text" }).range(from, to),
          );
        }
        return false;
      }
    },
  });

  // Sort decorations by from position (CM6 requires sorted range sets)
  decorations.sort((a, b) => a.from - b.from || a.to - b.to);
  atomicDecorations.sort((a, b) => a.from - b.from || a.to - b.to);
  try {
    return {
      all: Decoration.set(decorations, true),
      atomic: Decoration.set(atomicDecorations, true),
    };
  } catch (e) {
    console.error("[WYSIWYG] Decoration.set failed:", e);
    console.error("[WYSIWYG] decorations count:", decorations.length, "atomics:", atomicDecorations.length);
    // Log problematic decorations
    for (let i = 0; i < decorations.length; i++) {
      const d = decorations[i];
      console.log(`  dec[${i}]: from=${d.from} to=${d.to}`);
    }
    return { all: Decoration.none, atomic: Decoration.none };
  }
}

// Helper: hide all child nodes with a given type name
function hideChildMarkers(node, markerName, _state, decorations, atomicDecorations) {
  let child = node.node.firstChild;
  while (child) {
    if (child.type.name === markerName) {
      const range = hideDecoration.range(child.from, child.to);
      decorations.push(range);
      atomicDecorations.push(range);
    }
    child = child.nextSibling;
  }
}

// ---------------------------------------------------------------------------
// ViewPlugin
// ---------------------------------------------------------------------------

const wysiwygPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) {
      const result = buildDecorations(view);
      this.decorations = result.all;
      this.atomicDecorations = result.atomic;
      this.cursorLineNum = view.state.doc.lineAt(view.state.selection.main.head).number;
    }

    update(update) {
      // Always rebuild on doc, viewport, or focus changes
      if (update.docChanged || update.viewportChanged || update.focusChanged) {
        const t0 = performance.now();
        const result = buildDecorations(update.view);
        this.decorations = result.all;
        this.atomicDecorations = result.atomic;
        this.cursorLineNum = update.view.state.doc.lineAt(update.view.state.selection.main.head).number;
        const dt = performance.now() - t0;
        if (dt > 5) console.log(`[Perf] buildDecorations (doc/vp): ${dt.toFixed(1)}ms`);
        return;
      }
      // On selection change, only rebuild if cursor moved to a different line
      if (update.selectionSet) {
        const newLine = update.view.state.doc.lineAt(update.view.state.selection.main.head).number;
        if (newLine !== this.cursorLineNum) {
          const t0 = performance.now();
          this.cursorLineNum = newLine;
          const result = buildDecorations(update.view);
          this.decorations = result.all;
          this.atomicDecorations = result.atomic;
          const dt = performance.now() - t0;
          if (dt > 5) console.log(`[Perf] buildDecorations (line change): ${dt.toFixed(1)}ms`);
        }
      }
    }
  },
  {
    decorations: (v) => v.decorations,

    // Only make hidden (replaced) ranges atomic — NOT style marks.
    // This prevents backspace from deleting entire styled nodes (e.g. headings).
    provide: (plugin) =>
      EditorView.atomicRanges.of((view) => {
        return view.plugin(plugin)?.atomicDecorations || Decoration.none;
      }),

    // Cmd+Click on a rendered link → open URL in browser
    eventHandlers: {
      mousedown(e) {
        if (!e.metaKey) return false;
        const target = e.target.closest(".cm-link-text");
        if (!target) return false;
        const url = target.dataset.url;
        if (!url) return false;
        e.preventDefault();
        window.webkit?.messageHandlers?.editor?.postMessage({ action: "openLink", url });
        return true;
      },
    },
  },
);

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

export function wysiwyg() {
  return [wysiwygPlugin];
}
