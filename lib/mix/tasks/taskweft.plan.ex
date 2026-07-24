defmodule Mix.Tasks.Taskweft.Plan do
  @moduledoc """
  Load a DSL domain file, compile it, plan it, and print the plan JSON.

      mix taskweft.plan priv/plans/domains/blocks_world_dsl.ex

  Optionally pass an explain flag:

      mix taskweft.plan priv/plans/domains/blocks_world_dsl.ex --explain
  """

  use Mix.Task

  @shortdoc "Plan a DSL domain file from priv/plans/domains/"

  @switches [explain: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} = OptionParser.parse(args, switches: @switches)

    path =
      case positional do
        [p | _] -> p
        [] -> Mix.raise("Usage: mix taskweft.plan <path/to/domain_dsl.ex> [--explain]")
      end

    Mix.Task.run("app.start", [])

    dsl_source = File.read!(path)
    {:ok, compiled} = Taskweft.DSL.compile(dsl_source)

    if opts[:explain] do
      {:ok, result} = Taskweft.plan_explain(compiled)
      IO.puts(result)
    else
      {:ok, result} = Taskweft.plan(compiled)
      IO.puts(result)
    end
  end
end