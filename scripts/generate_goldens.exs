# Run: elixir -S mix run scripts/generate_goldens.exs
# Generates _expected.json golden files for every domain+problem pair.

domains_dir = "priv/plans/domains"
problems_dir = "priv/plans/problems"
expected_dir = "priv/plans/expected"
File.mkdir_p!(expected_dir)

pairs = [
  {"blocks_world", "blocks_world_1a"},
  {"blocks_world", "blocks_world_1b"},
  {"blocks_world", "blocks_world_2a"},
  {"blocks_world", "blocks_world_2b"},
  {"blocks_world", "blocks_world_3"},
  {"blocks_world", "blocks_world_goal"},
  {"blocks_world", "blocks_world_multigoal"},
  {"entity_capabilities", "entity_caps_amphibious"},
  {"entity_capabilities", "entity_caps_boat"},
  {"entity_capabilities", "entity_caps_drone"},
  {"entity_capabilities", "entity_caps_goal"},
  {"entity_capabilities", "entity_caps_human"},
  {"entity_capabilities", "entity_caps_multi"},
  {"healthcare", "healthcare_one"},
  {"healthcare", "healthcare_shared"},
  {"healthcare", "healthcare_two"},
  {"job_shop_scheduling", "job_shop_both"},
  {"job_shop_scheduling", "job_shop_one"},
  {"rescue", "rescue_move"},
  {"rescue", "rescue_survey"},
  {"robosub", "robosub_full_mission"},
  {"robosub", "robosub_partial"},
  {"simple_travel", "simple_travel_goal"},
  {"simple_travel", "simple_travel_one"},
  {"simple_travel", "simple_travel_two"},
  {"temporal_travel", "temporal_travel_goal"},
  {"temporal_travel", "temporal_travel_one"},
  {"temporal_travel", "temporal_travel_two"},
  {"trust_topology_audit", "trust_topology_audit_curvenet"},
  {"service_bringup", "chi176_local_infra_bringup"},
]

# Standalone domains (no problem files)
standalone = ["meta_loader"]

# Skill allocation times out — skip for now (noted in test)
# {"skill_allocation", "skill_allocation_mzn_1m_2"}, etc.

# ── generate ──

ok = 0
skip = 0

for {domain_name, problem_name} <- pairs do
  domain_path = Path.join(domains_dir, "#{domain_name}.jsonld")
  problem_path = Path.join(problems_dir, "#{problem_name}.jsonld")
  golden_path = Path.join(expected_dir, "#{domain_name}__#{problem_name}_expected.json")

  domain_json = File.read!(domain_path)
  problem_json = File.read!(problem_path)

  merged =
    Jason.decode!(domain_json)
    |> Map.merge(Jason.decode!(problem_json))
    |> Jason.encode!()

  case Taskweft.plan_explain(merged) do
    {:ok, result_json} ->
      result = Jason.decode!(result_json)
      plan = result["plan"] || []
      explain = result["explain"] || %{}
      tree = get_in(explain, ["solution_tree"]) || []

      golden = %{
        "plan" => plan,
        "steps" => length(plan),
        "tree" => tree,
        "tree_nodes" => length(tree)
      }

      File.write!(golden_path, Jason.encode!(golden, pretty: true))
      IO.puts("  #{domain_name} + #{problem_name} → #{length(plan)} steps, #{length(tree)} tree nodes")
      ok = ok + 1

    {:error, reason} ->
      IO.puts("  SKIP #{domain_name} + #{problem_name}: #{inspect(reason)}")
      skip = skip + 1
  end
end

# ── standalone ──
for domain_name <- standalone do
  domain_path = Path.join(domains_dir, "#{domain_name}.jsonld")
  golden_path = Path.join(expected_dir, "#{domain_name}_expected.json")

  domain_json = File.read!(domain_path)

  {:ok, result_json} = Taskweft.plan_explain(domain_json)
  result = Jason.decode!(result_json)
  plan = result["plan"] || []
  explain = result["explain"] || %{}
  tree = get_in(explain, ["solution_tree"]) || []

  golden = %{
    "plan" => plan,
    "steps" => length(plan),
    "tree" => tree,
    "tree_nodes" => length(tree)
  }

  File.write!(golden_path, Jason.encode!(golden, pretty: true))
  IO.puts("  #{domain_name} (standalone) → #{length(plan)} steps, #{length(tree)} tree nodes")
  ok = ok + 1
end

IO.puts("\nDone. #{ok} golden files written, #{skip} skipped → #{expected_dir}")
