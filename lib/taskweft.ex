defmodule Taskweft do
  @moduledoc """
  Pure Elixir HTN planner, replanner, temporal checker, and ReBAC engine.

  This module is a drop-in replacement for the `taskweft_nif` package on
  runtimes that do not support Erlang NIFs (AtomVM, Popcorn/WASM, Supabase
  Edge Functions).  On regular BEAM with the NIF loaded it defers to the
  faster C++ implementations via `Taskweft.NIF`.
  """

  alias Taskweft.NIF
  alias Taskweft.ReBAC

  # ── Planning ──────────────────────────────────────────────────────────────

  @doc """
  Plan the domain and check temporal consistency.

  Returns `{:ok, result_json}` on success or `{:error, reason}` on failure.
  `result_json` contains the plan, schedule, and temporal metadata.
  """
  @spec plan(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def plan(domain_json, origin_iso \\ "PT0S", reference_date \\ "") do
    if reference_date == "" do
      {:ok, NIF.plan_with_temporal(domain_json, origin_iso)}
    else
      {:ok, NIF.plan_with_temporal_civil(domain_json, origin_iso, reference_date)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc "Replan after a step failure.  `fail_step` = -1 for full replan."
  @spec replan(String.t(), String.t(), integer()) :: {:ok, String.t()} | {:error, term()}
  def replan(domain_json, plan_json, fail_step \\ -1) do
    {:ok, NIF.replan(domain_json, plan_json, fail_step)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc "Check temporal consistency of an existing plan."
  @spec check_temporal(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def check_temporal(domain_json, plan_json, origin_iso \\ "PT0S", reference_date \\ "") do
    result =
      if reference_date == "" do
        NIF.check_temporal(domain_json, plan_json, origin_iso)
      else
        NIF.check_temporal_civil(domain_json, plan_json, origin_iso, reference_date)
      end

    {:ok, result}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # ── ReBAC ─────────────────────────────────────────────────────────────────

  def rebac_check(graph_json, subj, expr_json, obj, fuel \\ 8),
    do: ReBAC.check(graph_json, subj, expr_json, obj, fuel)

  def rebac_expand(graph_json, rel, obj, fuel \\ 8),
    do: ReBAC.expand(graph_json, rel, obj, fuel)

  # ── Bridge ────────────────────────────────────────────────────────────────

  def bridge_extract_entities(state_json), do: NIF.bridge_extract_entities(state_json)

  def bridge_plan_contents(plan_json, domain, entities_json),
    do: NIF.bridge_plan_contents(plan_json, domain, entities_json)
end
