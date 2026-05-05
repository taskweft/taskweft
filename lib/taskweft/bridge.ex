defmodule Taskweft.Bridge do
  @moduledoc "Pure Elixir bridge utilities — content and entity extraction."

  @doc "Produce a string binding token `\"var arg val\"`."
  def binding_content(var, arg, val), do: "#{var} #{arg} #{val}"

  @doc "Extract inner dict keys from a PDDL-style state (one level deep)."
  def extract_state_entities(state_json) do
    state = Jason.decode!(state_json)

    state
    |> Map.values()
    |> Enum.flat_map(fn
      m when is_map(m) -> Map.keys(m)
      _ -> []
    end)
    |> Enum.uniq()
  end

  @doc "Build content records for storing a plan result in memory."
  def plan_result_contents(plan_json, domain, entities_json) do
    plan = Jason.decode!(plan_json)
    entities = Jason.decode!(entities_json)

    contents =
      Enum.map(plan, fn [action | args] ->
        relevant = Enum.filter(entities, &(&1 in args))

        %{
          "content" => "#{domain}: #{action}(#{Enum.join(args, ", ")})",
          "category" => "plan_step",
          "tags" => [domain, action | relevant]
        }
      end)

    Jason.encode!(contents)
  end

  @doc "Build content records for all (var, arg, val) triples in a state."
  def state_bindings_contents(state_json, domain, category) do
    state = Jason.decode!(state_json)

    contents =
      for {var, values} <- state,
          is_map(values),
          {arg, val} <- values do
        %{
          "content" => binding_content(var, arg, inspect(val)),
          "category" => category,
          "tags" => [domain, var]
        }
      end

    Jason.encode!(contents)
  end
end
