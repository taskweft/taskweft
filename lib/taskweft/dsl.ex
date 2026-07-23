# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.DSL do
  @moduledoc """
  Simple Elixir DSL struct-based domain builder.
  This compiles Elixir structs to JSON-LD for the planner.
  """

  defstruct [:name, :variables, :actions, :methods, :todo_list,
             capabilities: nil, description: nil]

  @doc """
  Compile a DSL domain to JSON-LD string.
  """
  @spec compile(%DSL.Domain{}) :: {:ok, String.t()} | {:error, String.t()}
  def compile(domain) do
    json = build_domain_json(domain)
    case Jason.encode(json) do
      {:ok, json_ld} -> {:ok, json_ld}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Compile a DSL domain to JSON-LD string, raising on error.
  """
  @spec compile!(%DSL.Domain{}) :: String.t()
  def compile!(domain) do
    case compile(domain) do
      {:ok, json} -> json
      {:error, reason} -> raise ArgumentError, "DSL compilation failed: #{reason}"
    end
  end

  defp build_domain_json(%DSL.Domain{} = domain) do
    context = %{
      "vsekai" => "https://v-sekai.org/",
      "domain" => "vsekai:planning/domain/"
    }

    base = %{
      "@context" => context,
      "@type" => "domain:Definition",
      "name" => domain.name,
      "variables" => Enum.map(domain.variables, &build_variable/1),
      "actions" => Map.new(domain.actions, fn {name, action} ->
        {name, build_action(name, action)}
      end),
      "methods" => Map.new(domain.methods, fn {name, method} ->
        {name, build_method(method)}
      end),
      "todo_list" => domain.todo_list
    }

    base
    |> maybe_add_capabilities(domain.capabilities)
    |> maybe_add_description(domain.description)
  end

  defp build_variable(%DSL.Variable{name: name, type: type, init: init}) do
    %{name: name, type: type, init: init}
  end

  defp build_action(name, %DSL.Action{params: params, body: body, duration: duration}) do
    %{
      "params" => params,
      "body" => Enum.map(body, &build_body_node/1)
    }
    |> maybe_add_duration(duration)
  end

  defp build_method(%DSL.Method{name: name, params: params, alternatives: alternatives}) do
    %{
      "params" => params,
      "alternatives" => Enum.map(alternatives, &build_alternative/1)
    }
  end

  defp build_alternative(%DSL.Alternative{name: name, check: check, subtasks: subtasks}) do
    %{
      "name" => name,
      "check" => Enum.map(check, &build_body_node/1),
      "subtasks" => subtasks
    }
  end

  defp build_body_node(%DSL.Eval{type: type, a: a, b: b}) do
    %{
      "eval" => %{
        "type" => type,
        "a" => build_value(a),
        "b" => build_value(b)
      }
    }
  end

  defp build_body_node(%DSL.PointerSet{pointer: pointer, value: value}) do
    %{
      "pointer/set" => "/#{pointer}"
    }
  end

  defp build_value(%DSL.VariableRef{var: var}), do: "{#{var}}"
  defp build_value(%DSL.Eval{type: :ref, a: a, b: b}) do
    %{"eval" => %{
      "type" => "rebac/check",
      "subject" => build_value(a),
      "rel" => build_value(b)
    }}
  end
  defp build_value(other), do: other

  defp maybe_add_capabilities(map, nil), do: map
  defp maybe_add_capabilities(map, capabilities), do: Map.put(map, "capabilities", capabilities)

  defp maybe_add_description(map, nil), do: map
  defp maybe_add_description(map, description), do: Map.put(map, "description", description)

  defp maybe_add_duration(map, nil), do: map
  defp maybe_add_duration(map, duration), do: Map.put(map, "duration", duration)
end