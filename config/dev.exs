import Config

# Popcorn WASM build configuration.
# `mix popcorn.cook` reads these to produce artifacts in out_dir.
# The unix target can be used for local testing: `mix popcorn.cook --target unix`
config :popcorn,
  out_dir: "supabase/functions/taskweft-edge",
  start: Taskweft.Edge,
  # Use Popcorn's pre-built FissionVM runtime: :ssl, :inets, :public_key,
  # :crypto, :asn1 are compiled as native C into that runtime — no BEAM
  # bytecode needed, no :ssl crash.  Custom runtime only when you need
  # >16 MB heap (then rebuild via scripts/patch_atomvm_deno.sh).
  extra_apps: [:inets, :ssl, :public_key, :crypto, :eex, :asn1]
