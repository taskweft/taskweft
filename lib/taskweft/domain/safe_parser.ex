# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.Domain.SafeParser do
  @moduledoc """
  A safe parser for Elixir DSL strings to JSON-LD.
  """

  def parse(dsl_source) when is_binary(dsl_source) do
    with {:ok, ast} <- Code.string_to_quoted(dsl_source) do
      with {:ok, domain} <- walk_ast(ast) do
        {:ok, Jason.encode!(finalize(domain))}
      end
    end
  end

  defp walk_ast({:__block__, _, expressions}) do
    walk_expressions(expressions, initial_domain())
  end

  defp walk_ast(single) do
    walk_expressions([single], initial_domain())
  end

  defp walk_expressions([expr | rest], acc) do
    walk_expressions(rest, reduce_ast(expr, acc))
  end

  defp walk_expressions([], acc), do: {:ok, acc}

  defp initial_domain do
    %{
      "@context" => %{"vsekai" => "https://v-sekai.org/", "domain" => "vsekai:planning/domain/"},
      "@type" => "domain:Definition",
      "name" => "unnamed_domain",
      "variables" => [],
      "actions" => %{},
      "methods" => %{},
      "todo_list" => []
    }
  end

  # Keyword list DSL parsing
  defp reduce_ast({:name, _, [name_str]}, acc) when is_binary(name_str) do
    %{acc | "name" => name_str}
  end

  defp reduce_ast({:variable, _, [name_atom, [type: type_atom, init: {:%{}, _, pairs}]]}, acc) do
    var = %{
      "name" => atom_str(name_atom),
      "type" => atom_str(type_atom),
      "init" => Map.new(pairs, fn {k, v} -> {safe_key(k), safe_literal(v)} end)
    }
    %{acc | "variables" => acc["variables"] ++ [var]}
  end

  defp reduce_ast({:action, _, [name_atom, [params: params, body: {:__block__, _, steps}]]}, acc) do
    action_def = %{
      "params" => Enum.map(List.wrap(params), &atom_str/1),
      "body" => Enum.flat_map(List.wrap(steps), &parse_body_steps/1)
    }
    %{acc | "actions" => Map.put(acc["actions"], atom_str(name_atom), action_def)}
  end

  defp reduce_ast({:method, _, [name_atom, opts]}, acc) when is_list(opts) do
    params = Keyword.get(opts, :params, [])
    alternatives = Keyword.get(opts, :alternatives, [])

    method_def = %{
      "params" => Enum.map(List.wrap(params), &atom_str/1),
      "alternatives" => parse_alternatives(alternatives)
    }

    %{acc | "methods" => Map.put(acc["methods"], atom_str(name_atom), method_def)}
  end

  defp reduce_ast({:todo_list, _, [list]}, acc) do
    %{acc | "todo_list" => parse_todo_list(list)}
  end

  # PointerSet
  defp parse_body_steps({:pointer_set, _, [ptr, val]}) do
    %{\"pointer/set\" => safe_string(ptr), \"value\" => safe_literal(val)}
  end

  # Eval (condition)
  defp parse_body_steps({:condition, _, [type_atom, a, b]}) do
    %{\"eval\" => %{\"type\" => atom_str(type_atom), \"a\" => safe_expr(a), \"b\" => safe_expr(b)}}
  end

  defp parse_body_steps({:condition, _, [type_atom, a]}) do
    %{\"eval\" => %{\"type\" => atom_str(type_atom), \"a\" => safe_expr(a)}}
  end

  # ReBAC check
  defp parse_body_steps({:rebac_check, _, [subj, rel, obj]}) do
    %{
      \"eval\" => %{
        \"type\" => \"rebac/check\",
        \"subject\" => safe_string(subj),
        \"rel\" => safe_string(rel),
        \"object\" => safe_string(obj)
      }
    }
  end

  # PointerGet (inline eval)
  defp parse_body_steps({:pointer_get, _, [ptr]}) do
    %{\"type\" => \"pointer/get\", \"pointer\" => safe_string(ptr)}
  end

  defp parse_alternatives([{:__block__, _, alts} | _]), do: parse_alternatives(alts)

  defp parse_alternatives(alts) when is_list(alts) do
    Enum.map(alts, &parse_single_alternative/1)
  end

  defp parse_single_alternative({:alt, _, [name_atom, opts]}) do
    subtasks = Keyword.get(opts, :subtasks, [])
    checks = Keyword.get(opts, :check, [])

    alt = %{
      \"name\" => atom_str(name_atom),
      \"subtasks\" => parse_subtasks(subtasks)
    }

    if checks != [] do
      Map.put(alt, \"check\", parse_checks(List.wrap(checks)))
    else
      alt
    end
  end

  defp parse_subtasks({:__block__, _, tasks}) do
    Enum.map(tasks, fn
      {:list, _, items} -> Enum.map(items, &safe_subtask_elem/1)
      _ -> []
    end)
  end

  defp parse_subtasks(list) when is_list(list) do
    Enum.map(list, fn
      {:list, _, items} -> Enum.map(items, &safe_subtask_elem/1)
      other -> safe_subtask_elem(other)
    end)
  end

  defp safe_subtask_elem(atom) when is_atom(atom), do: atom_str(atom)
  defp safe_subtask_elem(bin) when is_binary(bin), do: bin
  defp safe_subtask_elem(int) when is_integer(int), do: int

  defp parse_checks(checks) do
    Enum.map(checks, fn
      {:condition, _, [type_atom, a, b]} ->
        %{"eval" => %{"type" => atom_str(type_atom), "a" => safe_expr(a), "b" => safe_expr(b)}}

      {:condition, _, [type_atom, a]} ->
        %{"eval" => %{"type" => atom_str(type_atom), "a" => safe_expr(a)}}

      _ ->
        []
    end)
  end

  defp parse_todo_list({:__block__, _, tasks}) do
    Enum.map(tasks, &parse_todo_entry/1)
  end

  defp parse_todo_list(list) when is_list(list) do
    Enum.map(list, &parse_todo_entry/1)
  end

  defp parse_todo_entry({:list, _, items}) do
    Enum.map(items, &safe_subtask_elem/1)
  end

  defp parse_todo_entry({:%{}, _, [{:goal, _, [goals]}]}) do
    %{"goal" => parse_goal_entries(goals)}
  end

  defp parse_todo_entry({:%{}, _, [{:multigoal, _, [mg_pair]}]}) do
    parse_multigoal(mg_pair)
  end

  defp parse_goal_entries({:__block__, _, entries}) do
    Enum.map(entries, fn {:%{}, _, pairs} ->
      Map.new(pairs, fn {k, v} -> {atom_str(k), safe_literal(v)} end)
    end)
  end

  defp parse_goal_entries(entries) when is_list(entries) do
    Enum.map(entries, fn {:%{}, _, pairs} ->
      Map.new(pairs, fn {k, v} -> {atom_str(k), safe_literal(v)} end)
    end)
  end

  defp parse_multigoal({:%{}, _, mg_pairs}) do
    mg = Map.new(mg_pairs, fn {var_atom, {:%{}, _, bindings}} ->
      {atom_str(var_atom), Map.new(bindings, fn {k, v} -> {atom_str(k), safe_literal(v)} end)}
    end)
    %{"multigoal" => mg}
  end

  defp finalize(domain) do
    # Keep capabilities if present, drop others for cleaner output
    if domain["capabilities"] do
      Map.drop(domain, ["capabilities"])
      |> Map.put("capabilities", domain["capabilities"])
    else
      Map.drop(domain, ["capabilities"])
    end
  end

  defp safe_literal(val) when is_binary(val), do: val
  defp safe_literal(val) when is_integer(val), do: val
  defp safe_literal(val) when is_float(val), do: val
  defp safe_literal(val) when is_boolean(val), do: val
  defp safe_literal(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp safe_literal({:%{}, _, _} = map_expr) do
    {:%{}, _, pairs} = map_expr
    Map.new(pairs, fn {k, v} -> {safe_key(k), safe_literal(v)} end)
  end

  defp safe_string(val) when is_binary(val), do: val
  defp safe_string(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp safe_key(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp safe_key(bin) when is_binary(bin), do: bin

  defp safe_expr(val) when is_binary(val), do: val
  defp safe_expr(val) when is_integer(val), do: val
  defp safe_expr(val) when is_float(val), do: val
  defp safe_expr(val) when is_boolean(val), do: val
  defp safe_expr(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp safe_expr({:pointer_get, _, [ptr]}) do
    %{"type" => "pointer/get", "pointer" => safe_string(ptr)}
  end

  defp atom_str(atom) when is_atom(atom), do: Atom.to_string(atom)
end