/**
 * Supabase Edge Function: taskweft-edge
 *
 * Spawns a Deno Worker that runs AtomVM WASM (via atomvm_worker.ts) and
 * routes HTTP requests into the Elixir Taskweft.Edge process.
 *
 * Build prerequisites (run with OTP 26.0.2 + Elixir 1.17.3 via `mise install`):
 *
 *   mix popcorn.build_runtime --target wasm   # builds AtomVM.wasm (one-time)
 *   mix popcorn.cook --include-vm             # emits bundle.avm + all JS glue
 *
 * Local test:
 *   supabase start
 *   supabase functions serve taskweft-edge --no-verify-jwt
 *   curl -X POST http://localhost:54321/functions/v1/taskweft-edge \
 *     -H "Content-Type: application/json" \
 *     -d '{"action":"ping"}'
 *
 * SharedArrayBuffer note: AtomVM.wasm uses pthreads (SharedArrayBuffer for
 * thread sync).  In Deno Workers this is available server-side without
 * COOP/COEP headers.  We still set the headers on responses for forward
 * compatibility if the function is ever embedded in a browser context.
 */

type PendingCall = {
  resolve: (value: unknown) => void;
  reject: (reason: unknown) => void;
};

// Spawn AtomVM worker once at module level so the VM stays warm across requests.
const worker = new Worker(
  new URL("./atomvm_worker.ts", import.meta.url),
  { type: "module" },
);

let nextId = 0;
const pending = new Map<number, PendingCall>();
let vmReady = false;
const readyWaiters: Array<() => void> = [];

worker.addEventListener("message", ({ data }) => {
  switch (data.type) {
    case "popcorn-init":
      console.log("[taskweft-edge] AtomVM initializing…");
      break;

    case "popcorn-startVm":
      console.log("[taskweft-edge] AtomVM ready");
      vmReady = true;
      readyWaiters.splice(0).forEach((fn) => fn());
      break;

    case "popcorn-call": {
      const { requestId, data: result, error } = data.value as {
        requestId: number;
        data?: unknown;
        error?: string;
      };
      const call = pending.get(requestId);
      if (!call) break;
      pending.delete(requestId);
      if (error) call.reject(new Error(error));
      else call.resolve(result);
      break;
    }

    case "popcorn-stdout":
      console.log("[atomvm]", data.value);
      break;

    case "popcorn-stderr":
      console.error("[atomvm]", data.value);
      break;

    case "popcorn-reload":
      console.warn("[taskweft-edge] AtomVM crashed, worker reloading…");
      vmReady = false;
      break;
  }
});

worker.addEventListener("error", (e) => {
  console.error("[taskweft-edge] Worker error:", e.message);
  for (const [id, call] of pending) {
    pending.delete(id);
    call.reject(new Error("worker error: " + e.message));
  }
});

function waitForVm(): Promise<void> {
  if (vmReady) return Promise.resolve();
  return new Promise((resolve) => readyWaiters.push(resolve));
}

function callElixir(process: string, args: unknown): Promise<unknown> {
  const requestId = ++nextId;
  return new Promise((resolve, reject) => {
    pending.set(requestId, { resolve, reject });
    worker.postMessage({
      type: "popcorn-call",
      value: { requestId, process, args },
    });
  });
}

Deno.serve(async (req: Request) => {
  await waitForVm();

  const body = await req.json().catch(() => ({}));

  try {
    const result = await callElixir("Elixir.Taskweft.Edge", body);
    return new Response(JSON.stringify(result), {
      headers: {
        "Content-Type": "application/json",
        // Set for forward compatibility; Deno Workers don't need these
        // server-side, but browsers loading the response do.
        "Cross-Origin-Opener-Policy": "same-origin",
        "Cross-Origin-Embedder-Policy": "require-corp",
      },
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
