/**
 * PeTTa Playground â€” Browser-based MeTTa execution via SWI-Prolog WASM
 */

// ===== Example Programs =====

const EXAMPLES = {
    hello: {
        name: "Hello World",
        code: `; Hello World in MeTTa
; Use ! to execute expressions

!(println! "Hello, MeTTa World!")
!(+ 2 3)
!(* 4 5)`
    },
    arithmetic: {
        name: "Arithmetic",
        code: `; Basic arithmetic operations
!(+ 10 20)
!(- 100 42)
!(* 7 8)
!(/ 144 12)
!(% 17 5)

; Math functions
!(pow-math 2 10)
!(sqrt-math 144)
!(abs-math -42)
!(min 3 7)
!(max 3 7)`
    },
    identity: {
        name: "Identity Function",
        code: `; Define a squaring function
(= (square $x) (* $x $x))

; Test it
!(test (square 5) 25)
!(test (square 3) 9)
!(square 12)`
    },
    factorial: {
        name: "Factorial",
        code: `; Recursive factorial function
(= (factorial $n)
   (if (== $n 0)
       1
       (* $n (factorial (- $n 1)))))

!(test (factorial 5) 120)
!(test (factorial 10) 3628800)
!(factorial 7)`
    },
    fibonacci: {
        name: "Fibonacci",
        code: `; Fibonacci sequence
(= (fib $n)
   (if (< $n 2)
       $n
       (+ (fib (- $n 1))
          (fib (- $n 2)))))

!(test (fib 10) 55)
!(fib 15)`
    },
    peano: {
        name: "Peano Arithmetic",
        code: `; Peano numbers: Z = 0, (S n) = n+1
(= (peano-add Z $y) $y)
(= (peano-add (S $x) $y) (S (peano-add $x $y)))

; Convert to number
(= (to-nat Z) 0)
(= (to-nat (S $x)) (+ 1 (to-nat $x)))

; 2 + 3 = 5
!(to-nat (peano-add (S (S Z)) (S (S (S Z)))))`
    },
    pattern_matching: {
        name: "Pattern Matching",
        code: `; Pattern matching with atomspace
(color apple red)
(color banana yellow)
(color grape purple)
(color lime green)
(color cherry red)

; Find all red fruits
!(match &self (color $fruit red) $fruit)

; Find all fruits and their colors
!(match &self (color $fruit $color) ($fruit is $color))`
    },
    superpose: {
        name: "Nondeterminism",
        code: `; Superpose generates multiple results
!(superpose (1 2 3 4 5))

; Combine with functions
(= (double $x) (* $x 2))
!(double (superpose (1 2 3 4 5)))

; Collapse collects all results into a list
!(collapse (superpose (a b c d e)))`
    },
    higher_order: {
        name: "Higher-Order Functions",
        code: `; Map: apply a function to each element
!(map-atom (1 2 3 4 5) $x (* $x $x))

; Filter: keep elements matching a condition
!(filter-atom (1 2 3 4 5 6 7 8) $x (> $x 4))

; Fold: reduce a list to a single value (sum)
!(foldl-atom (1 2 3 4 5) 0 $acc $x (+ $acc $x))`
    },
    logic: {
        name: "Logic Programming",
        code: `; Family relationships
(parent alice bob)
(parent alice charlie)
(parent bob dave)
(parent bob eve)

; Define grandparent relationship
(= (grandparent $gp $gc)
   (let $parent (match &self (parent $gp $parent) $parent)
        (match &self (parent $parent $gc) $gc)))

; Find grandchildren of alice
!(grandparent alice $gc)`
    },
    types: {
        name: "Type System",
        code: `; Type annotations
(: add (-> Number Number Number))
(= (add $a $b) (+ $a $b))

; Check types
!(get-type 42)
!(get-type "hello")
!(get-type True)

; Use typed function
!(add 10 20)`
    }
};

// ===== DOM Elements =====
const elements = {
    codeEditor: document.getElementById("codeEditor"),
    lineNumbers: document.getElementById("lineNumbers"),
    runBtn: document.getElementById("runBtn"),
    clearBtn: document.getElementById("clearBtn"),
    examplesSelect: document.getElementById("examplesSelect"),
    outputContent: document.getElementById("outputContent"),
    outputBadge: document.getElementById("outputBadge"),
    executionTime: document.getElementById("executionTime"),
    statusDot: document.getElementById("statusDot"),
    statusText: document.getElementById("statusText"),
    loadingOverlay: document.getElementById("loadingOverlay"),
    loadingStep: document.getElementById("loadingStep"),
    progressBar: document.getElementById("progressBar"),
};

