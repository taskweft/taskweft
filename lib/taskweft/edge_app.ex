defmodule Taskweft.EdgeApp do
  @moduledoc """
  OTP Application entry point for the AtomVM/Popcorn WASM build.

  When `Application.ensure_all_started(:taskweft)` is called by Popcorn's
  boot module, this starts a supervisor whose child is a Task running
  `Taskweft.Edge.start/0`.  The Popcorn boot module (with `start_module: nil`)
  detects the supervisor via `:application.get_supervisor/1` and monitors it,
  keeping AtomVM alive while `Taskweft.Edge` is running.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task, &Taskweft.Edge.start/0}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Taskweft.EdgeSupervisor)
  end
end
