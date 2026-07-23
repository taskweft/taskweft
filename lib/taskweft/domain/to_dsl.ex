defmodule Taskweft.Domain.ToDSL do
  @moduledoc """
  Converts a domain map or plan list back to Elixir DSL source code.

  This is the inverse of `Taskweft.Domain.SafeParser` — takes the internal
  RECTGTN representation and produces valid Elixir DSL that SafeParser can
  parse back.
  """

  @doc """
  Convert a domain map to Elixir DSL source code.
  """
  def domain_to_dsl(domain) when is_map(domain) do
    lines = []

    lines = maybe_add_name(lines, domain)
    lines = maybe_add_context(lines, domain)
    lines = add_variables(lines, domain)
    lines = add_actions(lines, domain)
    lines = add_methods(lines, domain)
    lines = add_capabilities(lines, domain)
    lines = add_todo_list(lines, domain)

    Enum.join(lines, "\n")
  end

  @doc """
  Convert a plan list (list of step tuples) to Elixir DSL source code.
  """
  def plan_to_dsl(plan) when is_list(plan) do
    lines =
      Enum.map(plan, fn step ->
        "  " <> format_plan_step(step)
      end)

    "[\n" <> Enum.join(lines, "\n") <> "\n]"
  end

  defp maybe_add_name(lines, domain) do
    if name = domain["name"] do
      lines ++ [~s(name "#{name}")]
    else
      lines
    end
  end

  defp maybe_add_context(lines, domain) do
    if domain["@context"] do
      lines ++ ["# @context: #{inspect(domain["@context"])}"]
    else
      lines
    end
  end

  defp add_variables(lines, domain) do
    vars = domain["variables"] || []
    lines ++ Enum.map(vars, &format_variable/1)
  end

  defp format_variable(var) do
    name = var["name"]
    type = var["type"]
    init = var["init"]

    if init && init != %{} do
      pairs = Enum.map(init, fn {k, v} -> "#{format_key(k)}: #{format_value(v)}" end)
      "variable :#{name}, type: :#{type}, init: %{#{Enum.join(pairs, ", ")}}"
    else
      "variable :#{name}, type: :#{type}"
    end
  end

  defp add_actions(lines, domain) do
    actions = domain["actions"] || %{}
    lines ++ Enum.flat_map(actions, fn {name, action} -> format_action(name, action) end)
  end

  defp format_action(name, action) do
    params = action["params"] || []
    body = action["body"] || []
    duration = action["duration"]

    param_str = Enum.map(params, &":#{&1}") |> Enum.join(", ")

    body_lines =
      if body == [] do
        []
      else
        ["    body: ["] ++
          Enum.map(body, fn step -> "      " <> format_body_step(step) <> "," end) ++
          ["    ]"]
      end

    duration_lines =
      if duration do
        [~s[    duration: "#{duration}"]]
      else
        []
      end

    opts = ["params: [#{param_str}]"] ++ body_lines ++ duration_lines

    ["  action :#{name},"] ++ Enum.map(opts, &"    #{&1}") ++ [""]
  end

  defp format_body_step(%{"pointer/set" => ptr, "value" => val}) do
    ~s[pointer_set("#{ptr}", #{format_value(val)})]
  end

  defp format_body_step(%{"eval" => eval}) when is_map(eval) do
    t = eval["type"]

    case t do
      "rebac/check" ->
        ~s[rebac_check("#{eval["subject"]}", "#{eval["rel"]}", "#{eval["object"]}")]

      _ ->
        a = format_expr(eval["a"])
        b = if eval["b"], do: format_expr(eval["b"])

        if b do
          "condition(:#{t}, #{a}, #{b})"
        else
          "condition(:#{t}, #{a})"
        end
    end
  end

  defp format_body_step(%{"type" => "pointer/get", "pointer" => ptr}) do
    ~s[pointer_get("#{ptr}")]
  end

  defp add_methods(lines, domain) do
    methods = domain["methods"] || %{}
    lines ++ Enum.flat_map(methods, fn {name, method} -> format_method(name, method) end)
  end

  defp format_method(name, method) do
    params = method["params"] || []
    alternatives = method["alternatives"] || []

    param_str = Enum.map(params, &":#{&1}") |> Enum.join(", ")

    alt_lines =
      Enum.flat_map(alternatives, fn alt ->
        name = alt["name"]
        subtasks = alt["subtasks"] || []
        checks = alt["check"] || []

        subtask_strs = Enum.map(subtasks, &format_subtask/1)
        subtask_body = "subtasks: [#{Enum.join(subtask_strs, ", ")}]"

        check_lines =
          if checks != [] do
            ["    check: ["] ++
              Enum.map(checks, fn check -> "      " <> format_body_step(check) <> "," end) ++
              ["    ]"]
          else
            []
          end

        ["    alt(:#{name}, #{subtask_body})"] ++ check_lines
      end)

    ["  method :#{name}, params: [#{param_str}], alternatives: ["] ++
      Enum.map(alt_lines, &"    #{&1}") ++
      ["  ]"] ++
      [""]
  end

  defp format_subtask(task) when is_list(task) do
    "[" <> (Enum.map(task, &format_subtask_elem/1) |> Enum.join(", ")) <> "]"
  end

  defp format_subtask_elem(s) when is_binary(s), do: ~s["#{s}"]
  defp format_subtask_elem(s) when is_integer(s), do: to_string(s)
  defp format_subtask_elem(s) when is_atom(s), do: ":#{s}"

  defp add_capabilities(lines, domain) do
    caps = domain["capabilities"]

    if caps do
      entities = caps["entities"] || %{}
      graph = caps["graph"] || %{"edges" => []}

      entity_strs =
        Enum.map(entities, fn {type, caps_list} ->
          cap_strs = Enum.map(caps_list, &":#{&1}") |> Enum.join(", ")
          "  #{type}: [#{cap_strs}]"
        end)

      edge_strs =
        Enum.map(graph["edges"] || [], fn edge ->
          pairs = Enum.map(edge, fn {k, v} -> "#{k}: #{inspect(v)}" end) |> Enum.join(", ")
          "  %{#{pairs}}"
        end)

      lines ++
        [
          "capabilities %{",
          "  entities: %{",
          Enum.join(entity_strs, ",\n"),
          "  },",
          "  graph: %{",
          "    edges: [",
          Enum.join(edge_strs, ",\n"),
          "    ]",
          "  }",
          "}"
        ]
    else
      lines
    end
  end

  defp add_todo_list(lines, domain) do
    todo = domain["todo_list"] || []

    if todo == [] do
      lines
    else
      task_strs = Enum.map(todo, &format_todo_entry/1)
      lines ++ ["todo_list [#{Enum.join(task_strs, ", ")}]"]
    end
  end

  defp format_todo_entry(task) when is_list(task) do
    "[" <> (Enum.map(task, &format_subtask_elem/1) |> Enum.join(", ")) <> "]"
  end

  defp format_todo_entry(%{"goal" => goals}) do
    goal_strs =
      Enum.map(goals, fn g ->
        "  %{pointer: #{inspect(g["pointer"])}, eq: #{inspect(g["eq"])}}"
      end)

    "  %{goal: [\n" <> Enum.join(goal_strs, ",\n") <> "\n  ]}"
  end

  defp format_todo_entry(%{"multigoal" => mg}) do
    var_strs =
      Enum.map(mg, fn {var, bindings} ->
        bind_strs = Enum.map(bindings, fn {k, v} -> "#{k}: #{inspect(v)}" end) |> Enum.join(", ")
        "  #{var}: %{#{bind_strs}}"
      end)

    "  %{multigoal: %{\n" <> Enum.join(var_strs, ",\n") <> "\n  }}"
  end

  defp format_plan_step(step) when is_list(step) do
    "[" <> (Enum.map(step, &format_subtask_elem/1) |> Enum.join(", ")) <> "]"
  end

  defp format_plan_step(step) when is_map(step) do
    inspect(step)
  end

  defp format_key(key) when is_binary(key), do: key
  defp format_key(key) when is_atom(key), do: Atom.to_string(key)

  defp format_value(val) when is_binary(val), do: ~s["#{val}"]
  defp format_value(val) when is_integer(val), do: to_string(val)
  defp format_value(val) when is_float(val), do: to_string(val)
  defp format_value(true), do: "true"
  defp format_value(false), do: "false"
  defp format_value(val) when is_atom(val), do: ":#{val}"

  defp format_expr(val) when is_binary(val), do: ~s["#{val}"]
  defp format_expr(val) when is_integer(val), do: to_string(val)
  defp format_expr(%{"type" => "pointer/get", "pointer" => ptr}), do: ~s[pointer_get("#{ptr}")]
  defp format_expr(val) when is_map(val), do: inspect(val)
  defp format_expr(val), do: inspect(val)
end
