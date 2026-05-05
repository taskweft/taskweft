import Config

# Popcorn WASM build configuration.
# `mix popcorn.cook` reads these to produce artifacts in out_dir.
# The unix target can be used for local testing: `mix popcorn.cook --target unix`
config :popcorn,
  out_dir: "supabase/functions/taskweft-edge",
  start: Taskweft.Edge,
  extra_apps: [:inets, :ssl, :public_key, :crypto, :eex, :asn1],
  runtime: {:path, "popcorn_runtime_source/artifacts/wasm", target: :wasm}
