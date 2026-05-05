#!/usr/bin/env bash
# Apply Deno compatibility patches to the generated AtomVM.mjs.
# Handles both expanded (custom FissionVM build) and minified
# (Popcorn pre-built) variants of the file.
# Run after `mix popcorn.cook --include-vm` regenerates the file.
# See scripts/atomvm_deno.patch for rationale.

set -e

TARGET="supabase/functions/taskweft-edge/AtomVM.mjs"

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: $TARGET not found. Run 'mix popcorn.cook --include-vm' first." >&2
  exit 1
fi

echo "Patching $TARGET for Deno/Supabase Edge Runtime compatibility..."

# ── Hunk 1 (expanded format): minimum_runtime_check IIFE ─────────────────────
# Only present in custom-built FissionVM; minified Popcorn runtime skips this.
if grep -q "typeof process !== \"undefined\" && process.versions" "$TARGET"; then
  sed -i '' \
    's/var currentNodeVersion = typeof process !== "undefined" && process\.versions?\.node ? humanReadableVersionToPacked(process\.versions\.node) : TARGET_NOT_SUPPORTED;/var currentNodeVersion = TARGET_NOT_SUPPORTED; \/\/ patched for Deno\/non-browser/' \
    "$TARGET"
  echo "  [hunk 1] minimum_runtime_check patched"
else
  echo "  [hunk 1] minimum_runtime_check not found (minified build) — skipping"
fi

# ── Hunk 2: ENVIRONMENT_IS_NODE — force false (both expanded and minified) ────
# Expanded:   var ENVIRONMENT_IS_NODE = globalThis.process?.versions?.node && ...;
# Minified:   var ENVIRONMENT_IS_NODE=globalThis.process?.versions?.node&&...
if grep -q "ENVIRONMENT_IS_NODE=globalThis.process" "$TARGET"; then
  # Minified form
  sed -i '' \
    's/var ENVIRONMENT_IS_NODE=globalThis\.process?\.versions?\.node&&globalThis\.process?\.type!="renderer"/var ENVIRONMENT_IS_NODE=false\/\*patched for Deno\*\//' \
    "$TARGET"
  echo "  [hunk 2] ENVIRONMENT_IS_NODE (minified) patched"
elif grep -q 'ENVIRONMENT_IS_NODE = globalThis.process' "$TARGET"; then
  # Expanded form
  sed -i '' \
    's/var ENVIRONMENT_IS_NODE = globalThis\.process?\.versions?\.node && globalThis\.process?\.type != "renderer";/var ENVIRONMENT_IS_NODE = false; \/\/ patched for Deno/' \
    "$TARGET"
  echo "  [hunk 2] ENVIRONMENT_IS_NODE (expanded) patched"
else
  echo "  [hunk 2] ENVIRONMENT_IS_NODE not found — skipping"
fi

# ── Hunk 3 (expanded format): node-env assert ─────────────────────────────────
if grep -q 'assert(!ENVIRONMENT_IS_NODE, "node environment detected' "$TARGET"; then
  sed -i '' \
    's/assert(!ENVIRONMENT_IS_NODE, "node environment detected but not enabled at build time/\/\/ patched: assert(!ENVIRONMENT_IS_NODE, "node environment detected but not enabled at build time/' \
    "$TARGET"
  echo "  [hunk 3] node-env assert patched"
else
  echo "  [hunk 3] node-env assert not found (minified build) — skipping"
fi

echo "Done. Applied patches:"
grep -n "patched" "$TARGET" | head -10 || echo "  (no 'patched' markers — check file is correct)"
