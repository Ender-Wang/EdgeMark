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
const linkTextMark = Decoration.mark({ class: "cm-link-text" });
const linkUrlMark = Decoration.mark({ class: "cm-link-url" });
const blockquoteMark = Decoration.mark({ class: "cm-blockquote-line" });

// Heading marks indexed by level (1-based)
const headingMarks = [null, h1Mark, h2Mark, h3Mark, h4Mark, h5Mark, h6Mark];

// Checkbox widget for task lists
class CheckboxWidget extends WidgetType {
  constructor(checked) {
    super();
    this.checked = checked;
  }

  toDOM() {
    const cb = document.createElement("input");
    cb.type = "checkbox";
    cb.checked = this.checked;
    cb.classList.add("cm-task-checkbox");
    cb.setAttribute("aria-label", this.checked ? "checked" : "unchecked");
    return cb;
  }

  eq(other) {
    return this.checked === other.checked;
  }

  ignoreEvent() {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Build decorations from the Lezer syntax tree
// ---------------------------------------------------------------------------

function buildDecorations(view) {
  const { state } = view;
  const tree = syntaxTree(state);
  const decorations = [];

  // Determine which lines have a cursor so we can reveal markers there
  const cursorLines = new Set();
  for (const range of state.selection.ranges) {
    const startLine = state.doc.lineAt(range.from).number;
    const endLine = state.doc.lineAt(range.to).number;
    for (let ln = startLine; ln <= endLine; ln++) {
      cursorLines.add(ln);
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

      // Skip nodes entirely outside viewport for performance
      // (CM6 only parses visible + buffer, but tree may extend)

      // Determine if cursor is on any line this node spans
      const nodeStartLine = state.doc.lineAt(from).number;
      const isCursorLine = cursorLines.has(nodeStartLine);

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
            decorations.push(hideDecoration.range(headerMark.from, hideEnd));
          }
        }
        return false; // Don't descend into heading children for further processing
      }

      // ---- Emphasis (*text* or _text_) ----
      if (name === "Emphasis") {
        decorations.push(italicMark.range(from, to));
        if (!isCursorLine) {
          // Hide opening and closing markers (EmphasisMark children)
          hideChildMarkers(node, "EmphasisMark", state, decorations);
        }
        return false;
      }

      // ---- StrongEmphasis (**text** or __text__) ----
      if (name === "StrongEmphasis") {
        decorations.push(boldMark.range(from, to));
        if (!isCursorLine) {
          hideChildMarkers(node, "EmphasisMark", state, decorations);
        }
        return false;
      }

      // ---- Strikethrough (~~text~~) ----
      if (name === "Strikethrough") {
        decorations.push(strikeMark.range(from, to));
        if (!isCursorLine) {
          hideChildMarkers(node, "StrikethroughMark", state, decorations);
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
            decorations.push(hideDecoration.range(cm.from, cm.to));
          }
        }
        return false;
      }

