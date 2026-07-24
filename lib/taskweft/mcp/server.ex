# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.MCP.Server do
  @moduledoc """
  MCP server for Taskweft.
  """

  use ExMCP.Server.Handler
  use ExMCP.Server.DSL, name: "taskweft"

  # ---------- TOOLS ----------

  tool "plan",
       "Run the IPyHOP-style HTN planner over an Elixir DSL or JSON-LD domain. Returns the plan as JSON." do
    param(:domain_dsl, :string,
      required: true,
      description: """
      A RECTGTN HTN domain in Elixir DSL or JSON-LD format.

      **Elixir DSL** (preferred - valid Elixir code with module attributes):

          defmodule MyDomain do
            use Taskweft.DSL
            @name "my_domain"
            @variables %{pos: %{type: :ref, init: %{a: "table"}}}
            @todo_list [[:pickup, :a]]
          end

      **JSON-LD** (full Linked Data):

          {"@context": {...}, "@type": "domain:Definition", "name": "...", ...}

      Pass "format": "dsl" for DSL input, "json" or "yaml" for JSON-LD/YAML-LD.
      Defaults to "dsl".
      """
    )

    run(fn args, state ->
      guarded(state, fn ->
        with {:ok, domain_dsl} <- parse_domain_input(Map.fetch!(args, :domain_dsl), Map.get(args, :format, "dsl")),
             explain = Map.get(args, :explain, false) do
          plan_with_optional_explain(domain_dsl, explain)
        end
      end)
    end)
  end

  tool "replan",
       "Recover from a failed plan step using Elixir DSL or JSON-LD domain" do
    param(:domain_dsl, :string,
      required: true,
      description: "A RECTGTN HTN domain in Elixir DSL or JSON-LD format. See `plan` tool description for format details."
    )

    run(fn args, state ->
      guarded(state, fn ->
        with {:ok, domain_dsl} <- parse_domain_input(Map.fetch!(args, :domain_dsl), Map.get(args, :format, "dsl")),
             plan_arg = Map.fetch!(args, :plan_json),
             fail_step = Map.get(args, :fail_step, -1),
             {:ok, steps} <- decode_plan(plan_arg),
             :ok <- validate_fail_step(steps, fail_step),
             :ok <- validate_for_replan(domain_dsl),
             {:ok, plan_json} <- Jason.encode(%{"plan" => steps}),
             :ok <- validate_for_replan(plan_json) do
          Taskweft.replan(plan_json, Jason.encode!(steps), fail_step)
        else
          {:error, reason} -> {:error, reason}
        end
      end)
    end)
  end

  tool "validate",
       "Validate a RECTGTN domain/problem document in Elixir DSL or JSON-LD format. Returns the normalized document JSON on success, or a validation error. plan/replan do not validate — call this first if you want to check a document's shape without also attempting to solve it." do
    param(:domain_dsl, :string,
      required: true,
      description: "A RECTGTN HTN domain in Elixir DSL or JSON-LD format. See `plan` tool description for format details."
    )

    run(fn args, state ->
      guarded(state, fn ->
        with {:ok, domain_dsl} <- parse_domain_input(Map.fetch!(args, :domain_dsl), Map.get(args, :format, "dsl")) do
          validate_domain(domain_dsl)
        end
      end)
    end)
  end

  # ---------- HELPERS ----------

  alias Taskweft.DSL

  defp parse_domain_input(raw, "json") do
    case Jason.decode(raw) do
      {:ok, _map} -> {:ok, raw}
      {:error, reason} -> {:error, "invalid JSON-LD: #{reason}"}
    end
  end

  defp parse_domain_input(raw, "yaml") do
    case YamlElixir.read_from_string(raw) do
      {:ok, parsed} when is_map(parsed) -> {:ok, Jason.encode!(parsed)}
      {:ok, _} -> {:error, "YAML-LD input must decode to a map (got a list or scalar)"}
      {:error, reason} -> {:error, "invalid YAML-LD: #{reason}"}
    end
  end

  defp parse_domain_input(raw, "dsl") do
    Taskweft.DSL.compile(raw)
  end

  defp parse_domain_input(_raw, other) do
    {:error, ~s(unknown format: #{other}. Use "dsl", "json", or "yaml".)}
  end

  defp plan_with_optional_explain(domain_json, explain) do
    case validate_domain(domain_json) do
      _ok -> do_plan(domain_json, explain)
    end
  end

  defp do_plan(domain_json, false), do: Taskweft.plan(domain_json)
  defp do_plan(domain_json, true) do
    case Taskweft.plan_explain(domain_json) do
      {:ok, plan} ->
        with {:ok, domain} <- Jason.decode(domain_json),
             {:ok, explain_tree} <- Taskweft.explain_plan(domain_json) do
          {:ok, Jason.encode!(%{"plan" => plan, "explain_tree" => explain_tree})}
        else
          {:error, _reason} -> {:error, "Failed to explain plan"}
        end

      {:error, _reason} ->
        {:error, "Failed to explain plan"}
    end
  end

  defp validate_domain(domain_json) do
    with {:ok, domain} <- Jason.decode(domain_json),
         :ok <- Taskweft.Loader.validate(domain) do
      {:ok, Jason.encode!(domain)}
    else
      {:error, reason} -> {:error, "Validation error: #{reason}"}
    end
  end

  defp decode_plan(plan_json) do
    with {:ok, plan} <- Jason.decode(plan_json),
         :ok <- validate_plan(plan) do
      {:ok, plan}
    else
      {:error, reason} -> {:error, "Failed to decode plan: #{reason}"}
    end
  end

  defp validate_plan(plan) do
    # Basic validation of plan structure
    if is_list(plan) do
      :ok
    else
      {:error, "Plan must be a list of steps"}
    end
  end

  defp validate_fail_step(steps, fail_step) do
    if fail_step >= -1 and fail_step < length(steps) do
      :ok
    else
      {:error, "Invalid fail_step"}
    end
  end

  defp validate_for_replan(domain_json) do
    case Jason.decode(domain_json) do
      {:ok, domain} when is_map(domain) -> :ok
      {:ok, _} -> {:error, "Domain must decode to a map"}
      {:error, _} -> {:error, "Invalid domain JSON"}
    end
  end
end