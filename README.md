<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 K. S. Ernest (iFire) Lee -->

# multiplayer-fabric-taskweft

Elixir library wrapping a C++20 HTN planner NIF, plus a **single
self-contained standalone binary** (`taskweft`) that exposes both the
Taskweft CLI and the Taskweft MCP server — no Erlang/Elixir/CMake toolchain
required at runtime.

The binary is produced with [Burrito](https://github.com/burrito-elixir/burrito):
one file per target triplet, with the planner NIF bundled inside.

## Standalone binary

Download the binary for your platform from the
[latest release](https://github.com/V-Sekai-fire/multiplayer-fabric-taskweft/releases)
(e.g. `taskweft_windows_amd64.exe`), then:

```sh
taskweft plan <domain.jsonld>                     # plan from a self-contained file
taskweft plan --problem <domain> <problem>        # plan from split domain + problem
taskweft plan                                     # plan from JSON-LD on stdin
taskweft temporal <domain> [problem]              # plan + STN temporal metadata (JSON)
taskweft simulate <domain> [problem]              #   opts: --probs <json> --seed <int>
taskweft replan <fail_step> <domain> [problem]    # replan after a step failure (JSON)
taskweft mcp                                       # MCP server over stdio
taskweft mcp --http [--port N] [--host H]          # MCP server over HTTP
taskweft version                                   # version + build commit
taskweft help                                      # usage
```

`plan` prints the bare JSON step array (`[["a_walk", "alice", "2"], ...]`),
identical to the historical C++ CLI, so existing callers are unaffected. A
bare `taskweft <domain.jsonld>` (no subcommand) plans that file, and the
legacy `--temporal` / `--simulate` / `--replan` / `--problem` flag forms are
still accepted.

> **First run** self-extracts the bundled runtime into a per-user cache
> (`~/.local/share/.burrito` or `%LOCALAPPDATA%\.burrito`); subsequent runs
> start immediately.

### MCP client setup (Claude Code)

Point your MCP config at the binary — no `mix`, no `cwd`, no toolchain:

```json
{
  "mcpServers": {
    "taskweft": {
      "command": "/path/to/taskweft",
      "args": ["mcp"]
    }
  }
}
```

(On Windows, `"command": "C:\\path\\to\\taskweft_windows_amd64.exe"`.)

The server exposes the `plan`, `replan`, `simulate`, and `solve_minizinc`
tools and every bundled `priv/plans/{domains,problems}/*.jsonld` as a
resource.

## Building from source

Requires Elixir/OTP and, for the standalone binary, [Zig
0.15.2](https://ziglang.org/download/) (Burrito's cross-compiler backend).

```sh
mix deps.get
mix compile                 # builds the C++20 NIF via elixir_make
mix test --include property  # ExUnit + PropCheck

# Assemble the release (no Burrito wrap unless zig is present):
mix release taskweft

# Produce the standalone per-triplet binaries into ./burrito_out:
TASKWEFT_BURRITO=1 MIX_ENV=prod mix release taskweft            # all targets
TASKWEFT_BURRITO=1 BURRITO_TARGET=windows_amd64 \
  MIX_ENV=prod mix release taskweft                            # one target
```

Targets: `linux_amd64`, `linux_arm64`, `macos_arm64`, `windows_amd64`.
CI builds and attaches each on a tagged release (see
`.github/workflows/release.yml`).

`Taskweft.Release.wrap/1` skips the Burrito step when no zig toolchain is
present, so a plain `mix release taskweft` still assembles on any machine.
The commit stamped into `taskweft version` comes from the `TASKWEFT_COMMIT`
build-time environment variable.

## Repository layout

- `lib/taskweft/cli.ex` — the unified CLI dispatcher (`Taskweft.CLI`).
- `lib/taskweft/application.ex` — auto-runs the CLI only inside the Burrito
  binary; a no-op when used as a library dependency.
- `lib/taskweft/release.ex` — the toolchain-guarded Burrito wrap step.
- `lib/taskweft/jsonld/` — JSON-LD domain loader / validator.
- The planner NIF, MCP server, and bundled plans live in the sibling
  `taskweft-nif`, `taskweft-mcp`, and `taskweft-plans` packages.

See `AGENTS.md` and `CONTRIBUTING.md` for development conventions.
