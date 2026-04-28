/**
 * CodeMirror 6 editor setup + WKWebView bridge
 *
 * Loaded as IIFE bundle in editor.html. Communicates with Swift via:
 *   Swift → JS: window.editorAPI.setContent(), insertText(), focus(), etc.
 *   JS → Swift: window.webkit.messageHandlers.editor.postMessage(...)
 */

import {
  keymap,
  EditorView,
  highlightActiveLine,
  drawSelection,
  placeholder as placeholderExt,
} from "@codemirror/view";
import { EditorState, Prec, StateEffect, StateField } from "@codemirror/state";
import { Decoration } from "@codemirror/view";
import {
  defaultKeymap,
  history,
  historyKeymap,
  indentWithTab,
} from "@codemirror/commands";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import {
  bracketMatching,
} from "@codemirror/language";
import { searchKeymap, highlightSelectionMatches } from "@codemirror/search";
import { wysiwyg } from "./wysiwyg.js";

// ---------------------------------------------------------------------------
// List continuation keymap
// ---------------------------------------------------------------------------

function listContinuation({ state, dispatch }) {
  const { from } = state.selection.main;
  const line = state.doc.lineAt(from);
  const text = line.text;

  // Horizontal rule: Enter on --- line moves cursor below
  if (/^[-*_]{3,}$/.test(text.trim())) {
    dispatch({
      changes: { from: line.to, to: line.to, insert: "\n" },
      selection: { anchor: line.to + 1 },
    });
    return true;
  }

  // Task list: "  - [ ] content" or "  - [x] content"
  const taskMatch = text.match(/^(\s*)([-*+])\s+\[([xX ])\]\s?(.*)/);
  if (taskMatch) {
    const leadingSpace = taskMatch[1];
    const bullet = taskMatch[2];
    const content = taskMatch[4];
    if (content.trim() === "") {
      // Empty task line → clear it
      dispatch({
        changes: { from: line.from, to: line.to, insert: "" },
        selection: { anchor: line.from },
      });
      return true;
    }
    const insert = `\n${leadingSpace}${bullet} [ ] `;
    dispatch({
      changes: { from, to: from, insert },
      selection: { anchor: from + insert.length },
    });
    return true;
  }

  // Unordered list: "  - content" or "  * content" or "  + content"
  const ulMatch = text.match(/^(\s*[-*+])\s(.*)/);
  if (ulMatch) {
    const marker = ulMatch[1];
    const content = ulMatch[2];
    if (content.trim() === "") {
      dispatch({
        changes: { from: line.from, to: line.to, insert: "" },
        selection: { anchor: line.from },
      });
      return true;
    }
    const insert = `\n${marker} `;
    dispatch({
      changes: { from, to: from, insert },
      selection: { anchor: from + insert.length },
    });
    return true;
  }

  // Ordered list: "  1. content"
  const olMatch = text.match(/^(\s*)(\d+)\.\s(.*)/);
  if (olMatch) {
    const indent = olMatch[1];
    const num = parseInt(olMatch[2], 10);
    const content = olMatch[3];
    if (content.trim() === "") {
      dispatch({
        changes: { from: line.from, to: line.to, insert: "" },
        selection: { anchor: line.from },
      });
      return true;
    }
    const insert = `\n${indent}${num + 1}. `;
    dispatch({
      changes: { from, to: from, insert },
      selection: { anchor: from + insert.length },
    });
    return true;
  }

  return false;
}

const listContinuationKeymap = Prec.highest(keymap.of([
  { key: "Enter", run: listContinuation },
]));

// ---------------------------------------------------------------------------
// Markdown formatting shortcuts
// ---------------------------------------------------------------------------

/**
 * Wrap the selection with a symmetric marker (e.g. ** for bold).
 * - With selection: wrap it → **selection**
 * - Empty selection: insert markers with cursor between → **|**
 * - Already wrapped: unwrap (toggle off)
 */