      // ---- Links [text](url) ----
      if (name === "Link") {
        if (!isCursorLine) {
          // Find the child nodes
          let linkMark = null;
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
          // Style the link text
          // For [text](url): hide [ , ](url)
          if (linkStart) {
            decorations.push(hideDecoration.range(linkStart.from, linkStart.to));
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
              decorations.push(
                hideDecoration.range(marks[1].from, marks[3].to),
              );
            } else if (marks.length >= 2) {
              // Fallback: hide from ] to end of node
              decorations.push(hideDecoration.range(marks[1].from, to));
            }
          }
          // Style the visible text as a link
          if (linkStart && linkEnd) {
            decorations.push(
              linkTextMark.range(linkStart.to, linkEnd.from),
            );
          }
        } else {
          // Cursor on line — show everything, just style the text part
          let firstMark = null;
          let secondMark = null;
          let child = node.node.firstChild;
          while (child) {
            if (child.type.name === "LinkMark") {
              if (!firstMark) firstMark = child;
              else if (!secondMark) secondMark = child;
            }
            child = child.nextSibling;
          }
          if (firstMark && secondMark) {
            decorations.push(
              linkTextMark.range(firstMark.to, secondMark.from),
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
        const text = state.doc.sliceString(from, to);
        const isChecked = /\[[xX]\]/.test(text);
        if (!isCursorLine) {
          // Replace the [ ] / [x] with a checkbox widget
          decorations.push(
            Decoration.replace({
              widget: new CheckboxWidget(isChecked),
            }).range(from, to),
          );
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
          decorations.push(hideDecoration.range(from, hideEnd));
        }
      }

      // ---- FencedCode ---- (don't hide fences, just style)
      if (name === "FencedCode") {
        decorations.push(
          Decoration.mark({ class: "cm-fenced-code" }).range(from, to),
        );
        // Apply line decorations for the code block
        const startLine = state.doc.lineAt(from).number;
        const endLine = state.doc.lineAt(to).number;
        for (let ln = startLine; ln <= endLine; ln++) {
          const line = state.doc.line(ln);
          decorations.push(
            Decoration.line({ class: "cm-code-line" }).range(line.from),
          );
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
          // Hide the --- text; style the line with a bottom border via CSS
          decorations.push(hideDecoration.range(from, to));
        }
        return false;
      }
    },
  });

  // Sort decorations by from position (CM6 requires sorted range sets)
  decorations.sort((a, b) => a.from - b.from || a.startSide - b.startSide);
  return Decoration.set(decorations, true);
}

// Helper: hide all child nodes with a given type name
function hideChildMarkers(node, markerName, state, decorations) {
  let child = node.node.firstChild;
  while (child) {
    if (child.type.name === markerName) {
      decorations.push(hideDecoration.range(child.from, child.to));
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
      this.decorations = buildDecorations(view);
      this.cursorLineNum = view.state.doc.lineAt(view.state.selection.main.head).number;
    }

    update(update) {
      // Always rebuild on doc or viewport changes
      if (update.docChanged || update.viewportChanged) {
        const t0 = performance.now();
        this.decorations = buildDecorations(update.view);
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
          this.decorations = buildDecorations(update.view);
          const dt = performance.now() - t0;
          if (dt > 5) console.log(`[Perf] buildDecorations (line change): ${dt.toFixed(1)}ms`);
        }
      }
    }
  },
  {
    decorations: (v) => v.decorations,

    // Make cursor skip over hidden (replaced) ranges
    provide: (plugin) =>
      EditorView.atomicRanges.of((view) => {
        return view.plugin(plugin)?.decorations || Decoration.none;
      }),
  },
);

// ---------------------------------------------------------------------------
// Handle checkbox clicks — toggle [x] / [ ] in the document
// ---------------------------------------------------------------------------

const checkboxClickHandler = EditorView.domEventHandlers({
  click(event, view) {
    const target = event.target;
    if (
      target instanceof HTMLInputElement &&
      target.classList.contains("cm-task-checkbox")
    ) {
      event.preventDefault();
      // Find the position of this checkbox in the document
      const pos = view.posAtDOM(target);
      const line = view.state.doc.lineAt(pos);
      const text = line.text;
      // Find [ ] or [x] in the line
      const uncheckedMatch = text.match(/\[ \]/);
      const checkedMatch = text.match(/\[[xX]\]/);
      if (uncheckedMatch) {
        const idx = line.from + uncheckedMatch.index;
        view.dispatch({
          changes: { from: idx, to: idx + 3, insert: "[x]" },
        });
      } else if (checkedMatch) {
        const idx = line.from + checkedMatch.index;
        view.dispatch({
          changes: { from: idx, to: idx + 3, insert: "[ ]" },
        });
      }
      return true;
    }
    return false;
  },
});

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

export function wysiwyg() {
  return [wysiwygPlugin, checkboxClickHandler];
}
