defmodule Taskweft.ReBAC do
  @moduledoc """
  Pure Elixir Relationship-Based Access Control engine.

  Graph wire format:

      {"edges": [{"subject": "...", "object": "...", "rel": "..."}], "definitions": {}}

  Valid relation names: HAS_CAPABILITY CONTROLS OWNS IS_MEMBER_OF DELEGATED_TO
  SUPERVISOR_OF PARTNER_OF CAN_ENTER CAN_INSTANCE.

  Relation expressions (RelExpr) passed to `check/5`:

      {"type":"base","rel":"OWNS"}
      {"type":"union","a":{...},"b":{...}}
      {"type":"intersection","a":{...},"b":{...}}
      {"type":"difference","a":{...},"b":{...}}
      {"type":"tuple_to_userset","pivot_rel":"IS_MEMBER_OF","inner":{...}}

  IS_MEMBER_OF transitivity: if A IS_MEMBER_OF B and B holds `rel` to `obj`,
  then A also holds `rel` to `obj`.
  """

  @empty_graph ~s({"edges":[],"definitions":{}})

  @doc "Return an empty graph JSON string."
  def new_graph, do: @empty_graph

  @doc "Add a directed edge (subj)-[rel]->(obj) and return the updated graph JSON."
  def add_edge(graph_json, subj, obj, rel) do
    graph = Jason.decode!(graph_json)
    edge = %{"subject" => subj, "object" => obj, "rel" => rel}
    Jason.encode!(Map.update!(graph, "edges", &[edge | &1]))
  end

  @doc "Evaluate a RelExpr against the graph. Returns `true` or `false`."
  def check(graph_json, subj, expr_json, obj, fuel \\ 8) do
    graph = Jason.decode!(graph_json)
    expr = Jason.decode!(expr_json)
    eval_expr(graph["edges"] || [], subj, expr, obj, fuel)
  end

  @doc "Convenience wrapper for a base-relation check."
  def check_rel(graph_json, subj, rel, obj, fuel \\ 8) do
    check(graph_json, subj, ~s({"type":"base","rel":"#{rel}"}), obj, fuel)
  end

  @doc "Return all subjects that hold `rel` to `obj` (with IS_MEMBER_OF transitivity)."
  def expand(graph_json, rel, obj, fuel \\ 8) do
    edges = Jason.decode!(graph_json)["edges"] || []
    expand_set(edges, rel, obj, fuel, MapSet.new()) |> MapSet.to_list()
  end

  @doc """
  Parse natural-language fact sentences into relation edges.

  `facts_json` is a JSON array of `{"content": "...", "trust_score": float}` objects.
  Sentences below `trust_threshold` are ignored.
  """
  def parse_relation_edges(facts_json, trust_threshold \\ 0.5) do
    facts = Jason.decode!(facts_json)

    edges =
      for fact <- facts,
          is_map(fact),
          trust = Map.get(fact, "trust_score", 1.0),
          is_number(trust) and trust >= trust_threshold,
          content = Map.get(fact, "content", ""),
          is_binary(content),
          edge = extract_edge(content),
          edge != nil,
          do: edge

    Jason.encode!(%{"edges" => edges, "definitions" => %{}})
  end

  # ── RelExpr evaluator ─────────────────────────────────────────────────────

  defp eval_expr(_edges, _subj, _expr, _obj, 0), do: false

  defp eval_expr(edges, subj, %{"type" => "base", "rel" => rel}, obj, fuel) do
    direct = Enum.any?(edges, fn e ->
      e["subject"] == subj and e["object"] == obj and e["rel"] == rel
    end)

    if direct do
      true
    else
      # IS_MEMBER_OF transitivity: subj IS_MEMBER_OF group → group holds rel
      groups =
        for %{"subject" => s, "object" => g, "rel" => "IS_MEMBER_OF"} <- edges,
            s == subj,
            do: g

      Enum.any?(groups, fn g ->
        eval_expr(edges, g, %{"type" => "base", "rel" => rel}, obj, fuel - 1)
      end)
    end
  end

  defp eval_expr(edges, subj, %{"type" => "union", "a" => a, "b" => b}, obj, fuel),
    do: eval_expr(edges, subj, a, obj, fuel) or eval_expr(edges, subj, b, obj, fuel)

  defp eval_expr(edges, subj, %{"type" => "intersection", "a" => a, "b" => b}, obj, fuel),
    do: eval_expr(edges, subj, a, obj, fuel) and eval_expr(edges, subj, b, obj, fuel)

  defp eval_expr(edges, subj, %{"type" => "difference", "a" => a, "b" => b}, obj, fuel),
    do: eval_expr(edges, subj, a, obj, fuel) and not eval_expr(edges, subj, b, obj, fuel)

  defp eval_expr(edges, subj, %{"type" => "tuple_to_userset", "pivot_rel" => pr, "inner" => inner}, obj, fuel) do
    pivots =
      for %{"subject" => s, "object" => g, "rel" => r} <- edges,
          s == subj and r == pr,
          do: g

    Enum.any?(pivots, fn g -> eval_expr(edges, g, inner, obj, fuel - 1) end)
  end

  defp eval_expr(_edges, _subj, _expr, _obj, _fuel), do: false

  # ── expand (BFS with IS_MEMBER_OF transitivity) ──────────────────────────

  defp expand_set(_edges, _rel, _obj, 0, acc), do: acc

  defp expand_set(edges, rel, obj, _fuel, visited) do
    if MapSet.member?(visited, obj) do
      visited
    else
      visited = MapSet.put(visited, obj)

      direct =
        for %{"subject" => s, "object" => o, "rel" => r} <- edges,
            o == obj and r == rel,
            do: s

      result = MapSet.union(visited, MapSet.new(direct))

      Enum.reduce(direct, result, fn subj, acc ->
        members =
          for %{"subject" => a, "object" => b, "rel" => "IS_MEMBER_OF"} <- edges,
              b == subj,
              do: a

        MapSet.union(acc, MapSet.new(members))
      end)
    end
  end

  # ── Natural-language sentence parser ─────────────────────────────────────

  @verb_patterns [
    {"delegates to", "DELEGATED_TO"},
    {"is a member of", "IS_MEMBER_OF"},
    {"is member of", "IS_MEMBER_OF"},
    {"is supervisor of", "SUPERVISOR_OF"},
    {"is partner of", "PARTNER_OF"},
    {"has capability", "HAS_CAPABILITY"},
    {"can enter", "CAN_ENTER"},
    {"can instance", "CAN_INSTANCE"},
    {"partners with", "PARTNER_OF"},
    {"supervises", "SUPERVISOR_OF"},
    {"controls", "CONTROLS"},
    {"owns", "OWNS"}
  ]

  defp extract_edge(sentence) do
    lower = sentence |> String.downcase() |> String.trim()

    Enum.find_value(@verb_patterns, fn {verb, rel} ->
      case String.split(lower, " #{verb} ", parts: 2) do
        [subj_raw, obj_raw] ->
          subj = String.trim(subj_raw)
          obj = obj_raw |> String.trim() |> String.trim_trailing(".") |> String.trim_trailing(",")

          if subj != "" and obj != "" do
            %{"subject" => subj, "object" => obj, "rel" => rel}
          end

        _ ->
          nil
      end
    end)
  end
end