function wrapSelection(marker) {
  return ({ state, dispatch }) => {
    const { from, to } = state.selection.main;
    const len = marker.length;

    // Check if selection is already wrapped — toggle off
    if (from >= len && to + len <= state.doc.length) {
      const before = state.doc.sliceString(from - len, from);
      const after = state.doc.sliceString(to, to + len);
      if (before === marker && after === marker) {
        dispatch({
          changes: [
            { from: from - len, to: from, insert: "" },
            { from: to, to: to + len, insert: "" },
          ],
          selection: { anchor: from - len, head: to - len },
        });
        return true;
      }
    }

    if (from === to) {
      // Empty selection: insert markers with cursor between
      dispatch({
        changes: { from, to, insert: marker + marker },
        selection: { anchor: from + len },
      });
    } else {
      // Wrap selection
      const text = state.doc.sliceString(from, to);
      dispatch({
        changes: { from, to, insert: marker + text + marker },
        selection: { anchor: from + len, head: to + len },
      });
    }
    return true;
  };
}

function insertLink({ state, dispatch }) {
  const { from, to } = state.selection.main;
  if (from === to) {
    // Empty selection: insert [](url) and select "url" so user types the URL immediately
    const insert = "[](url)";
    dispatch({
      changes: { from, to, insert },
      selection: { anchor: from + 3, head: from + 6 }, // select "url"
    });
  } else {
    // Wrap selection as link text, pre-select "url" so user types the URL immediately
    const text = state.doc.sliceString(from, to);
    const insert = `[${text}](url)`;
    dispatch({
      changes: { from, to, insert },
      selection: { anchor: from + text.length + 3, head: from + text.length + 6 }, // select "url"
    });
  }
  return true;
}

const markdownFormattingKeymap = keymap.of([
  { key: "Mod-b", run: wrapSelection("**") },
  { key: "Mod-i", run: wrapSelection("*") },
  { key: "Mod-Shift-x", run: wrapSelection("~~") },
  { key: "Mod-e", run: wrapSelection("`") },
  { key: "Mod-k", run: insertLink },
]);

// ---------------------------------------------------------------------------
// Spell check decorations (driven by NSSpellChecker via Swift bridge)
// ---------------------------------------------------------------------------

const setSpellErrorsEffect = StateEffect.define();

const spellErrorField = StateField.define({
  create() {
    return Decoration.none;
  },
  update(decorations, tr) {
    // Keep decorations in sync with document changes
    decorations = decorations.map(tr.changes);
    for (const effect of tr.effects) {
      if (effect.is(setSpellErrorsEffect)) {
        const marks = effect.value.map(({ from, to }) =>
          Decoration.mark({ class: "cm-spell-error" }).range(from, to),
        );
        decorations = Decoration.set(marks, true);
      }
    }
    return decorations;
  },
  provide: (f) => EditorView.decorations.from(f),
});

// ---------------------------------------------------------------------------
// Theme (base styling — colors in styles.css)
// ---------------------------------------------------------------------------

const editorTheme = EditorView.theme({
  "&": {
    height: "100%",
    // Inherit body font so --editor-font-family / --editor-font-size apply.
    fontFamily: "inherit",
    fontSize: "inherit",
    background: "transparent",
  },
  ".cm-content": {
    fontFamily: "inherit",
    padding: "12px 0",
    caretColor: "var(--caret-color)",
  },
  "&.cm-focused .cm-cursor": {
    borderLeftColor: "var(--caret-color)",
    borderLeftWidth: "1.5px",
  },
  ".cm-scroller": {
    overflow: "auto",
    // CodeMirror's baseTheme defaults .cm-scroller to monospace, which
    // cascades into .cm-content. Override here so the body's --editor-font-family
    // reaches the editor.
    fontFamily: "inherit",
  },
  "&.cm-focused": {
    outline: "none",
  },
  ".cm-activeLine": {
    backgroundColor: "transparent",
  },
  ".cm-activeLineGutter": {
    backgroundColor: "transparent",
  },
  ".cm-gutters": {
    backgroundColor: "transparent",
    border: "none",
  },
  ".cm-selectionBackground, ::selection": {
    backgroundColor: "var(--selection-bg) !important",
  },
  "&.cm-focused .cm-selectionBackground": {
    backgroundColor: "var(--selection-bg) !important",
  },
  ".cm-spell-error": {
    borderBottom: "2px dotted rgba(255, 59, 48, 0.6)",
  },
});

