#!/usr/bin/env bash
# Build the Supabase Edge Function WASM artifacts end-to-end.
#
# Prerequisites:
#   mise install           # OTP 26.0.2 + Elixir 1.17.3
#   brew install emscripten cmake  # for build_runtime
#
# Run from the repo root:
#   bash scripts/build_edge_function.sh [--skip-runtime]

set -e
cd "$(dirname "$0")/.."

SKIP_RUNTIME=0
for arg in "$@"; do
  [[ "$arg" == "--skip-runtime" ]] && SKIP_RUNTIME=1
done

echo "==> Step 1: fetch deps"
mise exec -- mix deps.get

if [[ $SKIP_RUNTIME -eq 0 ]]; then
  echo "==> Step 2: build AtomVM WASM runtime (~15 min, one-time)"
  mise exec -- mix popcorn.build_runtime --target wasm \
    --cmake-opts "CMAKE_EXE_LINKER_FLAGS=-sINITIAL_MEMORY=134217728"
else
  echo "==> Step 2: skipped (--skip-runtime)"
fi

echo "==> Step 3: compile Elixir -> bundle.avm"
mise exec -- mix popcorn.cook

echo "==> Step 4: copy custom 128 MB AtomVM runtime artifacts"
cp popcorn_runtime_source/artifacts/wasm/AtomVM.wasm supabase/functions/taskweft-edge/
cp popcorn_runtime_source/artifacts/wasm/AtomVM.mjs  supabase/functions/taskweft-edge/
cp deps/popcorn/priv/static-template/wasm/popcorn.js         supabase/functions/taskweft-edge/
cp deps/popcorn/priv/static-template/wasm/popcorn_iframe.js  supabase/functions/taskweft-edge/

echo "==> Step 5: apply Deno compatibility patches to AtomVM.mjs"
bash scripts/patch_atomvm_deno.sh

echo ""
echo "Build complete. Artifacts in supabase/functions/taskweft-edge/:"
ls -lh supabase/functions/taskweft-edge/*.{avm,wasm,mjs,js,ts} 2>/dev/null || true

echo ""
echo "To test locally with Deno:"
echo "  cd supabase/functions/taskweft-edge"
echo "  deno run --allow-read --allow-net test_worker.ts"
echo ""
echo "To deploy:"
echo "  supabase functions deploy taskweft-edge"