// ===== State =====
let swipl = null;
let isRunning = false;

// ===== Line Numbers =====
function updateLineNumbers() {
    const lines = elements.codeEditor.value.split("\n").length;
    const nums = [];
    for (let i = 1; i <= lines; i++) {
        nums.push(i);
    }
    elements.lineNumbers.textContent = nums.join("\n");
}

elements.codeEditor.addEventListener("input", updateLineNumbers);
elements.codeEditor.addEventListener("scroll", () => {
    elements.lineNumbers.scrollTop = elements.codeEditor.scrollTop;
});

// Tab key support
elements.codeEditor.addEventListener("keydown", (e) => {
    if (e.key === "Tab") {
        e.preventDefault();
        const start = elements.codeEditor.selectionStart;
        const end = elements.codeEditor.selectionEnd;
        elements.codeEditor.value =
            elements.codeEditor.value.substring(0, start) +
            "    " +
            elements.codeEditor.value.substring(end);
        elements.codeEditor.selectionStart = elements.codeEditor.selectionEnd = start + 4;
        updateLineNumbers();
    }
    // Ctrl+Enter to run
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        runCode();
    }
});

updateLineNumbers();

// ===== Examples =====
elements.examplesSelect.addEventListener("change", () => {
    const key = elements.examplesSelect.value;
    if (key && EXAMPLES[key]) {
        elements.codeEditor.value = EXAMPLES[key].code;
        updateLineNumbers();
    }
    elements.examplesSelect.value = "";
});

// ===== Output =====
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