// ---------------------------------------------------------------------------
// Create editor
// ---------------------------------------------------------------------------

let view;

function createEditor(readOnly = false) {
  console.log(`[Editor JS] createEditor(readOnly=${readOnly})`);

  const extensions = [
    editorTheme,
    EditorView.lineWrapping,
    spellErrorField,
    history(),
    drawSelection(),
    highlightActiveLine(),
    highlightSelectionMatches(),
    bracketMatching(),
    markdown({ base: markdownLanguage }),
    wysiwyg(),
    listContinuationKeymap,
    markdownFormattingKeymap,
    keymap.of([...defaultKeymap, ...historyKeymap, ...searchKeymap, indentWithTab]),
    placeholderExt("Start writing…"),
    // Listen for doc changes → notify Swift (debounced)
    EditorView.updateListener.of((update) => {
      if (update.docChanged) {
        postContentChanged(update.state.doc.toString());
      }
      if (update.selectionSet) {
        postCursorPosition(update.view);
      }
    }),
  ];

  if (readOnly) {
    extensions.push(EditorState.readOnly.of(true));
    extensions.push(EditorView.editable.of(false));
  }

  view = new EditorView({
    state: EditorState.create({
      doc: "",
      extensions,
    }),
    parent: document.getElementById("editor"),
  });

  // Image drop handler — must be attached after view is created
  view.dom.addEventListener("drop", (e) => {
    const file = [...(e.dataTransfer?.files ?? [])].find((f) =>
      f.type.startsWith("image/"),
    );
    if (!file) return;
    e.preventDefault();
    const pos =
      view.posAtCoords({ x: e.clientX, y: e.clientY }) ??
      view.state.doc.length;
    pendingImageInsertPos = pos;
    readImageFile(file);
  });

  console.log("[Editor JS] Editor created, posting 'ready' to Swift");
  postToSwift({ action: "ready" });
}

// ---------------------------------------------------------------------------
// Swift ↔ JS Bridge
// ---------------------------------------------------------------------------

function postToSwift(msg) {
  try {
    window.webkit?.messageHandlers?.editor?.postMessage(msg);
  } catch (e) {
    // Running outside WKWebView (e.g. Safari for testing)
    console.log("[Bridge →]", msg);
  }
}

// ---------------------------------------------------------------------------
// Image drag & drop and paste
// ---------------------------------------------------------------------------

let pendingImageInsertPos = null;

function readImageFile(file) {
  const ext = (file.name.split(".").pop() || "png").toLowerCase();
  const reader = new FileReader();
  reader.onload = () => {
    const base64 = reader.result.split(",")[1];
    postToSwift({ action: "saveImage", data: base64, ext });
  };
  reader.readAsDataURL(file);
}

document.addEventListener("paste", (e) => {
  const item = [...(e.clipboardData?.items ?? [])].find(
    (i) => i.kind === "file" && i.type.startsWith("image/"),
  );
  if (!item) return;
  e.preventDefault();
  const file = item.getAsFile();
  if (!file || !view) return;
  pendingImageInsertPos = view.state.selection.main.head;
  readImageFile(file);
});

// Debounce contentChanged to avoid flooding Swift on every keystroke
let contentChangeTimer = null;
function postContentChanged(content) {
  if (contentChangeTimer) clearTimeout(contentChangeTimer);
  contentChangeTimer = setTimeout(() => {
    postToSwift({ action: "contentChanged", content });
    contentChangeTimer = null;
  }, 150);
}

// Throttle cursor position updates
let cursorThrottleTimer = null;
function postCursorPosition(editorView) {
  if (cursorThrottleTimer) return;
  cursorThrottleTimer = setTimeout(() => {
    cursorThrottleTimer = null;
    notifyCursorPosition(editorView);
  }, 50);
}

function notifyCursorPosition(editorView) {
  const { head } = editorView.state.selection.main;
  const coords = editorView.coordsAtPos(head);
  if (coords) {
    postToSwift({
      action: "cursorPosition",
      x: Math.round(coords.left),
      y: Math.round(coords.bottom),
      pos: head,
    });
  }
}

