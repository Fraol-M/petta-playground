import {snippetCompletion} from "@codemirror/autocomplete";

const ROOT_FORMS = [
  snippetCompletion("!(${1:expr})", {
    label: "!()", type: "function", detail: "Evaluate expression"
  }),
  snippetCompletion("(match &self ${1:(Rel $x)} ${2:$x})", {
    label: "match", type: "keyword", detail: "Pattern match"
  }),
  snippetCompletion("(= (${1:name} ${2:$x}) ${3:body})", {
    label: "= function", type: "keyword", detail: "Function definition"
  }),
  snippetCompletion("(: ${1:name} ${2:Type})", {
    label: ": type", type: "keyword", detail: "Type declaration"
  }),
  snippetCompletion("(if ${1:cond} ${2:then} ${3:else})", {
    label: "if", type: "keyword", detail: "Conditional"
  }),
  {label: "match", type: "keyword"},
  {label: "if", type: "keyword"},
  {label: "let", type: "keyword"},
  {label: "let*", type: "keyword"},
  {label: "and", type: "keyword"},
  {label: "or", type: "keyword"},
  {label: "not", type: "keyword"},
  {label: ":", type: "operator"},
  {label: "=", type: "operator"}
];

const TYPE_OPTIONS = [
  "Atom", "Expression", "Symbol", "Variable", "Number", "Bool", "String", "Type", "Grounded"
].map(label => ({label, type: "type"}));

const BUILTIN_SYMBOLS = [
  "+", "-", "*", "/", "%", "eq", "match", "if", "quote", "let", "let*", "and", "or", "not",
  "collapse", "superpose", "println!", "readln!", "test", "bind!", "change-state!",
  "get-state", "eval", "call", "reduce"
].map(label => ({label, type: "function"}));

function uniqOptions(list) {
  const seen = new Set();
  return list.filter(item => {
    const key = `${item.label}|${item.type || ""}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function prefixInfo(doc, pos) {
  let from = pos;
  while (from > 0) {
    const ch = doc[from - 1];
    if (!/[A-Za-z0-9_!?+*\/-:$&><=]/.test(ch)) break;
    from--;
  }
  return {from, text: doc.slice(from, pos)};
}

function scanContext(doc, pos) {
  const stack = [];
  let inString = false, escaped = false, inComment = false, token = "";

  function flushToken() {
    if (!token) return;
    if (stack.length && stack[stack.length - 1].head == null) {
      stack[stack.length - 1].head = token;
    }
    token = "";
  }

  for (let i = 0; i < pos; i++) {
    const ch = doc[i];
    if (inComment) { if (ch === "\n") inComment = false; continue; }
    if (inString) {
      if (escaped) escaped = false;
      else if (ch === "\\") escaped = true;
      else if (ch === '"') inString = false;
      continue;
    }
    if (ch === ";") { flushToken(); inComment = true; continue; }
    if (ch === '"') { flushToken(); inString = true; continue; }
    if (ch === '(') { flushToken(); stack.push({start: i, head: null}); continue; }
    if (ch === ')') { flushToken(); stack.pop(); continue; }
    if (/\s/.test(ch)) { flushToken(); continue; }
    token += ch;
  }
  flushToken();

  const currentList = stack[stack.length - 1] || null;
  const prevNonSpace = (() => {
    for (let i = pos - 1; i >= 0; i--) if (!/\s/.test(doc[i])) return doc[i];
    return "";
  })();

  return {
    currentList, prevNonSpace,
    listText: currentList ? doc.slice(currentList.start, pos) : "",
    parentHead: currentList?.head || null,
    expectHead: prevNonSpace === "(",
    inComment, inString
  };
}

function collectSymbols(doc) {
  const vars = new Set(), spaces = new Set(["&self"]), atoms = new Set(), heads = new Set(), types = new Set(["Atom", "Expression", "Symbol", "Variable", "Number", "Bool", "String", "Type"]);
  const tokenRe = /\$[A-Za-z0-9_!?-]+|&[A-Za-z0-9_!?-]+|[A-Za-z_+*/:-][A-Za-z0-9_!?+*/\:-]*/g;
  for (const match of doc.matchAll(tokenRe)) {
    const token = match[0];
    if (token.startsWith("$")) vars.add(token);
    else if (token.startsWith("&")) spaces.add(token);
    else atoms.add(token);
  }
  for (const match of doc.matchAll(/\(([A-Za-z_+*/:-][A-Za-z0-9_!?+*/\:-]*)/g)) heads.add(match[1]);
  for (const match of doc.matchAll(/\(=\s+\(([A-Za-z_+*/:-][A-Za-z0-9_!?+*/\:-]*)/g)) {
    atoms.add(match[1]); heads.add(match[1]);
  }
  for (const match of doc.matchAll(/\(:\s+([A-Za-z_+*/:-][A-Za-z0-9_!?+*/\:-]*)\s+([A-Za-z_+*/:-][A-Za-z0-9_!?+*/\:-]*)/g)) {
    atoms.add(match[1]); types.add(match[2]);
  }
  return { vars: [...vars], spaces: [...spaces], atoms: [...atoms], heads: [...heads], types: [...types] };
}

function symbolOptions(values, type = "variable") {
  return values.map(label => ({label, type}));
}

export function pettaContext(context) {
  const doc = context.state.doc.toString();
  const {from, text: prefix} = prefixInfo(doc, context.pos);
  const parse = scanContext(doc, context.pos);
  const symbols = collectSymbols(doc);
  const scopeVars = [...new Set((parse.listText.match(/\$[A-Za-z0-9_!?-]+/g) || []))];

  if (parse.inComment || parse.inString) return null;

  let options = [];
  if (prefix.startsWith("$")) {
    options = uniqOptions([...symbolOptions(scopeVars, "variable"), ...symbolOptions(symbols.vars, "variable")]);
  } else if (prefix.startsWith("&")) {
    options = uniqOptions(symbolOptions(symbols.spaces, "namespace"));
  } else if (parse.expectHead) {
    options = uniqOptions([...ROOT_FORMS, ...symbolOptions(symbols.heads, "function"), ...BUILTIN_SYMBOLS]);
  } else if (parse.parentHead === ":") {
    options = uniqOptions([...TYPE_OPTIONS, ...symbolOptions(symbols.types, "type")]);
  } else if (parse.parentHead === "match") {
    options = uniqOptions([
      ...symbolOptions(symbols.spaces, "namespace"),
      ...symbolOptions(symbols.heads, "function"),
      ...symbolOptions(scopeVars, "variable"),
      ...symbolOptions(symbols.vars, "variable")
    ]);
  } else {
    options = uniqOptions([
      ...BUILTIN_SYMBOLS,
      ...symbolOptions(symbols.atoms, "variable"),
      ...symbolOptions(scopeVars, "variable"),
      ...symbolOptions(symbols.vars, "variable"),
      ...symbolOptions(symbols.spaces, "namespace")
    ]);
  }

  if (!prefix && !parse.expectHead && !context.explicit) return null;
  const filtered = prefix ? options.filter(o => o.label.toLowerCase().startsWith(prefix.toLowerCase())) : options;
  if (!filtered.length) return null;

  return { from, options: filtered, validFor: /^[A-Za-z0-9_!?+*/:$&><=-]*$/ };
}
