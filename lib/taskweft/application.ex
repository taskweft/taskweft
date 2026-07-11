# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.Application do
  @moduledoc """
  OTP application for `:taskweft`.

  When `:taskweft` is used as a library dependency (or under `mix test` /
  `mix run`) this starts an empty supervision tree — no behaviour change for
  consumers. When the app boots as the standalone Burrito binary from issue
  #53, it starts a single `Task` that runs `Taskweft.CLI.main/0`, turning the
  binary into a CLI: subcommands that produce output print and halt, and
  `mcp` keeps the VM alive.

  The CLI is only auto-run when the app is running as a Burrito-wrapped
  standalone binary (`Burrito.Util.running_standalone?/0`, i.e. the `__BURRITO`
  runtime marker is set), so starting `:taskweft` as one dependency among many
  in another project's release does nothing. Set `TASKWEFT_CLI=0` to suppress
  it even in the standalone binary.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if run_cli?() do
        # `:temporary` so a crashing dispatcher can't be spin-restarted;
        # `main/1` is self-contained and halts the VM on completion.
        [Supervisor.child_spec({Task, fn -> Taskweft.CLI.main() end}, restart: :temporary)]
      else
        []
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: Taskweft.Supervisor)
  end

  defp run_cli? do
    System.get_env("TASKWEFT_CLI") != "0" and burrito_standalone?()
  end

  # The Burrito zig wrapper exports `__BURRITO=1` into the release runtime
  # (see burrito `src/erlang_launcher.zig`). Read it directly rather than
  # through `Burrito.Util`, whose module may not be loaded this early in boot.
  defp burrito_standalone? do
    System.get_env("__BURRITO") != nil
  end
end
