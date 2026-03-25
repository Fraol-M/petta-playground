import {StreamLanguage, LanguageSupport} from "@codemirror/language";

const KEYWORDS = new Set([
  "match", "if", "quote", "let", "let*", "and", "or", "not", "xor", "implies", 
  "superpose", "collapse", "import!", "bind!", "change-state!", "get-state",
  "test", "assert", "println!", "readln!", "eval", "call", "reduce", "transaction",
  "with_mutex", "hyperpose", "case", "once", "sealed", "progn", "prog1"
]);

const TYPES = new Set([
  "Atom", "Expression", "Symbol", "Variable", "Number", "Bool", "String", "Type",
  "Grounded"
]);

const OPERATORS = new Set([
    ":", "=", "->", "=>", "!", "!=", ">", "<", ">=", "<=", "==", "=?", "=alpha",
    "+", "-", "*", "/", "%", "cons"
]);

function readWhile(stream, re) {
  while (!stream.eol() && re.test(stream.peek())) {
    stream.next();
  }
}

const pettaStream = StreamLanguage.define({
  startState() {
    return {inString: false, escaped: false};
  },
  token(stream, state) {
    if (state.inString) {
      while (!stream.eol()) {
        const ch = stream.next();
        if (state.escaped) {
          state.escaped = false;
        } else if (ch === "\\") {
          state.escaped = true;
        } else if (ch === '"') {
          state.inString = false;
          break;
        }
      }
      return "string";
    }

    if (stream.sol() && stream.peek() === ";") {
      stream.skipToEnd();
      return "comment";
    }

    if (stream.peek() === ";") {
      stream.skipToEnd();
      return "comment";
    }

    if (stream.match(/\s+/)) {
      return null;
    }

    const ch = stream.peek();

    if (ch === '(' || ch === ')') {
      stream.next();
      return "bracket";
    }

    if (ch === '"') {
      state.inString = true;
      stream.next();
      return "string";
    }

    if (ch === '$') {
      stream.next();
      readWhile(stream, /[A-Za-z0-9_!?-]/);
      return "variableName";
    }

    if (ch === '&') {
      stream.next();
      readWhile(stream, /[A-Za-z0-9_!?-]/);
      return "namespace";
    }

    if (stream.match(/-?\d+(?:\.\d+)?\b/)) {
      return "number";
    }

    if (stream.match(/(?:->|=>|!=|>=|<=|=|:|=alpha|=\?|!|>|<)/)) {
      return "operator";
    }

    if (stream.match(/[A-Za-z_+*/%][A-Za-z0-9_!?+*/\-%]*/)) {
      const value = stream.current();
      if (KEYWORDS.has(value)) return "keyword";
      if (TYPES.has(value)) return "typeName";
      if (OPERATORS.has(value)) return "operator";
      if (value === "True" || value === "False" || value === "true" || value === "false") return "bool";
      return "atom";
    }

    stream.next();
    return null;
  }
});

export function pettaLanguage() {
  return new LanguageSupport(pettaStream);
}
