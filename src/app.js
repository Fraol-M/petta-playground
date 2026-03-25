// src/app.js
import {basicSetup} from "codemirror";
import {EditorView, keymap} from "@codemirror/view";
import {Compartment, EditorState} from "@codemirror/state";
import {autocompletion, closeBrackets} from "@codemirror/autocomplete";
import {defaultKeymap, history, historyKeymap, indentWithTab} from "@codemirror/commands";

import {pettaLanguage} from "./petta-language.js";
import {pettaContext} from "./petta-context.js";
import {pettaThemes} from "./themes.js";

// ===== Example Programs =====
const EXAMPLES = {
    hello: {
        name: "Hello World",
        code: `; Hello World in MeTTa\n; Use ! to execute expressions\n\n!(println! "Hello, MeTTa World!")\n!(+ 2 3)\n!(* 4 5)`
    },
    arithmetic: {
        name: "Arithmetic",
        code: `; Basic arithmetic operations\n!(+ 10 20)\n!(- 100 42)\n!(* 7 8)\n!(/ 144 12)\n!(% 17 5)\n\n; Math functions\n!(pow-math 2 10)\n!(sqrt-math 144)\n!(abs-math -42)\n!(min 3 7)\n!(max 3 7)`
    },
    identity: {
        name: "Identity Function",
        code: `; Define a squaring function\n(= (square $x) (* $x $x))\n\n; Test it\n!(test (square 5) 25)\n!(test (square 3) 9)\n!(square 12)`
    },
    factorial: {
        name: "Factorial",
        code: `; Recursive factorial function\n(= (factorial $n)\n   (if (== $n 0)\n       1\n       (* $n (factorial (- $n 1)))))\n\n!(test (factorial 5) 120)\n!(test (factorial 10) 3628800)\n!(factorial 7)`
    },
    fibonacci: {
        name: "Fibonacci",
        code: `; Fibonacci sequence\n(= (fib $n)\n   (if (< $n 2)\n       $n\n       (+ (fib (- $n 1))\n          (fib (- $n 2)))))\n\n!(test (fib 10) 55)\n!(fib 15)`
    },
    peano: {
        name: "Peano Arithmetic",
        code: `; Peano numbers: Z = 0, (S n) = n+1\n(= (peano-add Z $y) $y)\n(= (peano-add (S $x) $y) (S (peano-add $x $y)))\n\n; Convert to number\n(= (to-nat Z) 0)\n(= (to-nat (S $x)) (+ 1 (to-nat $x)))\n\n; 2 + 3 = 5\n!(to-nat (peano-add (S (S Z)) (S (S (S Z)))))`
    },
    pattern_matching: {
        name: "Pattern Matching",
        code: `; Pattern matching with atomspace\n(color apple red)\n(color banana yellow)\n(color grape purple)\n(color lime green)\n(color cherry red)\n\n; Find all red fruits\n!(match &self (color $fruit red) $fruit)\n\n; Find all fruits and their colors\n!(match &self (color $fruit $color) ($fruit is $color))`
    },
    superpose: {
        name: "Nondeterminism",
        code: `; Superpose generates multiple results\n!(superpose (1 2 3 4 5))\n\n; Combine with functions\n(= (double $x) (* $x 2))\n!(double (superpose (1 2 3 4 5)))\n\n; Collapse collects all results into a list\n!(collapse (superpose (a b c d e)))`
    },
    higher_order: {
        name: "Higher-Order Functions",
        code: `; Map: apply a function to each element\n!(map-atom (1 2 3 4 5) $x (* $x $x))\n\n; Filter: keep elements matching a condition\n!(filter-atom (1 2 3 4 5 6 7 8) $x (> $x 4))\n\n; Fold: reduce a list to a single value (sum)\n!(foldl-atom (1 2 3 4 5) 0 $acc $x (+ $acc $x))`
    },
    logic: {
        name: "Logic Programming",
        code: `; Family relationships\n(parent alice bob)\n(parent alice charlie)\n(parent bob dave)\n(parent bob eve)\n\n; Define grandparent relationship\n(= (grandparent $gp $gc)\n   (let* (($parent (match &self (parent $gp $parent) $parent))\n          ($gc (match &self (parent $parent $gc) $gc)))\n         $gc))\n\n; Find grandchildren of alice\n!(grandparent alice $gc)`
    },
    types: {
        name: "Type System",
        code: `; Type annotations\n(: add (-> Number Number Number))\n(= (add $a $b) (+ $a $b))\n\n; Check types\n!(get-type 42)\n!(get-type "hello")\n!(get-type True)\n\n; Use typed function\n!(add 10 20)`
    }
};

