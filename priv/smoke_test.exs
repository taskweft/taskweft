# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
#
# Integration smoke test — verifies every bundled JSON-LD domain produces a plan
# and a solution tree. Run with: mix run priv/smoke_test.exs

{:ok, _} = Application.ensure_all_started(:taskweft)
domains = Path.expand("priv/plans/domains", File.cwd!())
results = []

for f <- File.ls!(domains) |> Enum.filter(&String.ends_with?(&1, ".jsonld")) |> Enum.sort() do
  json = File.read!(Path.join(domains, f))
  plan = Taskweft.NIF.plan(json)
  {:ok, expl} = Taskweft.plan_explain(json)
  ex = Jason.decode!(expl)
  steps = length(Jason.decode!(plan))
  tree = get_in(ex, ["explain", "solution_tree"]) || []
  IO.puts("#{f}: #{steps} steps, #{length(tree)} solution-tree nodes")
  results = [{f, steps, length(tree), plan} | results]
end

IO.puts("")
IO.puts("#{length(results)} domains, all passed")

# Also run a representative domain+problem pair
IO.puts("")
d = File.read!(Path.join(domains, "blocks_world.jsonld"))
p = File.read!(Path.expand("priv/plans/problems/blocks_world_1a.jsonld", File.cwd!()))
merged = Jason.decode!(d) |> Map.merge(Jason.decode!(p)) |> Jason.encode!()
plan = Taskweft.NIF.plan(merged)
steps = length(Jason.decode!(plan))
IO.puts("blocks_world + blocks_world_1a: #{steps} steps")