/**
 * Standalone Deno test — verifies AtomVM WASM loads and the Elixir
 * Taskweft.Edge module responds to a ping without Supabase / Docker.
 *
 * Run from the repo root:
 *   deno run --allow-read --allow-net \
 *     supabase/functions/taskweft-edge/test_worker.ts
 */

const TIMEOUT_MS = 30_000;

// ── Patch environment before AtomVM.mjs loads ─────────────────────────────────

// Hide Deno's Node.js compat layer: Emscripten throws if process.versions.node
// is set (AtomVM.mjs was not compiled for Node.js).
const _savedProcess = (globalThis as Record<string, unknown>).process;
(globalThis as Record<string, unknown>).process = undefined;

// Expose WorkerGlobalScope so ENVIRONMENT_IS_WORKER = true in AtomVM.mjs.
if (!globalThis.WorkerGlobalScope) {
  (globalThis as Record<string, unknown>).WorkerGlobalScope =
    class WorkerGlobalScope {};
}

const { default: initAtomVM } = await import("./AtomVM.mjs");

(globalThis as Record<string, unknown>).process = _savedProcess;

// ── Load bundle.avm ───────────────────────────────────────────────────────────

console.log("[test] Loading bundle.avm…");
const avmBytes = await Deno.readFile(
  new URL("./bundle.avm", import.meta.url),
);
const avmBundle = new Int8Array(avmBytes.buffer);
console.log(`[test] bundle.avm: ${(avmBytes.byteLength / 1024 / 1024).toFixed(1)} MB`);

// ── Start AtomVM ──────────────────────────────────────────────────────────────

console.log("[test] Starting AtomVM WASM…");

// deno-lint-ignore no-explicit-any
let AtomModule: any = null;

const vmReady = new Promise<void>((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error("VM boot timeout")), TIMEOUT_MS);

  initAtomVM({
    // 128 MB fits within Supabase's 150 MB external (SharedArrayBuffer) budget.
    INITIAL_MEMORY: 134_217_728,
    preRun: [
      // deno-lint-ignore no-explicit-any
      function ({ FS }: any) {
        FS.mkdir("/data");
        FS.writeFile("/data/bundle.avm", avmBundle);
      },
    ],
    arguments: ["/data/bundle.avm"],
    print: (t: string) => console.log("[atomvm stdout]", t),
    printErr: (t: string) => console.error("[atomvm stderr]", t),
    onAbort: () => reject(new Error("AtomVM aborted")),
  // deno-lint-ignore no-explicit-any
  }).then((mod: any) => {
    AtomModule = mod;
    AtomModule["serialize"] = JSON.stringify;
    AtomModule["deserialize"] = (s: string) => JSON.parse(s);

    // The FissionVM pre.js defines onRunTrackedJs as eval(scriptString)
    // which evaluates but does NOT call the function.  popcorn_iframe.js
    // overrides it to call fn(Module) — we must do the same so that
    // :emscripten.run_script_tracked works from Elixir.
    AtomModule["onRunTrackedJs"] = (scriptString: string) => {
      const indirectEval = eval;
      let fn: ((m: unknown) => unknown[]) | null = null;
      try {
        fn = indirectEval(scriptString) as (m: unknown) => unknown[];
      } catch (e) {
        console.error("[atomvm] onRunTrackedJs eval error:", e);
        return null;
      }
      let result: unknown[] | null = null;
      try {
        result = fn!(AtomModule) as unknown[];
      } catch (e) {
        console.error("[atomvm] onRunTrackedJs call error:", e);
        return null;
      }
      const trackValue = (val: unknown) => {
        const key = AtomModule["nextTrackedObjectKey"]();
        AtomModule["trackedObjectsMap"].set(key, val);
        return key;
      };
      return (result ?? []).map(trackValue);
    };

    const origCall = AtomModule["call"];
    AtomModule["call"] = (proc: string, args: unknown) =>
      origCall(proc, JSON.stringify(args));

    AtomModule["onElixirReady"] = (_initProcess: unknown) => {
      clearTimeout(timer);
      AtomModule["onElixirReady"] = null;
      console.log("[test] onElixirReady fired");
      resolve();
    };
  }).catch(reject);
});

await vmReady;
console.log("[test] AtomVM ready ✓");

// ── Call Taskweft.Edge.main ───────────────────────────────────────────────────

console.log('[test] Calling Elixir.Taskweft.Edge with {"action":"ping"}…');
try {
  const raw = await AtomModule.call(
    "Elixir.Taskweft.Edge",
    { action: "ping" },
  );
  const result = AtomModule.deserialize(raw);
  console.log("[test] Result:", JSON.stringify(result));

  if ((result as Record<string, string>)?.status === "ok") {
    console.log("[test] PASS ✓ — AtomVM + Elixir edge function responded correctly");
  } else {
    console.error("[test] FAIL — unexpected response:", result);
    Deno.exit(1);
  }
} catch (err) {
  console.error("[test] FAIL — call threw:", err);
  Deno.exit(1);
}

Deno.exit(0);