// DOM Elements
const elements = {
    runBtn: document.getElementById("runBtn"),
    clearBtn: document.getElementById("clearBtn"),
    examplesSelect: document.getElementById("examplesSelect"),
    themeSelect: document.getElementById("themeSelect"),
    outputContent: document.getElementById("outputContent"),
    outputBadge: document.getElementById("outputBadge"),
    executionTime: document.getElementById("executionTime"),
    statusDot: document.getElementById("statusDot"),
    statusText: document.getElementById("statusText"),
    loadingOverlay: document.getElementById("loadingOverlay"),
    loadingStep: document.getElementById("loadingStep"),
    progressBar: document.getElementById("progressBar"),
};

// State
let worker = null;
let isRunning = false;
let editorView = null;
let activeRequestId = 0;
let nextRequestId = 0;

const themeSlot = new Compartment();

// Init Editor
function initEditor(initialCode) {
    editorView = new EditorView({
        state: EditorState.create({
            doc: initialCode,
            extensions: [
                basicSetup,
                history(),
                keymap.of([indentWithTab, ...defaultKeymap, ...historyKeymap]),
                closeBrackets(),
                pettaLanguage(),
                autocompletion({
                    override: [pettaContext],
                    activateOnTyping: true,
                    maxRenderedOptions: 12
                }),
                themeSlot.of(pettaThemes.dark)
            ]
        }),
        parent: document.getElementById("editor")
    });
}

function updateURL() {
    const code = editorView.state.doc.toString();
    const encoded = btoa(encodeURIComponent(code));
    window.history.replaceState(null, "", "?code=" + encoded);
}

// Resizable Panels using pure JS
function initResizablePanels() {
    const mainContent = document.getElementById('mainContent');
    const editorPanel = document.getElementById('editorPanel');
    const outputPanel = document.getElementById('outputPanel');
    
    // Check if we are in desktop layout (side-by-side)
    if (window.innerWidth >= 900) {
        // Create drag handle
        const dragHandle = document.createElement('div');
        dragHandle.className = 'drag-handle';
        
        // Remove controlsBar from the flow and append drag handle
        const controlsBar = document.getElementById('controlsBar');
        controlsBar.style.gridColumn = "1 / -1";
        controlsBar.style.gridRow = "2";
        
        mainContent.appendChild(dragHandle);
        
        let isDragging = false;
        
        dragHandle.addEventListener('mousedown', (e) => {
            isDragging = true;
            document.body.style.cursor = 'col-resize';
            e.preventDefault();
        });
        
        document.addEventListener('mousemove', (e) => {
            if (!isDragging) return;
            const containerRect = mainContent.getBoundingClientRect();
            // Calculate percentage width mapping 0-100 to avoid breaking layout
            let newWidth = ((e.clientX - containerRect.left) / containerRect.width) * 100;
            if (newWidth < 20) newWidth = 20;
            if (newWidth > 80) newWidth = 80;
            
            mainContent.style.gridTemplateColumns = `calc(${newWidth}% - var(--space-md)/2) calc(${100 - newWidth}% - var(--space-md)/2)`;
            dragHandle.style.left = `calc(${newWidth}%)`;
        });
        
        document.addEventListener('mouseup', () => {
            isDragging = false;
            document.body.style.cursor = '';
        });
    }
}

// Utility functions
function appendOutput(text, className = "") {
    const placeholder = elements.outputContent.querySelector(".output-placeholder");
    if (placeholder) {
        placeholder.remove();
    }
    const line = document.createElement("div");
    line.className = `output-line ${className}`;
    line.textContent = text;
    elements.outputContent.appendChild(line);
    elements.outputContent.scrollTop = elements.outputContent.scrollHeight;
}

