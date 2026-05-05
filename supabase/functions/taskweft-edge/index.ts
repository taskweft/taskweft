/**
 * Supabase Edge Function: taskweft-edge
 *
 * ## Build status
 *
 *   ✓  `mix popcorn.cook`           → bundle.avm (16 MB) — Elixir bytecode compiled
 *   ✓  `mix popcorn.build_runtime`  → AtomVM.wasm (4.3 MB) — WASM VM compiled
 *   ✓  `mix popcorn.cook --include-vm` → all artifacts in this directory
 *   ✗  Runtime in Deno/Supabase    — see blockers below
 *
 * ## Popcorn's browser-only JS bridge
 *
 * `popcorn.js` (315 KB) runs the AtomVM WASM binary inside an <iframe> and
 * communicates via `postMessage`.  This architecture assumes a browser DOM.
 * Deno (Supabase Edge Functions runtime) has no `document`, no `<iframe>`,
 * and `postMessage` is scoped to Web Workers only.
 *
 * ## Blockers (in priority order)
 *
 *   1. **No iframe / postMessage bridge in Deno.**
 *      `popcorn.js` uses `document.createElement("iframe")`.  Deno has no DOM.
 *      Fix: load AtomVM.wasm directly in a Deno Worker using the AtomVM C API
 *      instead of the Popcorn browser shim.
 *
 *   2. **SharedArrayBuffer requires COOP/COEP headers.**
 *      AtomVM WASM uses threads (SharedArrayBuffer).  These headers must be
 *      set on the response *and* on the Supabase function's TLS endpoint —
 *      something Supabase does not support today for edge functions.
 *      Fix: Supabase would need to add COOP/COEP header injection, or the
 *      AtomVM WASM build must be recompiled without SharedArrayBuffer (single-
 *      threaded mode: `-DAVM_NO_SMP=ON`).
 *
 *   3. **bundle.avm size (16 MB / 6.7 MB gzipped).**
 *      Supabase Edge Function bundles are currently limited to ~150 MB total,
 *      so size is not a hard blocker, but cold-start latency will be non-trivial.
 *
 * ## What works today
 *
 *   - Pure Elixir compilation through AtomVM (bundle.avm) — fully confirmed.
 *   - All 20 NIF functions have pure Elixir fallbacks passing 78 tests.
 *   - Supabase Postgres connection configured (Taskweft.Repo).
 *
 * ## Path to Supabase compatibility
 *
 * Option A (recommended): Fork AtomVM's JS glue to produce a Deno Worker loader
 * instead of the iframe bridge.  The WASM binary itself is already correct.
 *
 * Option B: Use Popcorn's `:unix` target, build a standalone binary, and run it
 * inside a Docker container deployed to Supabase Edge Runtime (not a function).
 *
 * ## Usage once the bridge is ported
 *
 *   import { Popcorn } from "./popcorn.js";
 *
 *   const popcorn = await Popcorn.init({ wasmDir: "./" });
 *
 *   Deno.serve(async (req: Request) => {
 *     const body = await req.json().catch(() => ({}));
 *     const result = await popcorn.call(body, {
 *       process: "Elixir.Taskweft.Edge",
 *       timeoutMs: 30_000,
 *     });
 *     return new Response(JSON.stringify(result.data), {
 *       headers: {
 *         "Content-Type": "application/json",
 *         "Cross-Origin-Opener-Policy": "same-origin",
 *         "Cross-Origin-Embedder-Policy": "require-corp",
 *       },
 *     });
 *   });
 *
 * ## supabase/config.toml static_files
 *
 *   [functions.taskweft-edge]
 *   static_files = [
 *     "./functions/taskweft-edge/bundle.avm",
 *     "./functions/taskweft-edge/AtomVM.wasm",
 *     "./functions/taskweft-edge/AtomVM.mjs",
 *     "./functions/taskweft-edge/popcorn.js",
 *     "./functions/taskweft-edge/popcorn_iframe.js",
 *   ]
 */

// Placeholder — replace with a Deno-compatible AtomVM WASM loader once
// the iframe bridge is ported (see Option A above).
Deno.serve((_req: Request) => {
  return new Response(
    JSON.stringify({
      status: "not_ready",
      reason: "Popcorn browser bridge not yet ported to Deno",
      artifacts: ["bundle.avm", "AtomVM.wasm", "AtomVM.mjs", "popcorn.js"],
      next_step:
        "Port popcorn.js iframe bridge to Deno Worker + direct WASM instantiation",
    }),
    { headers: { "Content-Type": "application/json" } }
  );
});
