defmodule Taskweft.Domain.Persist do
  @moduledoc """
  Converts a parsed domain map (from YAML-LD or JSON-LD) into a
  beautiful, Sourceror-formatted Elixir DSL `.ex` file.

  This is the final stage of the LLM ingestion pipeline:

      LLM → YAML-LD → Taskweft Parser (validate) → Persist → .ex file

  The LLM inputs cheap, resilient YAML-LD. Taskweft converts it to
  clean, compiled Elixir code for the codebase.
  """

  @doc """
  Convert a validated domain map to Elixir DSL source code.

  Returns `{:ok, source_string}` or `{:error, reason}`.
  """
  def to_dsl_source(domain) when is_map(domain) do
    name = Module.safe_concat([domain_name(domain)])
    body_lines = build_body(domain)

    source = """
    defmodule #{inspect(name)} do
      use Taskweft.Domain.Builder

    #{body_lines |> Enum.join("\n")}
    end
    """

    # Use Sourceror to format the generated code
    try do
      ast = Sourceror.parse_string!(source)
      formatted = Sourceror.to_string(ast)
      {:ok, formatted}
    rescue
      e -> {:error, "Sourceror formatting failed: #{Exception.message(e)}"}
    end
  end

  @doc """
  Persist a domain to an Elixir DSL `.ex` file.

  Writes to `priv/plans/domains/<name>.ex`.

  Returns `{:ok, file_path}` or `{:error, reason}`.
  """
  def persist(domain) do
    name = domain_name(domain)
    filename = "#{name}.ex"
    path = Path.join(["priv", "plans", "domains", filename])

    with {:ok, source} <- to_dsl_source(domain),
         :ok <- File.mkdir_p!(Path.dirname(path)),
         :ok <- File.write(path, source) do
      {:ok, Path.expand(path)}
    end
  end

  defp domain_name(domain) do
    name = domain["name"] || "unnamed_domain"
    # Convert to a valid Elixir module name: snake_case → CamelCase
    name
    |> String.split(~r/[-_]/)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
    |> then(fn s ->
      if String.match?(s, ~r/^[A-Z]/) do
        s
      else
        "Domain#{s}"
      end
    end)
  end

  defp build_body(domain) do
    lines = []

    lines = maybe_add_name(lines, domain)
    lines = maybe_add_variables(lines, domain)
    lines = maybe_add_capabilities(lines, domain)
    lines = maybe_add_actions(lines, domain)
    lines = maybe_add_methods(lines, domain)
    lines = maybe_add_todo_list(lines, domain)

    lines
  end

  defp maybe_add_name(lines, domain) do
    if domain["name"] do
      lines ++ [~s(  name "#{domain["name"]}")]
    else
      lines
    end
  end

  defp maybe_add_variables(lines, domain) do
    vars = domain["variables"] || []

    vars
    |> Enum.reduce(lines, fn var, acc ->
      var_name = var["name"] || ""
      var_type = var["type"] || "ref"
      init = var["init"]

      init_str =
        if init && init != %{} do
          init_pairs =
            Enum.map(init, fn {k, v} ->
              v_str = format_init_value(v)
              "    #{inspect(k)} => #{v_str},\n"
            end)

          ", init: %{\n#{init_pairs}}"
        else
          ""
        end

      acc ++ ["  variable :#{var_name}, type: :#{var_type}#{init_str}"]
    end)
  end

  defp maybe_add_capabilities(lines, domain) do
    caps = domain["capabilities"]

    if caps do
      entities_str =
        (caps["entities"] || %{})
        |> Enum.map(fn {entity, caps_list} ->
          cap_strs = Enum.map(caps_list || [], &"    :#{&1}")
          "    #{inspect(entity)} => [\n#{Enum.join(cap_strs, ",\n")}\n    ]"
        end)
        |> Enum.join(",\n")

      edges = caps["graph"]["edges"] || []

      edges_str =
        edges
        |> Enum.map(fn edge ->
          sub = edge["subject"] || ""
          rel = edge["rel"] || "HAS_CAPABILITY"
          obj = edge["object"] || ""
          "  %{subject: #{inspect(sub)}, rel: #{inspect(rel)}, object: #{inspect(obj)}}"
        end)
        |> Enum.join(",\n")

      lines ++
        [
          "",
          "  capabilities %{",
          "    entities: %{",
          entities_str,
          "    },",
          "    graph: [",
          edges_str,
          "    ]",
          "  }"
        ]
    else
      lines
    end
  end

  defp maybe_add_actions(lines, domain) do
    acts = domain["actions"] || %{}

    acts
    |> Enum.sort()
    |> Enum.reduce(lines, fn {act_name, act}, acc ->
      params_str =
        (act["params"] || [])
        |> Enum.map(&":#{&1}")
        |> Enum.join(", ")

      body_str = build_body_steps(act["body"] || [])

      duration_str =
        if act["duration"], do: ",\n    duration: #{inspect(act["duration"])}", else: ""

      acc ++
        [
          "",
          "  action :#{act_name},",
          "    params: [#{params_str}],",
          "    body: [",
          body_str,
          "    ]#{duration_str}"
        ]
    end)
  end

  defp build_body_steps(steps) do
    steps
    |> Enum.map(fn
      %{"pointer/set" => pointer, "value" => value} ->
        "      Taskweft.Domain.Builder.pointer_set(#{inspect(pointer)}, #{format_value(value)})"

      %{"eval" => eval} ->
        type = eval["type"]

        case type do
          "rebac/check" ->
            sub = eval["subject"] || ""
            rel = eval["rel"] || "HAS_CAPABILITY"
            obj = eval["object"] || ""

            "      Taskweft.Domain.Builder.rebac_check(#{inspect(sub)}, #{inspect(rel)}, #{inspect(obj)})"

          _ ->
            a = eval["a"]
            b = eval["b"]

            if b do
              "      Taskweft.Domain.Builder.condition(:#{type}, #{format_expr(a)}, #{format_expr(b)})"
            else
              "      Taskweft.Domain.Builder.condition(:#{type}, #{format_expr(a)})"
            end
        end

      other ->
        "      #{inspect(other)}"
    end)
    |> Enum.join(",\n")
  end

  defp maybe_add_methods(lines, domain) do
    meths = domain["methods"] || %{}

    meths
    |> Enum.sort()
    |> Enum.reduce(lines, fn {meth_name, meth}, acc ->
      params_str =
        (meth["params"] || [])
        |> Enum.map(&":#{&1}")
        |> Enum.join(", ")

      alt_str = build_alternatives(meth["alternatives"] || [])

      acc ++
        [
          "",
          "  method :#{meth_name},",
          "    params: [#{params_str}],",
          "    alternatives: [",
          alt_str,
          "    ]"
        ]
    end)
  end

  defp build_alternatives(alternatives) do
    alternatives
    |> Enum.map(fn alt ->
      name = alt["name"] || ""
      checks = alt["check"] || []
      subtasks = alt["subtasks"] || []

      checks_str =
        if checks != [] do
          check_lines =
            Enum.map(checks, fn
              %{"eval" => eval} ->
                type = eval["type"]
                a = eval["a"]
                b = eval["b"]

                if b do
                  "          Taskweft.Domain.Builder.condition(:#{type}, #{format_expr(a)}, #{format_expr(b)})"
                else
                  "          Taskweft.Domain.Builder.condition(:#{type}, #{format_expr(a)})"
                end
            end)
            |> Enum.join(",\n")

          ",\n        check: [\n#{check_lines}\n        ]"
        else
          ""
        end

      subtask_lines =
        subtasks
        |> Enum.map(fn task ->
          parts = Enum.map(task, &format_subtask_element/1)
          "            [#{Enum.join(parts, ", ")}]"
        end)
        |> Enum.join(",\n")

      """
            Taskweft.Domain.Builder.alt(:#{name}#{checks_str},
              subtasks: [
      #{subtask_lines}
              ]
            )\
      """
    end)
    |> Enum.join(",\n")
  end

  defp maybe_add_todo_list(lines, domain) do
    todo = domain["todo_list"] || []

    if todo != [] do
      task_lines =
        todo
        |> Enum.map(fn task ->
          parts = Enum.map(task, &format_subtask_element/1)
          "    [#{Enum.join(parts, ", ")}]"
        end)
        |> Enum.join(",\n")

      lines ++
        [
          "",
          "  todo_list [",
          task_lines,
          "  ]"
        ]
    else
      lines
    end
  end

  # ── Value formatting helpers ────────────────────────────────────────

  defp format_value(value) when is_integer(value), do: to_string(value)
  defp format_value(value) when is_float(value), do: to_string(value)
  defp format_value(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp format_value(value) when is_binary(value), do: inspect(value)

  defp format_expr(%{"type" => "pointer/get", "pointer" => pointer}) do
    "Taskweft.Domain.Builder.pointer_get(#{inspect(pointer)})"
  end

  defp format_expr(%{"type" => "math/eq"} = expr), do: inspect(expr)
  defp format_expr(value) when is_binary(value), do: inspect(value)
  defp format_expr(value) when is_integer(value), do: to_string(value)
  defp format_expr(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp format_expr(value), do: inspect(value)

  defp format_init_value(value) when is_binary(value) do
    if value =~ ~r/^[a-z_]/ and value =~ ~r/^[a-zA-Z0-9_]+$/ and not value =~ ~r/^[0-9]/ do
      ~s["#{value}"]
    else
      inspect(value)
    end
  end

  defp format_init_value(value) when is_integer(value), do: to_string(value)
  defp format_init_value(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp format_init_value(value), do: inspect(value)

  defp format_subtask_element(value) when is_integer(value), do: to_string(value)

  defp format_subtask_element(value) when is_binary(value) do
    # If it's a variable reference like "{agent}", keep it as string
    # If it's an action/method name like "a_pickup", emit as atom :a_pickup
    if String.starts_with?(value, "{") and String.ends_with?(value, "}") do
      inspect(value)
    else
      ":#{value}"
    end
  end

  defp format_subtask_element(value), do: inspect(value)
end
