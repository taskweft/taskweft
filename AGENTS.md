# AGENTS.md — multiplayer-fabric-taskweft

Guidance for AI coding agents working in this submodule.

## What this is

Pure Elixir HTN planner, ReBAC engine, and temporal scheduler — compiled to
AtomVM WebAssembly via Popcorn for deployment as a Supabase Edge Function.
The C++ NIF from `taskweft_nif` has been fully replaced by pure Elixir
fallbacks in `lib/taskweft/`.

## Toolchain

**Version manager: mise** (not Homebrew).  `.mise.toml` pins OTP 26.0.2 +
Elixir 1.17.3 — the exact versions Popcorn requires.

```sh
mise install       # install OTP 26.0.2 + Elixir 1.17.3
mise exec -- elixir --version   # verify: Elixir 1.17.3 / OTP 26
```

## Build and test (normal BEAM)

```sh
mix deps.get
mix compile
mix test --exclude red --exclude integration
# → 78 tests (30 property suites × 1000 samples + 48 unit tests), 0 failures
```

## Popcorn WASM build

```sh
# One-time: build the AtomVM WASM runtime (~15 min, requires Emscripten)
mise exec -- mix popcorn.build_runtime --target wasm

# Compile Elixir → AtomVM bytecode bundle + include WASM VM
mise exec -- mix popcorn.cook --include-vm

# Artifacts land in supabase/functions/taskweft-edge/:
#   bundle.avm       (16 MB)  — Elixir/Erlang bytecode
#   AtomVM.wasm      (4.3 MB) — AtomVM WASM VM
#   AtomVM.mjs       (315 KB) — AtomVM JS module
#   popcorn.js       (13 KB)  — Popcorn JS bridge
#   popcorn_iframe.js (5 KB)  — iframe communication shim
```

## Supabase Edge Function — compatibility status

| Step | Status |
|---|---|
| Elixir → AtomVM bytecode (`mix popcorn.cook`) | **Done** |
| AtomVM WASM runtime (`mix popcorn.build_runtime`) | **Done** |
| Supabase Postgres connection (`Taskweft.Repo`) | **Done** |
| Runtime in Deno (Supabase Edge Functions) | **Blocked** — see below |

### Runtime blockers

**Blocker 1 (hard): iframe bridge.**
`popcorn.js` runs AtomVM inside a browser `<iframe>` and communicates via
`postMessage`.  Deno has no DOM.  Fix: rewrite the bridge as a Deno `Worker`
that instantiates `AtomVM.wasm` directly via `WebAssembly.instantiate`.

**Blocker 2 (medium): SharedArrayBuffer.**
AtomVM WASM uses threads, which require `SharedArrayBuffer`.  Browsers and
Deno both support it, but it needs `Cross-Origin-Opener-Policy: same-origin`
and `Cross-Origin-Embedder-Policy: require-corp` headers — not injected by
Supabase today.  Alternative: rebuild AtomVM with `-DAVM_NO_SMP=ON` for
single-threaded (no `SharedArrayBuffer` needed).

## Architecture — NIF fallbacks

All 20 C++ NIF functions have pure Elixir counterparts in `lib/taskweft/`.
The long-term approach is to back-port these into `taskweft-nif` as NIF
fallback stubs (replacing `nif_error` with real implementations).  AtomVM
silently skips `@on_load`, so the Elixir path activates automatically in WASM
with no conditional logic.

## Module map

| Module | Responsibility |
|---|---|
| `Taskweft` | Public API: `plan/3`, `replan/3`, `check_temporal/4`, `rebac_*` |
| `Taskweft.NIF` | NIF fallback stubs — delegates to modules below |
| `Taskweft.Planner` | HTN planner: check/set body ops, method decomposition, rollback |
| `Taskweft.ReBAC` | Graph engine: edges, RelExpr eval, IS_MEMBER_OF transitivity |
| `Taskweft.Temporal` | ISO 8601 scheduler — civil (calendar-accurate) + fixed units |
| `Taskweft.Iso8601Duration` | Duration parser (spec: `lean/Planner/Iso8601Duration.lean`) |
| `Taskweft.Bridge` | Content/entity extraction utilities |
| `Taskweft.MCExecutor` | Monte Carlo stochastic plan executor |
| `Taskweft.Repo` | Ecto.Repo → Supabase Postgres (`hglmgarxgfgtxlmexkfp`) |
| `Taskweft.Edge` | AtomVM entry point for the edge function |

## Database

**Supabase Postgres** (project `hglmgarxgfgtxlmexkfp`) replaces exqlite/SQLite.
Copy `.env.example` to `.env` and fill in `SUPABASE_DB_PASSWORD`.

```sh
cp .env.example .env
# edit .env — set SUPABASE_DB_PASSWORD
```

Connection uses the Supabase PgBouncer pooler (port 6543) with TLS.

## Conventions

- All public functions return `{:ok, value}` or `{:error, reason}`.
- Property tests: `mix test --exclude red --exclude integration`.
- `:red`-tagged tests are TDD stubs for unimplemented features (KHR interactivity eval nodes).
- Commit messages: sentence case, no conventional-commit prefix.
  Example: `Add civil time support to Temporal scheduler`