// Public API called from Swift via evaluateJavaScript
window.editorAPI = {
  setContent(text) {
    console.log(`[Editor JS] setContent called, text length: ${text?.length}, view exists: ${!!view}`);
    if (!view) return;
    view.dispatch({
      changes: { from: 0, to: view.state.doc.length, insert: text },
      selection: { anchor: 0 },
    });
    console.log(`[Editor JS] setContent done, doc length now: ${view.state.doc.length}`);
  },

  insertText(text) {
    console.log(`[Editor JS] insertText called, text length: ${text?.length}`);
    if (!view) return;
    const { head } = view.state.selection.main;
    view.dispatch({
      changes: { from: head, to: head, insert: text },
      selection: { anchor: head + text.length },
    });
  },

  focus() {
    view?.focus();
  },

  setReadOnly(readOnly) {
    if (!view) return;
    view.dispatch({
      effects: EditorState.readOnly.reconfigure(readOnly),
    });
  },

  setTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme);
  },

  setFont({ family, size }) {
    const root = document.documentElement.style;
    if (family) {
      // Quote font names so multi-word names ("SF Pro") stay valid in CSS.
      root.setProperty("--editor-font-family", `"${family}", -apple-system, BlinkMacSystemFont, sans-serif`);
    } else {
      root.removeProperty("--editor-font-family");
    }
    if (size) {
      root.setProperty("--editor-font-size", `${size}px`);
    } else {
      root.removeProperty("--editor-font-size");
    }
  },

  getContent() {
    return view?.state.doc.toString() ?? "";
  },

  getCursorPosition() {
    if (!view) return 0;
    return view.state.selection.main.head;
  },

  replaceRange(from, to, text, cursorPos) {
    if (!view) return;
    const changes = { from, to, insert: text };
    const anchor = cursorPos !== undefined ? cursorPos : from + text.length;
    view.dispatch({ changes, selection: { anchor } });
  },

  getSelectedText() {
    if (!view) return "";
    const { from, to } = view.state.selection.main;
    return from === to ? "" : view.state.sliceDoc(from, to);
  },

  setNoteBaseURL(url) {
    // Absolute file:// URL of the note's directory (storageRoot + folder/).
    // ImageWidget uses this to resolve relative paths:
    //   .My-Note/IMG-uuid.png → file:///Users/.../EdgeMark/folder/.My-Note/IMG-uuid.png
    window.editorNoteBaseURL = url.endsWith("/") ? url : url + "/";
  },

  setSpellErrors(errors) {
    if (!view) return;
    view.dispatch({ effects: setSpellErrorsEffect.of(errors) });
  },

  onImageSaved({ markdown }) {
    if (!view) return;
    const pos = pendingImageInsertPos ?? view.state.selection.main.head;
    pendingImageInsertPos = null;
    const doc = view.state.doc;
    const line = doc.lineAt(pos);

    if (line.text.trim() === "") {
      // Cursor on empty line — replace it with the image, no extra newlines
      view.dispatch({
        changes: { from: line.from, to: line.to, insert: markdown },
        selection: { anchor: line.from + markdown.length },
      });
    } else {
      // Cursor on content line — insert image as the next line.
      // line.to is the last char of text; the \n after it (if any) is line.to itself
      // in CM6's model. Insert \nmarkdown right at line.to — this creates a new line
      // with the image, sitting directly below the current line with no blank line.
      const insert = "\n" + markdown;
      view.dispatch({
        changes: { from: line.to, to: line.to, insert },
        selection: { anchor: line.to + insert.length },
      });
    }
  },
};

// ---------------------------------------------------------------------------
// Initialize
// ---------------------------------------------------------------------------

// Check URL params for readOnly mode
const params = new URLSearchParams(window.location.search);
const isReadOnly = params.get("readOnly") === "true";

createEditor(isReadOnly);

// Right-click context menu: only intercept when text is selected
document.addEventListener("contextmenu", (e) => {
  if (!view) return;
  const { from, to } = view.state.selection.main;
  if (from === to) return; // no selection — let the system menu appear
  e.preventDefault();
  window.webkit?.messageHandlers?.editor?.postMessage({
    action: "contextMenu",
    selectedText: view.state.sliceDoc(from, to),
    x: e.clientX,
    y: e.clientY,
  });
});
