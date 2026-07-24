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
      """
    )

    param(:format, :string,
      default: "dsl",
      description: "Parse format - 'dsl' for Elixir DSL or 'json' for JSON-LD"
    )

    handle_with(fn args, state ->
      with {:ok, domain_dsl} <- parse_domain_input(Map.fetch!(args, :domain_dsl), Map.get(args, :format, "dsl")),
           {:ok, compiled} <- Taskweft.DSL.compile(domain_dsl),
           plan_json <- Jason.encode!(Map.get(compiled, :plan) || []),
           explain_json <- Jason.encode!(Map.get(compiled, :explain_tree) || %{}),
           {:ok, result} <- Taskweft.plan_with_optional_explain(plan_json, explain_json) do
        {:ok, %{content: Jason.encode!(result)}}
      else
        {:error, reason} -> {:ok, %{content: Jason.encode!(%{error: reason})}}
      end
    end)
  end

  tool "replan",
       "Replan after a step failure. Same interface as plan, but accepts a failed step index." do
    param(:domain_dsl, :string,
      required: true,
      description: "A RECTGTN HTN domain in Elixir DSL or JSON-LD format."
    )

    param(:format, :string,
      default: "dsl",
      description: "Parse format - 'dsl' for Elixir DSL or 'json' for JSON-LD"
    )

    param(:plan_json, :string,
      required: true,
      description: "JSON string containing the original plan from plan tool."
    )

    param(:fail_step, :integer,
      default: -1,
      description: "Step index to replan from (-1 for full replan)."
    )

    handle_with(fn args, state ->
      with {:ok, domain_dsl} <- parse_domain_input(Map.fetch!(args, :domain_dsl), Map.get(args, :format, "dsl")),
           {:ok, compiled} <- Taskweft.DSL.compile(domain_dsl),
           steps <- Jason.decode!(args[:plan_json]),
           fail_step <- Map.get(args, :fail_step, -1),
           {:ok, result} <- Taskweft.replan(steps, Jason.encode!(compiled), fail_step) do
        {:ok, %{content: Jason.encode!(result)}}
      else
        {:error, reason} -> {:ok, %{content: Jason.encode!(%{error: reason})}}
      end
    end)
  end

  tool "validate",
       "Validate a RECTGTN HTN domain without generating a plan." do
    param(:domain_dsl, :string,
      required: true,
      description: "A RECTGTN HTN domain in Elixir DSL or JSON-LD format."
    )

    param(:format, :string,
      default: "dsl",
      description: "Parse format - 'dsl' for Elixir DSL or 'json' for JSON-LD"
    )

    handle_with(fn args, state ->
      with {:ok, domain_dsl} <- parse_domain_input(Map.fetch!(args, :domain_dsl), Map.get(args, :format, "dsl")),
           {:ok, compiled} <- Taskweft.DSL.compile(domain_dsl),
           {:ok, domain_normalized} <- Taskweft.validate(Jason.encode!(compiled)) do
        {:ok, %{content: Jason.encode!(domain_normalized)}}
      else
        {:error, reason} -> {:ok, %{content: Jason.encode!(%{error: reason})}}
      end
    end)
  end

  # ---------- HELPERS ----------

  defp parse_domain_input(raw, "json") when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, json} -> {:ok, Jason.encode!(json)}
      {:error, _} -> {:error, "Invalid JSON"}
    end
  end

  defp parse_domain_input(raw, "yaml") when is_binary(raw) do
    case YamlElixir.read_all_from_string(raw) do
      {:ok, yaml} -> {:ok, Jason.encode!(yaml)}
      {:error, _} -> {:error, "Invalid YAML"}
    end
  end

  defp parse_domain_input(raw, "dsl") when is_binary(raw) do
    {:ok, raw}
  end

  defp parse_domain_input(_raw, _format), do: {:error, "Invalid format. Use 'dsl', 'json', or 'yaml'"}
end