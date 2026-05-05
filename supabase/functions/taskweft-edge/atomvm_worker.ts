/**
 * Deno Worker — runs AtomVM WASM directly, adapted from popcorn_iframe.js.
 *
 * Three environment patches are applied before AtomVM.mjs loads:
 *  1. Hide process.versions.node — Emscripten's runtime check throws if it
 *     detects Node.js (Deno exposes process for Node compat).
 *  2. Expose WorkerGlobalScope — AtomVM.mjs requires this to be truthy to
 *     enter Worker mode (ENVIRONMENT_IS_WORKER = !!globalThis.WorkerGlobalScope).
 *  3. Keep window undefined — ensures ENVIRONMENT_IS_WEB stays false so
 *     AtomVM treats this as a Worker, not a browser main thread.
 *
 * SharedArrayBuffer note: In Deno Workers, SharedArrayBuffer is available
 * server-side without COOP/COEP headers (that restriction is browser-only).
 * AtomVM uses it internally for Erlang thread (pthread) synchronization.
 */

// ── Patch 1: hide Node.js process so Emscripten doesn't detect Deno ──────────
const _savedProcess = (globalThis as Record<string, unknown>).process;
(globalThis as Record<string, unknown>).process = undefined;

// ── Patch 2: expose WorkerGlobalScope so ENVIRONMENT_IS_WORKER = true ─────────
if (!globalThis.WorkerGlobalScope) {
  (globalThis as Record<string, unknown>).WorkerGlobalScope =
    class WorkerGlobalScope {};
}

// ── Dynamic import AFTER patches (static imports are hoisted past patches) ────
const { default: initAtomVM } = await import("./AtomVM.mjs");

// Restore process for any code that legitimately needs it after AtomVM loads.
(globalThis as Record<string, unknown>).process = _savedProcess;

// ── Message constants (mirrors popcorn_iframe.js) ────────────────────────────
const MSG = {
  INIT: "popcorn-init",
  START_VM: "popcorn-startVm",
  CALL: "popcorn-call",
  CALL_ACK: "popcorn-callAck",
  STDOUT: "popcorn-stdout",
  STDERR: "popcorn-stderr",
  HEARTBEAT: "popcorn-heartbeat",
  RELOAD: "popcorn-reload",
} as const;

// deno-lint-ignore no-explicit-any
let AtomModule: any = null;

function send(type: string, data?: unknown) {
  self.postMessage({ type, value: data });
}

function deserialize(message: string): unknown {
  return JSON.parse(message, (_key, value) => {
    if (
      typeof value === "object" &&
      value !== null &&
      Object.hasOwn(value, "popcorn_ref") &&
      Object.getOwnPropertyNames(value).length === 1
    ) {
      return AtomModule?.trackedObjectsMap?.get(
        (value as Record<string, number>).popcorn_ref,
      );
    }
    return value;
  });
}

async function startVm(avmBundle: Int8Array): Promise<unknown> {
  return new Promise((resolve, reject) => {
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
      print(text: string) {
        send(MSG.STDOUT, text);
      },
      printErr(text: string) {
        send(MSG.STDERR, text);
      },
      onAbort() {
        setTimeout(() => send(MSG.RELOAD, null), 100);
      },
    })
      // deno-lint-ignore no-explicit-any
      .then((mod: any) => {
        AtomModule = mod;
        AtomModule["serialize"] = JSON.stringify;
        AtomModule["deserialize"] = deserialize;
        AtomModule["cleanupFunctions"] = new Map();
        AtomModule["onTrackedObjectDelete"] = (key: number) => {
          const fn = AtomModule["cleanupFunctions"].get(key);
          AtomModule["cleanupFunctions"].delete(key);
          try {
            fn?.();
          } finally {
            AtomModule["trackedObjectsMap"]?.delete(key);
          }
        };

        // FissionVM's pre.js defines onRunTrackedJs as eval(scriptString)
        // which evaluates but does NOT call the resulting function.
        // popcorn_iframe.js overrides it to call fn(Module).  We must do
        // the same so :emscripten.run_script_tracked works from Elixir.
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
        AtomModule["call"] = (process: string, args: unknown) =>
          origCall(process, JSON.stringify(args));

        AtomModule["onElixirReady"] = (initProcess: unknown) => {
          AtomModule["onElixirReady"] = null;
          resolve(initProcess);
        };
      })
      .catch(reject);
  });
}

// ── Boot ─────────────────────────────────────────────────────────────────────

send(MSG.INIT);

const bundleUrl = new URL("./bundle.avm", import.meta.url);
const bundleBuffer = await fetch(bundleUrl).then((r) => r.arrayBuffer());
const avmBundle = new Int8Array(bundleBuffer);

const initProcess = await startVm(avmBundle);

self.addEventListener("message", async ({ data }) => {
  if (data.type !== MSG.CALL) return;
  const { requestId, process, args } = data.value as {
    requestId: number;
    process: string;
    args: unknown;
  };
  send(MSG.CALL_ACK, { requestId });
  try {
    const result = await AtomModule.call(process, args);
    send(MSG.CALL, { requestId, data: AtomModule.deserialize(result) });
  } catch (error) {
    if (error === "noproc") {
      send(MSG.RELOAD, null);
      return;
    }
    send(MSG.CALL, { requestId, error: String(error) });
  }
});

send(MSG.START_VM, initProcess);
setInterval(() => send(MSG.HEARTBEAT, null), 500);
