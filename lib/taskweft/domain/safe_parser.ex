defmodule Taskweft.Domain.SafeParser do
  @moduledoc """
  A safe, token-efficient parser that walks Elixir syntax trees without ever
  compiling or executing code strings at runtime.

  Uses `Code.string_to_quoted/2` to convert DSL source to an AST, then walks
  it with strict pattern matching that only allows known RECTGTN constructs.
  Any unrecognised form is rejected immediately — no sandbox escapes possible.

  ## Example

      SafeParser.parse('''
        name "blocks_world"
        variable :pos, type: :ref, init: %{a: "table"}
        action :pickup, params: [:x],
          body: [pointer_set("/pos/{x}", "hand")]
        todo_list [[:pickup, :a]]
      ''')
      # => {:ok, "{\\"@context\\": ..., \\"variables\\": ...}"}
  """

  @doc """
  Parse an Elixir DSL string into a RECTGTN domain JSON map.

  Returns `{:ok, json_string}` or `{:error, reason}`.
  """
  def parse(dsl_source) when is_binary(dsl_source) do
    case Code.string_to_quoted(dsl_source, columns: true, literal_encoder: fn
      {:sigil, _, _}, _meta -> {:ok, {:sigil, :__block__, []}}
      other, _meta -> {:ok, other}
    end) do
      {:ok, {:__block__, _, expressions}} ->
        try do
          domain = Enum.reduce(expressions, initial_domain(), &reduce_ast/2)
          {:ok, Jason.encode!(finalize(domain))}
        catch
          {:invalid, reason} -> {:error, "RECTGTN compliance error: #{reason}"}
        end

      {:ok, single} ->
        # Single expression (no block wrapping needed for one-liners)
        try do
          domain = reduce_ast(single, initial_domain())
          {:ok, Jason.encode!(finalize(domain))}
        catch
          {:invalid, reason} -> {:error, "RECTGTN compliance error: #{reason}"}
        end

      {:error, {_line, err, _token}} ->
        {:error, "Syntax error: #{err}"}
    end
  end

  defp initial_domain do
    %{
      "@context" => %{
        "vsekai" => "https://v-sekai.org/",
        "domain" => "vsekai:planning/domain/"
      },
      "@type" => "domain:Definition",
      "name" => "unnamed_domain",
      "variables" => [],
      "actions" => %{},
      "methods" => %{},
      "todo_list" => []
    }
  end

  # ── Name ──────────────────────────────────────────────────────────────

  defp reduce_ast({:name, _, [name_str]}, acc) when is_binary(name_str) do
    %{acc | "name" => name_str}
  end

  # ── Variables ──────────────────────────────────────────────────────────

  defp reduce_ast(
         {:variable, _, [name_atom, [type: type_atom, init: {:%{}, _, pairs}]]},
         acc
       ) do
    var = %{
      "name" => atom_str(name_atom),
      "type" => atom_str(type_atom),
      "init" => Map.new(pairs, fn {k, v} -> {safe_key(k), safe_literal(v)} end)
    }
    %{acc | "variables" => acc["variables"] ++ [var]}
  end

  defp reduce_ast({:variable, _, [name_atom, [type: type_atom]]}, acc) do
    var = %{"name" => atom_str(name_atom), "type" => atom_str(type_atom), "init" => %{}}
    %{acc | "variables" => acc["variables"] ++ [var]}
  end

  defp reduce_ast({:variable, _, [name_atom, [type: type_atom, init: init_val]]}, acc)
       when not is_list(init_val) do
    var = %{
      "name" => atom_str(name_atom),
      "type" => atom_str(type_atom),
      "init" => safe_literal(init_val)
    }
    %{acc | "variables" => acc["variables"] ++ [var]}
  end

  # ── Actions ────────────────────────────────────────────────────────────

  defp reduce_ast({:action, _, [name_atom, [params: params, body: {:__block__, _, steps}]]}, acc) do
    add_action(acc, name_atom, params, steps)
  end

  defp reduce_ast({:action, _, [name_atom, [params: params, body: steps] = opts]}, acc)
       when is_list(steps) do
    add_action(acc, name_atom, params, steps, opts[:duration])
  end

  defp reduce_ast({:action, _, [name_atom, opts]}, acc) when is_list(opts) do
    params = Keyword.get(opts, :params, [])
    body = Keyword.get(opts, :body, [])
    duration = Keyword.get(opts, :duration)
    add_action(acc, name_atom, params, body |> List.wrap(), duration)
  end

  defp add_action(acc, name_atom, params, steps, duration \\ nil) do
    action_def = %{
      "params" => Enum.map(List.wrap(params), &atom_str/1),
      "body" => Enum.flat_map(List.wrap(steps), &parse_body_steps/1)
    }

    action_def =
      if duration do
        Map.put(action_def, "duration", safe_string(duration))
      else
        action_def
      end

    %{acc | "actions" => Map.put(acc["actions"], atom_str(name_atom), action_def)}
  end

  # ── Methods ────────────────────────────────────────────────────────────

  defp reduce_ast({:method, _, [name_atom, opts]}, acc) when is_list(opts) do
    params = Keyword.get(opts, :params, [])
    alternatives = Keyword.get(opts, :alternatives, [])

    method_def = %{
      "params" => Enum.map(List.wrap(params), &atom_str/1),
      "alternatives" => parse_alternatives(alternatives)
    }

    %{acc | "methods" => Map.put(acc["methods"], atom_str(name_atom), method_def)}
  end

  # ── Capabilities ───────────────────────────────────────────────────────

  defp reduce_ast({:capabilities, _, [caps]}, acc) do
    %{acc | "capabilities" => parse_capabilities(caps)}
  end

  # ── Todo list ──────────────────────────────────────────────────────────

  defp reduce_ast({:todo_list, _, [list]}, acc) do
    %{acc | "todo_list" => parse_todo_list(list)}
  end

  # ── Fallback: reject anything unrecognised ───────────────────────────

  defp reduce_ast(other, _acc) do
    throw({:invalid, "unrecognised construct: #{inspect(other)}"})
  end

  # ── Body step parsers ─────────────────────────────────────────────────

  defp parse_body_steps({:__block__, _, steps}), do: Enum.flat_map(steps, &parse_body_step/1)
  defp parse_body_steps(other), do: [parse_body_step(other)]

  defp parse_body_step({:pointer_set, _, [ptr, val]}) do
    %{"pointer/set" => safe_string(ptr), "value" => safe_literal(val)}
  end

  defp parse_body_step({:condition, _, [type_atom, a, b]}) do
    %{"eval" => %{"type" => atom_str(type_atom), "a" => safe_expr(a), "b" => safe_expr(b)}}
  end

  defp parse_body_step({:condition, _, [type_atom, a]}) do
    %{"eval" => %{"type" => atom_str(type_atom), "a" => safe_expr(a)}}
  end

  defp parse_body_step({:rebac_check, _, [subj, rel, obj]}) do
    %{
      "eval" => %{
        "type" => "rebac/check",
        "subject" => safe_string(subj),
        "rel" => safe_string(rel),
        "object" => safe_string(obj)
      }
    }
  end

  defp parse_body_step({:pointer_get, _, [ptr]}) do
    %{"type" => "pointer/get", "pointer" => safe_string(ptr)}
  end

  defp parse_body_step(other) do
    throw({:invalid, "malformed step: #{inspect(other)}"})
  end

  # ── Alternative parsers ───────────────────────────────────────────────

  defp parse_alternatives([{:__block__, _, alts} | _]), do: parse_alternatives(alts)
  defp parse_alternatives(alts) when is_list(alts) do
    Enum.map(alts, &parse_single_alternative/1)
  end

  defp parse_single_alternative({:alt, _, [name_atom, opts]}) do
    subtasks = Keyword.get(opts, :subtasks, [])
    checks = Keyword.get(opts, :check, [])

    alt = %{
      "name" => atom_str(name_atom),
      "subtasks" => parse_subtasks(subtasks)
    }

    if checks != [] do
      Map.put(alt, "check", parse_checks(List.wrap(checks)))
    else
      alt
    end
  end

  defp parse_subtasks({:__block__, _, tasks}) do
    Enum.map(tasks, fn
      {:list, _, items} -> Enum.map(items, &safe_subtask_elem/1)
      other -> throw({:invalid, "malformed subtask: #{inspect(other)}"})
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
  defp safe_subtask_elem(other), do: throw({:invalid, "non-literal in subtask: #{inspect(other)}"})

  defp parse_checks(checks) do
    Enum.map(checks, fn
      {:condition, _, [type_atom, a, b]} ->
        %{"eval" => %{"type" => atom_str(type_atom), "a" => safe_expr(a), "b" => safe_expr(b)}}
      {:condition, _, [type_atom, a]} ->
        %{"eval" => %{"type" => atom_str(type_atom), "a" => safe_expr(a)}}
      other ->
        throw({:invalid, "malformed check: #{inspect(other)}"})
    end)
  end

  # ── Capability parser ─────────────────────────────────────────────────

  defp parse_capabilities({:%{}, _, pairs}) do
    entities = parse_entity_map(Keyword.get(pairs, :entities, {:%{}, [], []}))
    graph_edges = parse_graph_edges(Keyword.get(pairs, :graph, []))

    %{
      "entities" => entities,
      "graph" => %{"edges" => graph_edges, "definitions" => %{}}
    }
  end

  defp parse_entity_map({:%{}, _, pairs}) do
    Map.new(pairs, fn {entity_atom, caps_list} ->
      {atom_str(entity_atom), Enum.map(List.wrap(caps_list), &atom_str/1)}
    end)
  end

  defp parse_graph_edges(edges) do
    Enum.map(List.wrap(edges), fn
      {:%{}, _, pairs} ->
        Map.new(pairs, fn {k, v} -> {atom_str(k), safe_string(v)} end)

      other ->
        throw({:invalid, "malformed graph edge: #{inspect(other)}"})
    end)
  end

  # ── Todo list parser ──────────────────────────────────────────────────

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

  defp parse_todo_entry(other) do
    throw({:invalid, "malformed todo_list entry: #{inspect(other)}"})
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

  # ── Finaliser ─────────────────────────────────────────────────────────

  defp finalize(domain) do
    # Remove empty fields for a cleaner output
    domain
    |> Map.drop(["capabilities"])
    |> then(fn d ->
      if domain["capabilities"] do
        Map.put(d, "capabilities", domain["capabilities"])
      else
        d
      end
    end)
  end

  # ── Safe value extractors ──────────────────────────────────────────────

  # Only allow literal values: strings, numbers, booleans, atoms → strings
  defp safe_literal(val) when is_binary(val), do: val
  defp safe_literal(val) when is_integer(val), do: val
  defp safe_literal(val) when is_float(val), do: val
  defp safe_literal(val) when is_boolean(val), do: val
  defp safe_literal(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp safe_literal({:__aliases__, _, parts}), do: parts |> Enum.map(&Atom.to_string/1) |> Enum.join(".")
  defp safe_literal(other), do: throw({:invalid, "non-literal value: #{inspect(other)}"})

  defp safe_string(val) when is_binary(val), do: val
  defp safe_string(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp safe_string(other), do: throw({:invalid, "non-string value: #{inspect(other)}"})

  defp safe_key(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp safe_key(bin) when is_binary(bin), do: bin
  defp safe_key(other), do: throw({:invalid, "non-literal key: #{inspect(other)}"})

  defp safe_expr(val) when is_binary(val), do: val
  defp safe_expr(val) when is_integer(val), do: val
  defp safe_expr(val) when is_float(val), do: val
  defp safe_expr(val) when is_boolean(val), do: val
  defp safe_expr(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp safe_expr({:pointer_get, _, [ptr]}) do
    %{"type" => "pointer/get", "pointer" => safe_string(ptr)}
  end

  defp safe_expr({:%{}, _, _} = map_expr) do
    # Allow map literals (e.g. for enum values or expressions)
    {:%{}, _, pairs} = map_expr
    Map.new(pairs, fn {k, v} -> {safe_key(k), safe_literal(v)} end)
  end

  defp safe_expr(other) do
    throw({:invalid, "non-literal expression: #{inspect(other)}"})
  end

  defp atom_str(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp atom_str(other), do: throw({:invalid, "expected atom, got: #{inspect(other)}"})
end