function appendOutput(text, className = "") {
    // Remove placeholder if present
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

elements.clearBtn.addEventListener("click", clearOutput);

// ===== Status =====
function setStatus(status, text) {
    elements.statusDot.className = `status-dot ${status}`;
    elements.statusText.textContent = text;
}

// ===== Loading =====
function setLoadingStep(text, progress) {
    elements.loadingStep.textContent = text;
    elements.progressBar.style.width = `${progress}%`;
}

// ===== Escape Prolog String =====
function escapePrologString(str) {
    return str
        .replace(/\\/g, "\\\\")
        .replace(/"/g, '\\"')
        .replace(/\n/g, "\\n")
        .replace(/\r/g, "");
}
function looksLikeErrorOutput(text) {
    if (!text) return false;
    const lower = text.toLowerCase();
    return lower.startsWith("error:") ||
        lower.startsWith("error(") ||
        lower.includes("permission_error") ||
        lower.includes("syntax_error") ||
        lower.includes("existence_error") ||
        lower.includes("type_error");
}

// ===== Run Code =====
async function runCode() {
    if (!swipl || isRunning) return;

    isRunning = true;
    const codeRaw = elements.codeEditor.value;
    const hasAnyCode = codeRaw.trim().length > 0;
    const code = codeRaw.endsWith("\n") ? codeRaw : `${codeRaw}\n`;

    if (!hasAnyCode) {
        appendOutput("No code to run.", "info");
        isRunning = false;
        return;
    }

    // Clear previous output
    elements.outputContent.innerHTML = "";
    elements.outputBadge.className = "output-badge";
    elements.executionTime.textContent = "";

    // Update UI
    elements.runBtn.classList.add("running");
    elements.runBtn.querySelector("span").textContent = "Running...";
    setStatus("running", "Executing...");

    const startTime = performance.now();

    try {
        const escaped = escapePrologString(code);
        const query = `metta_exec("${escaped}", Output)`;

        try {
            const result = swipl.prolog.query(query).once();

            if (result === false || !result || !Object.prototype.hasOwnProperty.call(result, "Output")) {
                appendOutput("Query failed - no results.", "error");
                elements.outputBadge.className = "output-badge error";
                elements.outputBadge.textContent = "Failed";
            } else {
                const output = String(result.Output ?? "").trim();
                const hadStreamOutput = elements.outputContent.children.length > 0;

                if (output) {
                    if (looksLikeErrorOutput(output)) {
                        const errorText = /^error:/i.test(output) ? output : `Error: ${output}`;
                        appendOutput(errorText, "error");
                        elements.outputBadge.className = "output-badge error";
                        elements.outputBadge.textContent = "Error";
                        return;
                    }

                    const lines = output.split('\n');
                    for (const line of lines) {
                        const trimmedLine = line.trim();
                        if (trimmedLine) {
                            appendOutput(trimmedLine, "result");
                        }
                    }
                    elements.outputBadge.className = "output-badge success";
                    elements.outputBadge.textContent = "Done";
                } else if (!hadStreamOutput) {
                    appendOutput("No output. Add at least one runnable form like !(...).", "info");
                    elements.outputBadge.className = "output-badge";
                    elements.outputBadge.textContent = "";
                } else {
                    elements.outputBadge.className = "output-badge success";
                    elements.outputBadge.textContent = "Done";
                }
            }
        } catch (prologError) {
            appendOutput(`Prolog Error: ${prologError.message || prologError}`, "error");
            elements.outputBadge.className = "output-badge error";
            elements.outputBadge.textContent = "Error";
        }
    } catch (err) {
        appendOutput(`Error: ${err.message || String(err)}`, "error");
        elements.outputBadge.className = "output-badge error";
        elements.outputBadge.textContent = "Error";
    } finally {
        const elapsed = performance.now() - startTime;
        elements.executionTime.textContent = `${elapsed.toFixed(1)}ms`;

        // Reset UI
        elements.runBtn.classList.remove("running");
        elements.runBtn.querySelector("span").textContent = "Run";
        setStatus("ready", "Ready");
        isRunning = false;
    }
}

elements.runBtn.addEventListener("click", runCode);

// ===== Initialize SWI-Prolog WASM =====
async function initPeTTa() {
    try {
        setLoadingStep("Initializing SWI-Prolog WebAssembly...", 20);

        // Initialize SWIPL
        swipl = await SWIPL({
            arguments: ["-q"],
            on_output: (line) => {
                if (line && line.trim()) {
                    // Classify output lines
                    const trimmed = line.trim();
                    
                    // Strip ANSI codes 
                    const clean = trimmed.replace(/\x1b\[[0-9;]*m/g, "");
                    if (!clean) return;
                    
                    // Skip internal compilation messages
                    if (clean.startsWith("-->")) return;
                    if (clean.startsWith("^^^")) return;
                    
                    // Detect test results
                    if (clean.includes("âœ…")) {
                        appendOutput(clean, "test-pass");
                    } else if (clean.includes("âŒ")) {
                        appendOutput(clean, "test-fail");
                    } else if (clean.startsWith("Error:") || clean.startsWith("error(")) {
                        appendOutput(clean, "error");
                    } else if (clean.startsWith("Result:")) {
                        appendOutput(clean.replace("Result: ", ""), "result");
                    } else {
                        appendOutput(clean, "result");
                    }
                }
            },
        });

        setLoadingStep("Loading PeTTa language runtime...", 50);

        // Fetch the PeTTa bundle (with cache bypass so it always gets the latest version)
        const response = await fetch("petta_bundle.pl?t=" + new Date().getTime());
        if (!response.ok) {
            throw new Error(`Failed to load petta_bundle.pl: ${response.status}`);
        }
        const bundleCode = await response.text();

        setLoadingStep("Compiling PeTTa Prolog sources...", 70);

        // Load the bundle into SWI-Prolog
        await swipl.prolog.load_string(bundleCode, "petta_bundle.pl");

        setLoadingStep("PeTTa runtime ready!", 100);

        // Brief delay so the user sees "ready"
        await new Promise((resolve) => setTimeout(resolve, 500));

        // Hide loading overlay
        elements.loadingOverlay.classList.add("hidden");
        setTimeout(() => {
            elements.loadingOverlay.style.display = "none";
        }, 500);

        // Enable Run button
        elements.runBtn.disabled = false;
        setStatus("ready", "Ready");

    } catch (err) {
        console.error("PeTTa initialization failed:", err);
        setLoadingStep(`Error: ${err.message}`, 0);
        elements.progressBar.style.background = "var(--accent-red)";
        setStatus("error", "Failed to load");
        
        // Show error in output panel too
        elements.loadingOverlay.classList.add("hidden");
        setTimeout(() => {
            elements.loadingOverlay.style.display = "none";
        }, 500);
        appendOutput(`Failed to initialize PeTTa: ${err.message}`, "error");
        appendOutput("Please check your internet connection and reload the page.", "info");
    }
}

// ===== Start =====
document.addEventListener("DOMContentLoaded", () => {
    initPeTTa();
});
