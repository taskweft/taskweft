# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.CapabilitiesReBACTest do
  @moduledoc """
  Coverage for ADR 0004 (unify domain `capabilities` with the ReBAC
  relation-expression engine, taskweft#96): action capability guards are
  evaluated against a `TwReBAC::TwReBACGraph` (`tw_rebac.hpp`) rather than
  precomputed booleans, so a domain can express requirements the old flat
  `{"entities": ..., "actions": ...}` shape could not — transitive team
  membership, and composed relation expressions (union/intersection/...).
  """
  use ExUnit.Case, async: true

  defp domain(extra), do: Map.merge(%{"@type" => "domain:Definition", "name" => "t"}, extra)

  defp plans?(domain_json) do
    case Taskweft.plan(domain_json) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  describe "backward compatibility: flat entities/actions shape" do
    defp flat_domain(entity_caps) do
      domain(%{
        "variables" => [%{"name" => "done", "init" => %{"a" => false}}],
        "capabilities" => %{
          "entities" => %{"drone_1" => entity_caps},
          "actions" => %{"a_fly" => ["fly"]}
        },
        "actions" => %{
          "a_fly" => %{
            "params" => ["agent"],
            "body" => [%{"pointer/set" => "/done/a", "value" => true}]
          }
        },
        "tasks" => [["a_fly", "drone_1"]]
      })
      |> Jason.encode!()
    end

    test "an entity holding the required capability may act" do
      assert plans?(flat_domain(["fly"]))
    end

    test "an entity lacking the required capability may not act" do
      refute plans?(flat_domain(["swim"]))
    end
  end

  describe "explicit graph: transitive capability via team membership" do
    defp team_domain(agent_on_team?) do
      edges =
        if agent_on_team? do
          [%{"subject" => "alice", "object" => "flight_team", "rel" => "IS_MEMBER_OF"}]
        else
          []
        end

      domain(%{
        "variables" => [%{"name" => "done", "init" => %{"a" => false}}],
        "capabilities" => %{
          "graph" => %{
            "edges" =>
              edges ++
                [%{"subject" => "flight_team", "object" => "fly", "rel" => "HAS_CAPABILITY"}],
            "definitions" => %{}
          },
          "actions" => %{"a_fly" => ["fly"]}
        },
        "actions" => %{
          "a_fly" => %{
            "params" => ["agent"],
            "body" => [%{"pointer/set" => "/done/a", "value" => true}]
          }
        },
        "tasks" => [["a_fly", "alice"]]
      })
      |> Jason.encode!()
    end

    test "a member of a capability-holding team inherits the capability transitively" do
      assert plans?(team_domain(true))
    end

    test "a non-member does not inherit the team's capability" do
      refute plans?(team_domain(false))
    end
  end

  describe "full relation-expression action requirement" do
    defp union_domain(caps) do
      domain(%{
        "variables" => [%{"name" => "done", "init" => %{"a" => false}}],
        "capabilities" => %{
          "entities" => %{"drone_1" => caps},
          "actions" => %{
            "a_fly" => [
              %{
                "rel" => %{
                  "type" => "union",
                  "a" => %{"type" => "base", "rel" => "HAS_CAPABILITY"},
                  "b" => %{"type" => "base", "rel" => "HAS_CAPABILITY"}
                },
                "object" => "fly"
              }
            ]
          }
        },
        "actions" => %{
          "a_fly" => %{
            "params" => ["agent"],
            "body" => [%{"pointer/set" => "/done/a", "value" => true}]
          }
        },
        "tasks" => [["a_fly", "drone_1"]]
      })
      |> Jason.encode!()
    end

    test "a union expression over HAS_CAPABILITY still matches a direct edge" do
      assert plans?(union_domain(["fly"]))
    end

    test "a union expression still rejects an unrelated capability" do
      refute plans?(union_domain(["swim"]))
    end
  end
end
