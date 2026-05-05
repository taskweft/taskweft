/**
 * Supabase Edge Function: taskweft-edge
 *
 * Loads the Popcorn-generated AtomVM WASM bundle and routes HTTP requests
 * into the Elixir Taskweft.Edge process.
 *
 * Prerequisites:
 *   1. Run `mix popcorn.cook` to generate the .avm bundle and atomvm.wasm
 *   2. Place the generated files under supabase/functions/taskweft-edge/
 *   3. Add static_files entries in supabase/config.toml (see below)
 *
 * supabase/config.toml excerpt:
 *   [functions.taskweft-edge]
 *   static_files = [
 *     "./functions/taskweft-edge/taskweft.avm",
 *     "./functions/taskweft-edge/atomvm.wasm",
 *   ]
 *
 * Known limitations (see README notes in this PR):
 *   - Popcorn requires COOP/COEP headers for SharedArrayBuffer; Supabase
 *     Edge Functions do not inject these by default.
 *   - AtomVM does not support Erlang NIFs — taskweft_nif, exqlite, and jaxon
 *     must be excluded from the WASM build.
 *   - The AtomVM Wasm runtime is designed for browsers; Deno compatibility
 *     is untested upstream and may require shimming browser globals.
 */

import { AtomVM } from "./atomvm.js";

const avm = await fetch(new URL("./taskweft.avm", import.meta.url));
const avmBytes = new Uint8Array(await avm.arrayBuffer());

const vm = await AtomVM.init({
  wasmPath: new URL("./atomvm.wasm", import.meta.url).pathname,
});

vm.load(avmBytes);

const edgePid = vm.spawn("Elixir.Taskweft.Edge", "main", []);

Deno.serve(async (req: Request) => {
  const body = await req.json().catch(() => ({}));

  const responsePromise = new Promise<Record<string, unknown>>((resolve) => {
    const self = vm.self();
    vm.send(edgePid, { request: self, body });
    vm.receive(self, ({ response }) => resolve(response));
  });

  const result = await responsePromise;

  return new Response(JSON.stringify(result), {
    headers: {
      "Content-Type": "application/json",
      // Required for AtomVM SharedArrayBuffer usage — may need Supabase
      // support or a reverse-proxy to inject these.
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
    },
  });
});
