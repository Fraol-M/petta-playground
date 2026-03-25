import {EditorView} from "@codemirror/view";
import {HighlightStyle, syntaxHighlighting} from "@codemirror/language";
import {tags} from "@lezer/highlight";

const shared = {
  ".cm-content": {
    fontFamily: "var(--font-mono)",
    fontSize: "0.85rem",
    lineHeight: "1.6"
  },
  ".cm-line": { padding: "0" },
  ".cm-tooltip-autocomplete": {
    borderRadius: "8px",
    overflow: "hidden",
    fontFamily: "var(--font-sans)"
  },
  ".cm-tooltip-autocomplete > ul > li[aria-selected]": {
    background: "rgba(99, 102, 241, 0.2)"
  }
};

const darkChrome = EditorView.theme({
  ...shared,
  "&": {
    color: "#f1f5f9",
    backgroundColor: "transparent"
  },
  ".cm-gutters": {
    backgroundColor: "rgba(255, 255, 255, 0.01)",
    color: "var(--text-muted)",
    border: "none",
    borderRight: "1px solid var(--border-secondary)"
  },
  ".cm-activeLine": {
    backgroundColor: "rgba(255,255,255,0.02)"
  },
  ".cm-activeLineGutter": {
    backgroundColor: "rgba(255,255,255,0.02)"
  },
  ".cm-selectionBackground, &.cm-focused .cm-selectionBackground": {
    backgroundColor: "rgba(99, 102, 241, 0.3)"
  },
  "&.cm-focused .cm-cursor": {
    borderLeftColor: "var(--accent-primary)"
  },
  ".cm-panels": {
    backgroundColor: "var(--bg-tertiary)",
    color: "#f1f5f9"
  },
  ".cm-tooltip": {
    backgroundColor: "var(--bg-tertiary)",
    color: "#f1f5f9",
    border: "1px solid var(--border-secondary)"
  }
}, {dark: true});

const lightChrome = EditorView.theme({
  ...shared,
  "&": {
    color: "#0f172a",
    backgroundColor: "transparent"
  },
  ".cm-gutters": {
    backgroundColor: "#f8fafc",
    color: "#64748b",
    border: "none",
    borderRight: "1px solid #e2e8f0"
  },
  ".cm-activeLine": {
    backgroundColor: "rgba(0,0,0,0.03)"
  },
  ".cm-activeLineGutter": {
    backgroundColor: "rgba(0,0,0,0.03)"
  },
  ".cm-selectionBackground, &.cm-focused .cm-selectionBackground": {
    backgroundColor: "rgba(99, 102, 241, 0.2)"
  },
  "&.cm-focused .cm-cursor": {
    borderLeftColor: "var(--accent-primary)"
  },
  ".cm-panels": {
    backgroundColor: "#f1f5f9",
    color: "#0f172a"
  },
  ".cm-tooltip": {
    backgroundColor: "#ffffff",
    color: "#0f172a",
    border: "1px solid #e2e8f0"
  }
}, {dark: false});

// Highlighting closer to the visual style
const darkSyntax = HighlightStyle.define([
  {tag: tags.comment, color: "var(--text-muted)", fontStyle: "italic"},
  {tag: tags.keyword, color: "var(--accent-secondary)"}, // purple/indigo
  {tag: [tags.operator, tags.punctuation], color: "var(--accent-red)"}, // red/pink
  {tag: [tags.number, tags.bool], color: "var(--accent-amber)"}, // amber
  {tag: tags.string, color: "var(--accent-green)"}, // green
  {tag: tags.variableName, color: "var(--accent-cyan)"}, // cyan
  {tag: tags.namespace, color: "var(--accent-cyan)"},
  {tag: [tags.atom, tags.labelName], color: "var(--text-primary)"},
  {tag: tags.typeName, color: "var(--accent-red)"}
]);

const lightSyntax = HighlightStyle.define([
  {tag: tags.comment, color: "#64748b", fontStyle: "italic"},
  {tag: tags.keyword, color: "#7c3aed"},
  {tag: [tags.operator, tags.punctuation], color: "#e11d48"},
  {tag: [tags.number, tags.bool], color: "#d97706"},
  {tag: tags.string, color: "#059669"},
  {tag: tags.variableName, color: "#0284c7"},
  {tag: tags.namespace, color: "#0891b2"},
  {tag: [tags.atom, tags.labelName], color: "#0f172a"},
  {tag: tags.typeName, color: "#dc2626"}
]);

export const pettaThemes = {
  dark: [darkChrome, syntaxHighlighting(darkSyntax)],
  light: [lightChrome, syntaxHighlighting(lightSyntax)]
};
