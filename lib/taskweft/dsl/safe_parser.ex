# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.DSL.SafeParser do
  @moduledoc """
  Safe AST parser for Elixir module attributes used in Taskweft DSL.

  Parses module attributes (@name, @variables, @actions, etc.) from an Elixir module
  AST and converts them to RECTGTN JSON-LD format.
  """

  @type parse_result :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Parse an Elixir module AST and extract domain attributes into RECTGTN JSON-LD.

  Returns {:ok, json_string} or {:error, reason} on failure.
  """
  @spec parse(Elixir.t()) :: parse_result()
  def parse(module_ast) do
    with {:ok, domain_map} <- extract_domain_attributes(module_ast) do
      json = Jason.encode!(finalize(domain_map))
      {:ok, json}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_domain_attributes({:__block__, _, attributes}) do
    domain = %{
      "@context" => %{
        "vsekai" => "https://v-sekai.org/",
        "domain" => "vsekai:planning/domain/"
      },
      "@type" => "domain:Definition",
      "name" => nil,
      "variables" => [],
      "actions" => %{},
      "methods" => %{},
      "todo_list" => []
    }

    domain =
      Enum.reduce(attributes, domain, fn attr, acc ->
        handle_attribute(attr, acc)
      end)

    {:ok, domain}
  end

  defp handle_attribute({:name, _, [value]}, domain) when is_binary(value) do
    Map.put(domain, "name", value)
  end

  defp handle_attribute({:variables, _, [value]}, domain) when is_map(value) do
    vars =
      value
      |> Map.to_list()
      |> Enum.map(fn {name, opts} ->
        %{
          "name" => to_string(name),
          "type" => to_string(opts[:type] || :ref),
          "init" =>
            opts[:init]
            |> Map.new(fn {k, v} -> {to_string(k), to_string(v)} end)
        }
      end)

    Map.put(domain, "variables", vars)
  end

  defp handle_attribute({:actions, _, [value]}, domain) when is_map(value) do
    acts =
      value
      |> Map.to_list()
      |> Enum.map(fn {name, act} ->
        {to_string(name), to_string_act(act)}
      end)
      |> Map.new()

    Map.put(domain, "actions", acts)
  end

  defp handle_attribute({:methods, _, [value]}, domain) when is_map(value) do
    meths =
      value
      |> Map.to_list()
      |> Enum.map(fn {name, meth} ->
        {to_string(name), to_string_method(meth)}
      end)
      |> Map.new()

    Map.put(domain, "methods", meths)
  end

  defp handle_attribute({:todo_list, _, [value]}, domain) when is_list(value) do
    Map.put(domain, "todo_list", to_string_todo_list(value))
  end

  defp handle_attribute(_attr, domain), do: domain

  defp to_string_act(act) when is_map(act) do
    params = (act[:params] || []) |> Enum.map(&to_string/1)
    body = (act[:body] || []) |> Enum.map(&to_string_body/1)

    action_def = %{"params" => params, "body" => body}

    action_def =
      if act[:duration] do
        Map.put(action_def, :duration, to_string(act[:duration]))
      else
        action_def
      end

    action_def
  end

  defp to_string_method(meth) when is_map(meth) do
    params = (meth[:params] || []) |> Enum.map(&to_string/1)
    alternatives = (meth[:alternatives] || []) |> Enum.map(&to_string_alternative/1)

    %{"params" => params, "alternatives" => alternatives}
  end

  defp to_string_alternative(alt) when is_map(alt) do
    %{
      "name" => to_string(alt[:name]),
      "subtasks" => alt[:subtasks] || [],
      "check" => (alt[:check] || []) |> Enum.map(&to_string_guard/1)
    }
  end

  defp to_string_body(%{pointer_set: path, value: value}) do
    %{"pointer/set" => to_string(path), "value" => to_string(value)}
  end

  defp to_string_guard({:condition, _, [type, args]}) do
    cond =
      case args do
        [expr] -> %{"type" => to_string(type), "a" => to_string_expr(expr)}
        [expr1, expr2] -> %{"type" => to_string(type), "a" => to_string_expr(expr1), "b" => to_string_expr(expr2)}
      end

    cond
  end

  defp to_string_todo_list(list) when is_list(list) do
    Enum.map(list, fn item ->
      case item do
        [call, task_task_args...] when is_binary(call) ->
          [to_string(call) | Enum.map(task_task_args, &to_string/1)]

        %{goal: goals} when is_list(goals) ->
          %{"goal" => Enum.map(goals, &to_string_goal/1)}

        %{multigoal: mg} when is_map(mg) ->
          %{"multigoal" => mg}

        other ->
          other
      end
    end)
  end

  defp to_string_goal(%{"pointer" => pointer, "eq" => value}) do
    %{"pointer" => to_string(pointer), "eq" => to_string(value)}
  end

  defp to_string_expr(atom) when is_atom(atom), do: to_string(atom)
  defp to_string_expr(str) when is_binary(str), do: str
  defp to_string_expr(num) when is_integer(num), do: to_string(num)
  defp to_string_expr(num) when is_float(num), do: to_string(num)
  defp to_string_expr(%{pointer_get: path}), do: %{"type" => "pointer/get", "pointer" => to_string(path)}
  defp to_string_expr(_other), do: {:error, "invalid expression"}

  defp finalize(domain) do
    domain
    |> Map.delete("capabilities")
    |> then(fn d ->
      if Map.has_key?(domain, "capabilities") do
        Map.put(d, "capabilities", domain["capabilities"])
      else
        d
      end
    end)
  end
end
