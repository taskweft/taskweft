defmodule Taskweft.MCExecutor do
  @moduledoc """
  Pure Elixir Monte Carlo plan executor.

  Simulates each plan step probabilistically using per-action success
  probabilities.  `probs_json` is a JSON object mapping action names (or
  step indices as strings) to floats in `[0, 1]`.  Missing entries default
  to `1.0` (always succeeds).
  """

  @spec execute(String.t(), String.t(), String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, term()}
  def execute(domain_json, plan_json, probs_json, seed) do
    {:ok, mc_execute(domain_json, plan_json, probs_json, seed)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc "Raw execution — returns the trace JSON string."
  def mc_execute(_domain_json, plan_json, probs_json, seed) do
    plan = Jason.decode!(plan_json)
    probs = Jason.decode!(probs_json)

    :rand.seed(:exsplus, {seed, seed, seed})

    trace =
      plan
      |> Enum.with_index()
      |> Enum.map(fn {[action | _args], i} ->
        prob =
          Map.get(probs, action) ||
            Map.get(probs, Integer.to_string(i)) ||
            1.0

        success = :rand.uniform() < prob

        %{"step" => i, "action" => action, "success" => success, "prob" => prob}
      end)

    Jason.encode!(%{
      "trace" => trace,
      "succeeded" => Enum.all?(trace, & &1["success"]),
      "steps_run" => length(trace),
      "seed" => seed
    })
  end
end
