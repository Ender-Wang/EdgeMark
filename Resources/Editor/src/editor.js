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
import { EditorState } from "@codemirror/state";
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

  // Task list: "  - [ ] content" or "  - [x] content"
  const taskMatch = text.match(/^(\s*[-*+]\s+)\[([xX ])\]\s?(.*)/);
  if (taskMatch) {
    const indent = taskMatch[1];
    const content = taskMatch[3];
    if (content.trim() === "") {
      // Empty task line → clear it
      dispatch({
        changes: { from: line.from, to: line.to, insert: "" },
        selection: { anchor: line.from },
      });
      return true;
    }
    const insert = `\n${indent}[ ] `;
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

const listContinuationKeymap = keymap.of([
  { key: "Enter", run: listContinuation },
]);

// ---------------------------------------------------------------------------
// Theme (base styling — colors in styles.css)
// ---------------------------------------------------------------------------

const editorTheme = EditorView.theme({
  "&": {
    height: "100%",
    fontSize: "15px",
    background: "transparent",
  },
  ".cm-content": {
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
    padding: "12px",
    caretColor: "var(--caret-color)",
  },
  ".cm-focused .cm-cursor": {
    borderLeftColor: "var(--caret-color)",
    borderLeftWidth: "1.5px",
  },
  ".cm-scroller": {
    overflow: "auto",
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
  ".cm-focused .cm-selectionBackground": {
    backgroundColor: "var(--selection-bg) !important",
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
    history(),
    drawSelection(),
    highlightActiveLine(),
    highlightSelectionMatches(),
    bracketMatching(),
    markdown({ base: markdownLanguage }),
    wysiwyg(),
    listContinuationKeymap,
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
};

// ---------------------------------------------------------------------------
// Initialize
// ---------------------------------------------------------------------------

// Check URL params for readOnly mode
const params = new URLSearchParams(window.location.search);
const isReadOnly = params.get("readOnly") === "true";

createEditor(isReadOnly);
