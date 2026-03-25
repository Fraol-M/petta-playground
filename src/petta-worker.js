// src/petta-worker.js
import SWIPL from "swipl-wasm";
import pettaBundle from "../petta_bundle.pl?raw";

let swipl = null;
let runtimeOutputChunks = [];

function clearRuntimeOutput() {
    runtimeOutputChunks = [];
}

function readRuntimeOutput() {
    const raw = runtimeOutputChunks.join("");
    runtimeOutputChunks = [];
    return raw.replace(/\r/g, "").trim();
}

function suppressPrintlnTrueLines(code, output) {
    if (!output) return output;
    const printlnCalls = (code.match(/!\s*\(\s*println!(?=\s|\))/g) || []).length;
    if (printlnCalls <= 0) return output;

    let remaining = printlnCalls;
    const filtered = [];
    for (const line of output.split("\n")) {
        if (remaining > 0 && line.trim() === "true") {
            remaining--;
            continue;
        }
        filtered.push(line);
    }
    return filtered.join("\n").trim();
}

function mergeOutputs(code, runtimeOut, resultOut) {
    const cleanRuntime = (runtimeOut || "").trim();
    const cleanResult = (resultOut || "").trim();

    let merged = "";
    if (cleanRuntime && cleanResult) merged = `${cleanRuntime}\n${cleanResult}`;
    else if (cleanRuntime) merged = cleanRuntime;
    else merged = cleanResult;

    return suppressPrintlnTrueLines(code, merged);
}

async function ensureInit() {
    if (!swipl) {
        swipl = await SWIPL({
            arguments: ["-q"],
            on_output: (line) => {
                if (typeof line === "string" && line.length) {
                    runtimeOutputChunks.push(line);
                }
            }
        });

        await swipl.prolog.load_string(pettaBundle, "petta_bundle.pl");
    }
}

self.addEventListener("message", async (event) => {
    const { type, code, requestId } = event.data;
    
    if (type === "init") {
        try {
            await ensureInit();
            self.postMessage({ type: "ready" });
        } catch (err) {
            self.postMessage({ type: "error", error: err.message });
        }
        return;
    }
    
    if (type === "run") {
        try {
            await ensureInit();
            clearRuntimeOutput();
            
            // Clean state before running
            const resetResult = swipl.prolog.query("reset_metta_state").once();
            if (resetResult === false) {
                throw new Error("reset_metta_state failed");
            }

            // Run code
            // Escape code
            const escaped = code
                .replace(/\\/g, "\\\\")
                .replace(/"/g, '\\"')
                .replace(/\n/g, "\\n")
                .replace(/\r/g, "");

            const result = swipl.prolog.query(`metta_exec("${escaped}", result(Output, Err))`).once();
            const runtimeOutput = readRuntimeOutput();
            
            if (!result) {
                self.postMessage({ type: "error", error: "Execution failed (no result).", requestId });
            } else if (result.Err && result.Err !== "none") {
                self.postMessage({ type: "error", error: result.Err, requestId });
            } else {
                const output = mergeOutputs(code, runtimeOutput, result.Output || "");
                self.postMessage({ type: "result", output, requestId });
            }
        } catch (err) {
            clearRuntimeOutput();
            self.postMessage({ type: "error", error: err.message || String(err), requestId });
        }
    }
});