function clearOutput() {
    elements.outputContent.innerHTML = `
        <div class="output-placeholder">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="placeholder-icon">
                <circle cx="12" cy="12" r="10"></circle>
                <path d="M8 14s1.5 2 4 2 4-2 4-2"></path>
                <line x1="9" y1="9" x2="9.01" y2="9"></line>
                <line x1="15" y1="9" x2="15.01" y2="9"></line>
            </svg>
            <p>Run your code to see results here</p>
            <span class="placeholder-hint">Press <kbd>Ctrl+Enter</kbd> or click <strong>Run</strong></span>
        </div>`;
    elements.outputBadge.className = "output-badge";
    elements.outputBadge.textContent = "";
    elements.executionTime.textContent = "";
}

function setStatus(status, text) {
    elements.statusDot.className = `status-dot ${status}`;
    elements.statusText.textContent = text;
}

function setLoadingStep(text, progress) {
    elements.loadingStep.textContent = text;
    elements.progressBar.style.width = `${progress}%`;
}

// Worker Execution
function runMettaAsync(worker, code, requestId) {
    return new Promise((resolve, reject) => {
        const handleMessage = (event) => {
            const message = event.data;
            if (!message || message.requestId !== requestId) return;
            
            worker.removeEventListener("message", handleMessage);
            worker.removeEventListener("error", handleError);
            
            if (message.type === "result") {
                resolve(message.output);
            } else if (message.type === "error") {
                reject(new Error(message.error));
            }
        };

        const handleError = (event) => {
            worker.removeEventListener("message", handleMessage);
            worker.removeEventListener("error", handleError);
            reject(event.error || new Error(event.message || "Worker execution failed"));
        };

        worker.addEventListener("message", handleMessage);
        worker.addEventListener("error", handleError, {once: true});
        worker.postMessage({type: "run", code, requestId});
    });
}

async function runCode() {
    if (!worker || isRunning) return;
    
    updateURL();

    const code = editorView.state.doc.toString();
    if (!code.trim().length) {
        appendOutput("No code to run.", "info");
        return;
    }

    isRunning = true;
    const requestId = ++nextRequestId;
    activeRequestId = requestId;

    elements.runBtn.classList.add("running");
    elements.runBtn.querySelector("span").textContent = "Running...";
    setStatus("running", "Executing...");
    elements.outputContent.innerHTML = "";
    elements.outputBadge.className = "output-badge";
    elements.executionTime.textContent = "";

    const startTime = performance.now();

    // Kill runaway queries after 10s
    let timeoutFinished = false;
    const TIMEOUT_MS = 10000;
    const timer = setTimeout(() => {
        if (!timeoutFinished) {
            worker.terminate();
            appendOutput("Execution timed out after 10s.", "error");
            elements.outputBadge.className = "output-badge error";
            elements.outputBadge.textContent = "Error";
            
            // Re-initialize worker
            initPeTTa();
            resetUI(startTime);
        }
    }, TIMEOUT_MS);

    try {
        const result = await runMettaAsync(worker, code, requestId);
        timeoutFinished = true;
        clearTimeout(timer);

        if (requestId !== activeRequestId) return;

        if (result) {
            const lines = result.split('\n');
            for (const line of lines) {
                const trimmedLine = line.trim();
                if (trimmedLine) {
                    // Check testing output syntax and colorize
                    if (trimmedLine.includes("✅")) {
                        appendOutput(trimmedLine, "test-pass");
                    } else if (trimmedLine.includes("❌")) {
                        appendOutput(trimmedLine, "test-fail");
                    } else {
                        appendOutput(trimmedLine, "result");
                    }
                }
            }
            elements.outputBadge.className = "output-badge success";
            elements.outputBadge.textContent = "Done";
        } else {
            appendOutput("No output. Add at least one runnable form like !(...).", "info");
            elements.outputBadge.className = "output-badge";
            elements.outputBadge.textContent = "";
        }
    } catch (err) {
        timeoutFinished = true;
        clearTimeout(timer);
        if (requestId !== activeRequestId) return;
        
        appendOutput(`Error: ${err.message}`, "error");
        elements.outputBadge.className = "output-badge error";
        elements.outputBadge.textContent = "Error";
    } finally {
        if (requestId === activeRequestId) {
            resetUI(startTime);
        }
    }
}

