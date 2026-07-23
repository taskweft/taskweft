# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.DomainTest do
  use ExUnit.Case, async: true

  @domains_path Path.expand("priv/plans/domains", File.cwd!())

  for f <- File.ls!(@domains_path) |> Enum.filter(&String.ends_with?(&1, ".jsonld")) |> Enum.sort() do
    name = String.replace(f, ".jsonld", "")
    json = File.read!(Path.join(@domains_path, f))
    golden_path = Path.join(@domains_path, "#{name}_expected.json")
    golden = Jason.decode!(File.read!(golden_path))

    @tag :domain
    test "#{name} produces expected plan and solution tree" do
      plan = Taskweft.NIF.plan(unquote(json))
      plan_list = Jason.decode!(plan)

      {:ok, expl} = Taskweft.plan_explain(unquote(json))
      ex = Jason.decode!(expl)
      tree = get_in(ex, ["explain", "solution_tree"]) || []

      expected = unquote(Macro.escape(golden))

      assert length(plan_list) == expected["steps"],
             "#{unquote(name)}: expected #{expected["steps"]} steps, got #{length(plan_list)}"

      assert length(tree) == expected["tree_nodes"],
             "#{unquote(name)}: expected #{expected["tree_nodes"]} tree nodes, got #{length(tree)}"

      assert plan_list == expected["plan"],
             "#{unquote(name)}: plan mismatch"
    end
  end

  @problems_path Path.expand("priv/plans/problems", File.cwd!())

  # Representative domain+problem pairs
  @pairs [
    {"blocks_world", "blocks_world_1a", 6},
    {"blocks_world", "blocks_world_goal", 6},
    {"entity_capabilities", "entity_caps_drone", 1},
    {"healthcare", "healthcare_one", 4},
    {"simple_travel", "simple_travel_one", 1},
    {"temporal_travel", "temporal_travel_one", 1}
  ]

  for {domain, problem, expected_steps} <- @pairs do
    d = File.read!(Path.join(@domains_path, "#{domain}.jsonld"))
    p = File.read!(Path.join(@problems_path, "#{problem}.jsonld"))
    merged =
      Jason.decode!(d) |> Map.merge(Jason.decode!(p)) |> Jason.encode!()

    @tag :domain
    test "#{domain} + #{problem} produces #{expected_steps} steps" do
      plan = Taskweft.NIF.plan(unquote(merged))
      steps = length(Jason.decode!(plan))
      assert steps == unquote(expected_steps),
             "#{unquote(domain)}+#{unquote(problem)}: expected #{unquote(expected_steps)} steps, got #{steps}"
    end
  end
end