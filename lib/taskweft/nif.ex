defmodule Taskweft.NIF do
  @moduledoc """
  Pure Elixir NIF fallback module.

  On regular BEAM this module is normally replaced at load time by the C++
  NIF from `taskweft_nif` via `@on_load`.  Here, every function is
  implemented in pure Elixir so the module works unchanged in AtomVM /
  Popcorn (where `@on_load` and `:erlang.load_nif/2` are not supported).

  Architecture note — NIF fallbacks vs full port:
  The correct long-term strategy is **NIF fallbacks**: keep the C++ planner
  as the fast production path on BEAM, and replace the `nif_error` stubs in
  `taskweft_nif/lib/taskweft/nif.ex` with real Elixir implementations.
  AtomVM silently skips `@on_load`, so the Elixir stubs become the active
  implementation in WASM/edge contexts with zero conditional logic needed.
  """

  alias Taskweft.Planner
  alias Taskweft.Temporal
  alias Taskweft.ReBAC
  alias Taskweft.Bridge
  alias Taskweft.MCExecutor

  # ── Planning ──────────────────────────────────────────────────────────────

  def plan(domain_json) do
    case Planner.run(Jason.decode!(domain_json)) do
      {:ok, p} -> Planner.encode_plan(p)
      {:error, r} -> raise r
    end
  end

  def plan_with_temporal(domain_json, origin_iso),
    do: Temporal.plan_with_temporal(domain_json, origin_iso)

  def plan_with_temporal_civil(domain_json, origin_iso, reference_date),
    do: Temporal.plan_with_temporal_civil(domain_json, origin_iso, reference_date)

  def replan(domain_json, plan_json, fail_step) do
    domain = Jason.decode!(domain_json)
    plan = Jason.decode!(plan_json)
    actions = domain["actions"] || %{}
    fail_idx = if fail_step < 0, do: 0, else: fail_step

    state = build_initial_state(domain)

    pre_state =
      Enum.reduce_while(Enum.take(plan, fail_idx), state, fn [action | _], s ->
        spec = actions[action] || %{}
        case apply_noop_action(s, spec) do
          {:ok, new_s} -> {:cont, new_s}
          _ -> {:halt, s}
        end
      end)

    result =
      case Planner.run(Map.put(domain, "state", pre_state)) do
        {:ok, new_plan} ->
          %{
            "recovered" => true,
            "fail_step" => fail_idx,
            "new_plan" => new_plan,
            "original_plan" => plan
          }

        {:error, _} ->
          %{
            "recovered" => false,
            "fail_step" => fail_idx,
            "new_plan" => nil,
            "original_plan" => plan
          }
      end

    Jason.encode!(result)
  end

  defp build_initial_state(%{"variables" => vars}) when is_list(vars) do
    Enum.reduce(vars, %{}, fn
      %{"name" => name, "init" => init}, acc -> Map.put(acc, name, init)
      _, acc -> acc
    end)
  end

  defp build_initial_state(%{"state" => s}) when is_map(s), do: s
  defp build_initial_state(_), do: %{}

  defp apply_noop_action(state, _spec), do: {:ok, state}

  # ── Temporal ──────────────────────────────────────────────────────────────

  def check_temporal(domain_json, plan_json, origin_iso),
    do: Temporal.check_temporal(domain_json, plan_json, origin_iso)

  def check_temporal_civil(domain_json, plan_json, origin_iso, reference_date),
    do: Temporal.check_temporal_civil(domain_json, plan_json, origin_iso, reference_date)

  # ── ReBAC ─────────────────────────────────────────────────────────────────

  def rebac_add_edge(graph_json, subj, obj, rel),
    do: ReBAC.add_edge(graph_json, subj, obj, rel)

  def rebac_check(graph_json, subj, expr_json, obj, fuel),
    do: ReBAC.check(graph_json, subj, expr_json, obj, fuel)

  def rebac_expand(graph_json, rel, obj, fuel),
    do: ReBAC.expand(graph_json, rel, obj, fuel)

  def rebac_parse_relation_edges(facts_json, trust_threshold),
    do: ReBAC.parse_relation_edges(facts_json, trust_threshold)

  def rebac_can(graph_json, subj, capability, max_depth) do
    edges = Jason.decode!(graph_json)["edges"] || []
    result = dfs_can(edges, subj, capability, max_depth, [])
    Jason.encode!(result)
  end

  defp dfs_can(edges, subj, capability, depth, visited) do
    cond do
      depth < 0 or subj in visited ->
        %{"authorized" => false, "path" => []}

      Enum.any?(edges, fn e ->
        e["subject"] == subj and e["object"] == capability and
          e["rel"] in ["HAS_CAPABILITY", "CONTROLS", "OWNS"]
      end) ->
        %{"authorized" => true, "path" => [subj, capability]}

      true ->
        nexts =
          for %{"subject" => s, "object" => o} <- edges, s == subj, do: o

        Enum.find_value(nexts, %{"authorized" => false, "path" => []}, fn next ->
          r = dfs_can(edges, next, capability, depth - 1, [subj | visited])
          if r["authorized"], do: %{r | "path" => [subj | r["path"]]}, else: nil
        end) || %{"authorized" => false, "path" => []}
    end
  end

  def rebac_get_entity_capabilities(graph_json, entity) do
    edges = Jason.decode!(graph_json)["edges"] || []

    for %{"subject" => s, "object" => o, "rel" => "HAS_CAPABILITY"} <- edges,
        s == entity,
        do: o
  end

  def rebac_get_entities_with_capability(graph_json, capability) do
    edges = Jason.decode!(graph_json)["edges"] || []

    for %{"subject" => s, "object" => o, "rel" => "HAS_CAPABILITY"} <- edges,
        o == capability,
        do: s
  end

  def rebac_cache_clear, do: "ok"

  # ── Bridge ────────────────────────────────────────────────────────────────

  def bridge_binding_content(var, arg, val), do: Bridge.binding_content(var, arg, val)
  def bridge_extract_entities(state_json), do: Bridge.extract_state_entities(state_json)

  def bridge_plan_contents(plan_json, domain, entities_json),
    do: Bridge.plan_result_contents(plan_json, domain, entities_json)

  def bridge_state_bindings(state_json, domain, category),
    do: Bridge.state_bindings_contents(state_json, domain, category)

  # ── Monte Carlo ───────────────────────────────────────────────────────────

  def mc_execute(domain_json, plan_json, probs_json, seed),
    do: MCExecutor.mc_execute(domain_json, plan_json, probs_json, seed)

  # ── Cache (no-ops in pure Elixir) ─────────────────────────────────────────

  def domain_cache_clear, do: "ok"
end
