defmodule Taskweft.Planner do
  @moduledoc """
  Pure Elixir HTN planner.  Implements the same domain JSON interface as the
  C++ NIF (tw_planner.hpp).

  Domain format:

      %{
        "@type"     => "domain:Definition",
        "name"      => "...",
        "variables" => [%{"name" => "var", "init" => %{...}}],
        "actions"   => %{"action_name" => %{"params" => [], "body" => [...]}},
        "methods"   => %{"method_name" => %{"params" => [], "alternatives" => [...]}},
        "tasks"     => [["task_name", ...args]]
      }

  Alternatively, a `"state"` key may replace `"variables"` for the temporal
  check-only domain format used in tests.

  Body steps:
    - `%{"check" => "/ptr", "eq"|"neq"|"lt"|"le"|"gt"|"ge" => value}`
    - `%{"set"   => "/ptr", "value" => new_value}`
    - `%{"eval"  => khr_node}` — KHR interactivity nodes (not yet implemented;
      fails the action, consistent with the C++ NIF's current `:red` status)
  """

  @doc "Return `{:ok, plan_as_list}` or `{:error, reason}` from a parsed domain map."
  def run(domain) do
    state = build_state(domain)
    tasks = domain["tasks"] || []
    case plan_tasks(state, tasks, domain) do
      {:ok, plan, _final_state} -> {:ok, plan}
      {:error, _} = err -> err
    end
  end

  @doc "Encode `plan_result` to a JSON string (for NIF parity)."
  def encode_plan(plan), do: Jason.encode!(plan)

  # ── State construction ────────────────────────────────────────────────────

  defp build_state(%{"variables" => vars}) when is_list(vars) do
    Enum.reduce(vars, %{}, fn
      %{"name" => name, "init" => init}, acc -> Map.put(acc, name, init)
      _, acc -> acc
    end)
  end

  defp build_state(%{"state" => state}) when is_map(state), do: state
  defp build_state(_), do: %{}

  # ── Core planner ──────────────────────────────────────────────────────────

  defp plan_tasks(state, [], _domain), do: {:ok, [], state}

  defp plan_tasks(state, [[task_name | args] | rest_tasks], domain) do
    actions = domain["actions"] || %{}
    methods = domain["methods"] || %{}

    cond do
      Map.has_key?(actions, task_name) ->
        action = actions[task_name]
        case apply_action(state, action) do
          {:ok, new_state} ->
            case plan_tasks(new_state, rest_tasks, domain) do
              {:ok, rest_plan, final_state} ->
                {:ok, [[task_name | args] | rest_plan], final_state}

              err ->
                err
            end

          {:error, _} = err ->
            err
        end

      Map.has_key?(methods, task_name) ->
        method = methods[task_name]
        alternatives = method["alternatives"] || []
        try_alternatives(state, alternatives, args, rest_tasks, domain)

      true ->
        {:error, "unknown_task: #{task_name}"}
    end
  end

  defp try_alternatives(_state, [], _args, _rest_tasks, _domain), do: {:error, "no_plan"}

  defp try_alternatives(state, [alt | alts], args, rest_tasks, domain) do
    subtasks = resolve_subtasks(alt["subtasks"] || [], alt["params"] || [], args)

    case plan_tasks(state, subtasks ++ rest_tasks, domain) do
      {:ok, _, _} = ok -> ok
      {:error, _} -> try_alternatives(state, alts, args, rest_tasks, domain)
    end
  end

  defp resolve_subtasks(subtasks, _params, _args), do: subtasks

  # ── Action application ────────────────────────────────────────────────────

  defp apply_action(state, action) do
    body = action["body"] || []
    apply_body(state, body)
  end

  defp apply_body(state, []), do: {:ok, state}

  defp apply_body(state, [step | rest]) do
    case apply_step(state, step) do
      {:ok, new_state} -> apply_body(new_state, rest)
      {:error, _} = err -> err
    end
  end

  defp apply_step(state, %{"check" => ptr} = step) do
    current = get_by_pointer(state, ptr)

    result =
      cond do
        Map.has_key?(step, "eq") -> current == step["eq"]
        Map.has_key?(step, "neq") -> current != step["neq"]
        Map.has_key?(step, "lt") -> numeric_compare(current, step["lt"], :lt)
        Map.has_key?(step, "le") -> numeric_compare(current, step["le"], :le)
        Map.has_key?(step, "gt") -> numeric_compare(current, step["gt"], :gt)
        Map.has_key?(step, "ge") -> numeric_compare(current, step["ge"], :ge)
        true -> true
      end

    if result, do: {:ok, state}, else: {:error, :precondition_failed}
  end

  defp apply_step(state, %{"set" => ptr, "value" => value}) do
    {:ok, set_by_pointer(state, ptr, value)}
  end

  defp apply_step(_state, %{"eval" => _}) do
    # KHR interactivity eval nodes are not yet implemented.
    # Returns an error so the action fails — consistent with the C++ NIF's
    # current state (these tests are tagged :red).
    {:error, :eval_not_supported}
  end

  defp apply_step(state, _unknown), do: {:ok, state}

  # ── JSON Pointer (RFC 6901) ───────────────────────────────────────────────

  def get_by_pointer(_state, ""), do: nil

  def get_by_pointer(state, "/" <> path) do
    keys = path |> String.split("/") |> Enum.map(&unescape_pointer/1)
    Enum.reduce(keys, state, fn
      key, m when is_map(m) -> Map.get(m, key)
      _key, _ -> nil
    end)
  end

  def get_by_pointer(_state, _), do: nil

  def set_by_pointer(state, "/" <> path, value) do
    keys = path |> String.split("/") |> Enum.map(&unescape_pointer/1)
    put_nested(state, keys, value)
  end

  def set_by_pointer(state, _, _), do: state

  defp put_nested(_any, [], value), do: value

  defp put_nested(map, [key | rest], value) when is_map(map) do
    Map.put(map, key, put_nested(Map.get(map, key, %{}), rest, value))
  end

  defp put_nested(_non_map, [key | rest], value) do
    %{key => put_nested(%{}, rest, value)}
  end

  defp unescape_pointer(s),
    do: s |> String.replace("~1", "/") |> String.replace("~0", "~")

  # ── Numeric comparisons ───────────────────────────────────────────────────

  defp numeric_compare(a, b, :lt) when is_number(a) and is_number(b), do: a < b
  defp numeric_compare(a, b, :le) when is_number(a) and is_number(b), do: a <= b
  defp numeric_compare(a, b, :gt) when is_number(a) and is_number(b), do: a > b
  defp numeric_compare(a, b, :ge) when is_number(a) and is_number(b), do: a >= b
  defp numeric_compare(_, _, _), do: false
end