function resetUI(startTime) {
    const elapsed = performance.now() - startTime;
    elements.executionTime.textContent = `${elapsed.toFixed(1)}ms`;
    
    elements.runBtn.classList.remove("running");
    elements.runBtn.querySelector("span").textContent = "Run";
    setStatus("ready", "Ready");
    isRunning = false;
}

// Initializer
function initPeTTa() {
    try {
        worker = new Worker(new URL("./petta-worker.js", import.meta.url), { type: "module" });
    } catch (err) {
        const message = err?.message || String(err);
        console.error("Worker creation failed:", err);
        setLoadingStep(`Error: ${message}`, 0);
        elements.progressBar.style.background = "var(--accent-red)";
        setStatus("error", "Failed to load");
        return;
    }
    
    setLoadingStep("Initializing Web Worker & SWI-Prolog...", 30);

    const handleInitError = (event) => {
        const message = event?.error?.message || event?.message || "Worker failed to initialize";
        console.error("Worker init/runtime error:", event?.error || event);
        setLoadingStep(`Error: ${message}`, 0);
        elements.progressBar.style.background = "var(--accent-red)";
        setStatus("error", "Failed to load");
    };

    worker.addEventListener("error", handleInitError, { once: true });
    worker.postMessage({ type: "init" });

    worker.addEventListener("message", (event) => {
        const { type, error } = event.data;
        if (type === "ready") {
            worker.removeEventListener("error", handleInitError);
            setLoadingStep("PeTTa runtime ready!", 100);
            setTimeout(() => {
                elements.loadingOverlay.classList.add("hidden");
                setTimeout(() => elements.loadingOverlay.style.display = "none", 500);
            }, 500);
            elements.runBtn.disabled = false;
            setStatus("ready", "Ready");
        } else if (type === "error") {
            worker.removeEventListener("error", handleInitError);
            console.error("Worker init failed:", error);
            setLoadingStep(`Error: ${error}`, 0);
            elements.progressBar.style.background = "var(--accent-red)";
            setStatus("error", "Failed to load");
        }
    });
}

// Events
document.addEventListener("DOMContentLoaded", () => {
    // Read URL state
    const urlParams = new URLSearchParams(window.location.search);
    let initialCode = `; Welcome to PeTTa Playground!\n; Try running this simple example:\n\n(= (square $x) (* $x $x))\n\n!(square 5)\n!(+ 10 20)\n!(test (square 3) 9)`;
    if (urlParams.has("code")) {
        try {
            initialCode = decodeURIComponent(atob(urlParams.get("code")));
        } catch(e) { }
    }

    initEditor(initialCode);
    initPeTTa();
    initResizablePanels();

    // Theme toggle
    elements.themeSelect.addEventListener("change", (e) => {
        const mode = e.target.value;
        if(mode === "light") {
            document.body.classList.add("light-theme");
        } else {
            document.body.classList.remove("light-theme");
        }
        editorView.dispatch({
            effects: themeSlot.reconfigure(pettaThemes[mode])
        });
    });

    // Run shortuct
    document.addEventListener("keydown", (e) => {
        if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
            e.preventDefault();
            runCode();
        }
    });

    elements.runBtn.addEventListener("click", runCode);
    elements.clearBtn.addEventListener("click", clearOutput);

    // Examples
    elements.examplesSelect.addEventListener("change", () => {
        const key = elements.examplesSelect.value;
        if (key && EXAMPLES[key]) {
            editorView.dispatch({
                changes: {from: 0, to: editorView.state.doc.length, insert: EXAMPLES[key].code}
            });
            updateURL();
        }
        elements.examplesSelect.value = "";
    });
    
    // Auto-update URL on Editor change
    let updateTimeout;
    editorView.dom.addEventListener('input', () => {
        clearTimeout(updateTimeout);
        updateTimeout = setTimeout(updateURL, 1000);
    });
});
