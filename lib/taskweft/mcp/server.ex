defmodule Taskweft.MCP.Server do
  @moduledoc """
  MCP server for Taskweft.

  Start with `mix taskweft.mcp` or `taskweft mcp` (HTTP only — see `Taskweft.CLI`).

  The planner model is **RECTGTN** — Relationship-Enabled Capability-Temporal
  Goal-Task-Network. A domain's `todo_list` (GTPyHOP's own term for this
  heterogeneous list) holds three task kinds: `TwCall` call arrays
  (`'E'`/`'T'`), `TwGoal` `{"goal": [...]}` entries (`'G'`, conjunctive
  bindings satisfied via a goal method — an ordinary `methods` entry named
  after the state var it targets; there's no separate `goals` key), and
  `TwMultiGoal` `{"multigoal": …}` entries (`'N'`). Two more layers apply on
  top of any task kind: capability guards (`'R'`/`'C'`, top-level
  `capabilities` graph data plus a hand-written `rebac/check` eval step per
  action — no compiled sugar) and per-action temporal duration (`'T'`, an
  action's `duration` field). The `plan` tool's `domain_json` description
  documents all five with golden shapes (and rejected shapes for
  goal/multigoal — capabilities/duration are plan-time, not load-time, so
  nothing there is structurally validated).

  ## Tools

  | Tool | Description |
  |------|-------------|
  | `plan` | Run the HTN planner over an Elixir DSL domain (variables, actions, methods, capabilities, temporal duration) |
  | `replan` | Recover from a failed plan step |

  `check_temporal` is not exposed as its own tool; every `plan` response
  already includes a `"temporal"` block computed from action `duration`
  fields. ReBAC, bridge, and cache NIF entrypoints are not exposed.

  ## Prompts

  `plan_problem` (solve a problem/domain pair), `plan_goal` (build a TwGoal or
  TwMultiGoal problem), `plan_capability_temporal` (build a domain using
  capability guards and/or action durations), `replan_after_failure`, and
  `work_queue`.

  ## Resources

  Every `.jsonld` under `priv/plans/{domains,problems}` is exposed as
  `taskweft://domains/<file>` and `taskweft://problems/<file>`; new files require
  `mix compile` to register.
  """

  use ExMCP.Server.Handler

  # No `version:` here — ex_mcp's DSL requires a compile-time literal for it
  # (confirmed empirically: __using__'s opts get wrapped in Macro.escape/1,
  # which freezes ANY nested `@attr` read or function call as inert AST data
  # rather than letting it compile as ordinary code, so there's no way to
  # derive this from mix.exs's own @version without patching ex_mcp). A
  # hand-copied literal here silently drifted from mix.exs twice already
  # (taskweft/mcp#23, #24) — rather than keep chasing ways to sync two
  # numbers that don't need to be synced, just don't advertise one; ex_mcp
  # falls back to its own default ("1.0.0") for `serverInfo.version`, which
  # callers should treat as informational only, not as this package's actual
  # release version (that's `Application.spec(:taskweft, :vsn)`, read at
  # request time — not a compile-time module attribute, so it isn't subject
  # to the self-referential-.app-spec problem `TaskweftDeploy.Router`'s own
  # `@taskweft_version` hit — used correctly elsewhere in this file, e.g.
  # the taskweft://meta resource).
  use ExMCP.Server.DSL, name: "taskweft"

  # ---------- TOOLS ----------

  tool "plan",
       "Run the IPyHOP-style HTN planner over an Elixir DSL domain. See docs/rectgtn.md for the full RECTGTN feature reference." do
    param(:domain_json, :string,
      required: true,
      description: """
      A RECTGTN HTN domain defined in Elixir DSL syntax (AST-safe, no runtime code execution):
          variable :pos, type: :ref, init: %{a: "table", b: "hand"}
          action :a_pickup, params: [:block], body: [...]
          method :move_one, params: [:block, :dest], alternatives: [...]

      Elixir DSL only. See docs/rectgtn.md for the complete RECTGTN feature reference.

      ── State variables ──
      Typed per-entity state. Type is mandatory: bool, int, float, float2/3/4,
      float2x2/3x3/4x4, ref. ref values are opaque identity references (e.g.
      "table", "hand", agent names). No string/enum type — symbolic concepts
      use ref or capability/ReBAC membership.

          variable :pos, type: :ref, init: %{a: "table", b: "hand", c: "table"}
          variable :clear, type: :bool, init: %{a: true, b: false, c: true}
          variable :holding, type: :bool, init: %{hand: false}

      ── Actions ──
      Primitive operations. Body steps are pointer/set (effects) or eval
      (guards/preconditions). Params are substituted via {curly} syntax.

          action :a_pickup,
            params: [:block],
            body: [
              condition(:math/eq, pointer_get("/pos/{block}"), "table"),
              condition(:math/eq, pointer_get("/clear/{block}"), true),
              pointer_set("/pos/{block}", "hand"),
              pointer_set("/clear/{block}", false),
              pointer_set("/holding/hand", "{block}")
            ]

      Actions may carry a temporal duration (ISO 8601):

          action :a_fly,
            params: [:agent, :to_loc],
            duration: "PT5M",
            body: [pointer_set("/loc/{agent}", "{to_loc}")]

      ── Methods (compound tasks) ──
      Decomposed via alternatives. Each alternative is a named sequence of
      subtask calls (to actions or other methods). Optional check guards.

          method :move_one,
            params: [:block, :dest],
            alternatives: [
              alt(:get_and_put, subtasks: [[:get, "{block}"], [:put, "{block}", "{dest}"]])
            ]

          method :get,
            params: [:block],
            alternatives: [
              alt(:pickup_from_table,
                check: [condition(:math/eq, pointer_get("/pos/{block}"), "table")],
                subtasks: [[:a_pickup, "{block}"]]
              ),
              alt(:unstack, subtasks: [[:a_unstack, "{block}"]])
            ]

      ── Three task kinds (todo_list) ──
      todo_list can mix all three. A todo_list entry is either a call array
      [name, arg...] (TwCall), a goal {goal: [{pointer, eq}, ...]} (TwGoal),
      or a multigoal {multigoal: {var: {key: val}}} (TwMultiGoal):

          # TwCall — call an action or method directly
          todo_list [[:move_one, :a, :table], [:move_one, :c, :b]]

          # TwGoal — desired state bindings, solved via goal methods
          # (methods named after the state var they target)
          todo_list [goal: [pointer: "/switch/x", eq: true]]

          # TwMultiGoal — planner backjumps over which binding to satisfy first
          todo_list [multigoal: %{switch: %{x: true, y: true}}]

          # Mixed: calls + goals + multigoals in one list
          todo_list [
            [:move_one, :a, :table],
            %{goal: [%{pointer: "/switch/x", eq: true}]}
          ]

      ── Capabilities & ReBAC ──
      Entities hold capabilities via a ReBAC (Relationship-Based Access
      Control) graph. Action guards check HAS_CAPABILITY (or any composed
      relation) against the graph. Relations: HAS_CAPABILITY, CONTROLS, OWNS,
      IS_MEMBER_OF, DELEGATED_TO, SUPERVISOR_OF, PARTNER_OF, CAN_ENTER,
      CAN_INSTANCE.

          capabilities %{
            entities: %{drone_1: [:fly], human_1: [:walk]},
            graph: [
              %{subject: "alice", rel: "IS_MEMBER_OF", object: "flight_team"},
              %{subject: "flight_team", rel: "HAS_CAPABILITY", object: "fly"}
            ]
          }

          # ReBAC guard: alice qualifies via IS_MEMBER_OF -> HAS_CAPABILITY chain
          action :a_fly,
            params: [:agent, :to],
            duration: "PT5M",
            body: [
              rebac_check("{agent}", "HAS_CAPABILITY", "fly"),
              pointer_set("/loc/{agent}", "{to}")
            ]

      ── Full example: multi-agent with capabilities + temporal ──

          variable :loc, type: :ref, init: %{drone_1: "base", boat_1: "harbor", human_1: "base"}

          action :a_fly, params: [:agent, :to],
            duration: "PT5M",
            body: [
              rebac_check("{agent}", "HAS_CAPABILITY", "fly"),
              pointer_set("/loc/{agent}", "{to}")
            ]

          action :a_swim, params: [:agent, :to],
            duration: "PT20M",
            body: [
              rebac_check("{agent}", "HAS_CAPABILITY", "swim"),
              pointer_set("/loc/{agent}", "{to}")
            ]

          action :a_walk, params: [:agent, :to],
            duration: "PT30M",
            body: [
              rebac_check("{agent}", "HAS_CAPABILITY", "walk"),
              pointer_set("/loc/{agent}", "{to}")
            ]

          method :m_move, params: [:agent, :to],
            alternatives: [
              alt(:fly, subtasks: [[:a_fly, "{agent}", "{to}"]]),
              alt(:swim, subtasks: [[:a_swim, "{agent}", "{to}"]]),
              alt(:walk, subtasks: [[:a_walk, "{agent}", "{to}"]])
            ]

          capabilities %{
            entities: %{
              drone_1: [:fly], drone_2: [:fly],
              boat_1: [:swim], boat_2: [:swim],
              human_1: [:walk], human_2: [:walk],
              amphibious_1: [:swim, :walk]
            }
          }

          todo_list [[:m_move, :drone_1, :city]]

      The planner only tries alternatives whose capability guard the agent
      satisfies. drone_1 has [:fly] → tries fly (PT5M). human_1 has [:walk]
      → tries walk (PT30M). amphibious_1 has [:swim, :walk] → tries swim
      first (PT20M), then walk (PT30M) if swim fails.

      The plan response includes a temporal block with STN consistency:
          {"temporal": {"consistent": true, "total": "PT5M",
            "steps": [{"action": "a_fly", "start": "PT0S", "end": "PT5M"}]}}

      See also: https://github.com/taskweft/taskweft/blob/main/docs/rectgtn.md
      """
    )

    param(:explain, :boolean,
      required: false,
      description:
        "When true, include an explain tree for successful plans and return structured no_plan diagnostics instead of a bare failure token."
    )

    run(fn args, state ->
      guarded(state, fn ->
        with {:ok, domain_json} <-
               parse_domain_input(Map.fetch!(args, :domain_json)),
             explain = Map.get(args, :explain, false) do
          plan_with_optional_explain(domain_json, explain)
        end
      end)
    end)
  end

  tool "replan",
       "Replan after a step failure. Pass the original Elixir DSL domain, the previously-returned plan, and the index of the failed step (-1 for full replan)." do
    param(:domain_json, :string,
      required: true,
      description: "Elixir DSL domain definition (same format as the plan tool's domain_json)."
    )

    param(:plan_json, :object,
      required: true,
      description:
        "The previously-returned plan object (the {\"plan\": [...]} envelope or a bare step array)."
    )

    param(:fail_step, :integer,
      required: false,
      description: "Index of the failed step; -1 for a full replan."
    )

    run(fn args, state ->
      guarded(state, fn ->
        with {:ok, domain_json} <-
               parse_domain_input(Map.fetch!(args, :domain_json)),
             plan_arg = Map.fetch!(args, :plan_json),
             fail_step = Map.get(args, :fail_step, -1),
             {:ok, steps} <- decode_plan(plan_arg),
             :ok <- validate_fail_step(steps, fail_step),
             :ok <- validate_for_replan(domain_json) do
          # tw_replan wants a bare top-level step array; the {"plan":[...]} envelope
          # that `plan` returns silently parses to 0 steps (#43), so re-encode the
          # step list before handing it to the NIF.
          Taskweft.replan(domain_json, Jason.encode!(steps), fail_step)
        end
      end)
    end)
  end

  tool "validate",
       "Validate an Elixir DSL domain/problem document without planning. Returns the normalized document JSON on success, or a validation error. plan/replan do not validate — call this first if you want to check a document's shape without also attempting to solve it." do
    param(:domain_json, :string,
      required: true,
      description: "Elixir DSL domain definition (same format as the plan tool's domain_json)."
    )

    run(fn args, state ->
      guarded(state, fn ->
        with {:ok, domain_json} <-
               parse_domain_input(Map.fetch!(args, :domain_json)) do
          validate_domain(domain_json)
        end
      end)
    end)
  end

  tool "convert",
       "Convert between Elixir DSL and YAML-LD formats." do
    param(:domain, :string,
      required: true,
      description: "The domain string to convert."
    )

    param(:to, :string,
      required: false,
      default: "yaml",
      description: ~s[Target format: "yaml" (DSL -> YAML-LD, default) or "dsl" (YAML-LD -> DSL).]
    )

    run(fn args, state ->
      guarded(state, fn ->
        domain = Map.fetch!(args, :domain)
        target = Map.get(args, :to, "yaml")

        case target do
          "dsl" ->
            case Taskweft.Domain.SafeParser.parse(domain) do
              {:ok, json} ->
                with {:ok, map} <- Jason.decode(json) do
                  {:ok, Taskweft.Domain.ToDSL.domain_to_dsl(map)}
                else
                  {:error, reason} -> {:error, "Internal decode: #{reason}"}
                end

              {:error, _} = err ->
                err
            end

          "yaml" ->
            case Taskweft.Domain.SafeParser.parse(domain) do
              {:ok, json} ->
                with {:ok, map} <- Jason.decode(json) do
                  {:ok, encode_yaml(map)}
                else
                  {:error, reason} -> {:error, "Internal decode: #{reason}"}
                end

              {:error, _} = err ->
                err
            end

          other ->
            {:error, ~s(unknown target format: "#{other}". Use "yaml" or "dsl".)}
        end
      end)
    end)
  end

  # ---------- RESOURCES ----------
  # Every bundled `.jsonld` under priv/plans/{domains,problems} is readable. 1.0's
  # `resource` needs a literal URI, so the per-file set is exposed as two templates.

  resource "taskweft://meta", "Taskweft MCP metadata" do
    title("Taskweft metadata")
    mime_type("application/json")

    read(fn _args, _state ->
      version = Application.spec(:taskweft, :vsn) |> to_string()
      {:ok, Jason.encode!(%{"name" => "taskweft", "version" => version})}
    end)
  end

  resource_template "taskweft://domains/{file}", "RECTGTN HTN domain" do
    title("HTN domain")
    mime_type("application/ld+json")
    param(:file, :string)

    read(fn %{file: file}, state -> read_jsonld("taskweft://domains/#{file}", state) end)
  end

  resource_template "taskweft://problems/{file}", "RECTGTN HTN problem" do
    title("HTN problem")
    mime_type("application/ld+json")
    param(:file, :string)

    read(fn %{file: file}, state -> read_jsonld("taskweft://problems/#{file}", state) end)
  end

  # ---------- PROMPTS ----------

  prompt "work_queue",
         "Stored skill — read taskweft://problems/work_queue.jsonld and its sibling .notes.json, and report decoded status." do
    title("Work queue status")

    render(fn _args, state ->
      message(
        "Read the resources taskweft://problems/work_queue.jsonld (the plannable state/todo_list) " <>
          "and taskweft://problems/work_queue.notes.json (human/LLM-facing status metadata, not " <>
          "part of the planning document) and report the decoded status: phases, pass conditions, " <>
          "scenarios, and stack readiness.",
        state
      )
    end)
  end

  prompt "plan_problem",
         "Sample workflow — solve a problem against a domain via the `plan` tool." do
    title("Plan a problem")
    arg(:domain, required: false, description: "Domain file name, e.g. blocks_world.jsonld")
    arg(:problem, required: false, description: "Problem file name, e.g. blocks_world_1a.jsonld")

    render(fn args, state ->
      domain = args[:domain] || "<domain>.jsonld"
      problem = args[:problem] || "<problem>.jsonld"

      message(
        "Read taskweft://domains/#{domain} and taskweft://problems/#{problem}, then call the `plan` tool with the combined Elixir DSL domain.",
        state
      )
    end)
  end

  prompt "plan_goal",
         "Sample workflow — solve a goal or multigoal (RECTGTN 'G'/'N') against a domain via the `plan` tool." do
    title("Plan a goal / multigoal")
    arg(:domain, required: false, description: "Domain file name, e.g. blocks_world.jsonld")

    arg(:kind,
      required: false,
      description: "Task kind: \"goal\" (TwGoal) or \"multigoal\" (TwMultiGoal)"
    )

    render(fn args, state ->
      domain = args[:domain] || "<domain>.jsonld"
      kind = args[:kind] || "goal"

      shape =
        if kind == "multigoal" do
          ~s(a `{"multigoal": {<var>: {<key>: <desired>, ...}}}` entry in "todo_list")
        else
          ~s(a `{"goal": [{"pointer": "/var/key", "eq": <desired>}, ...]}` entry in "todo_list")
        end

      message(
        "Read taskweft://domains/#{domain} for its actions and methods (goal methods are " <>
          "ordinary methods named after the state var they target, not a separate key). " <>
          "Build a domain:Problem whose desired end-state is expressed as #{shape} " <>
          "(RECTGTN #{if kind == "multigoal", do: "'N' TwMultiGoal", else: "'G' TwGoal"}), " <>
          "then call the `plan` tool with the merged domain. The planner solves each " <>
          "binding via the matching goal method; a multigoal additionally backjumps " <>
          "over which binding to satisfy first.",
        state
      )
    end)
  end

  prompt "plan_capability_temporal",
         "Sample workflow — build a domain using capability guards and/or action durations (RECTGTN 'R'/'C'/'T'), then plan it." do
    title("Plan with capabilities / temporal duration")

    arg(:domain,
      required: false,
      description: "Domain file name, e.g. entity_capabilities.jsonld or temporal_travel.jsonld"
    )

    render(fn args, state ->
      domain = args[:domain] || "entity_capabilities.jsonld"

      message(
        "Read taskweft://domains/#{domain}. If it has a top-level \"capabilities\" object " <>
          "({\"entities\": {<entity>: [<cap>,...]}, \"graph\": {...}}), note which capabilities " <>
          "each entity holds — a capability guard is a hand-written {\"eval\": {\"type\": " <>
          "\"rebac/check\", \"rel\": <relation>, \"subject\": <ref>, \"object\": <cap>}} step in " <>
          "an action's own body (RECTGTN 'R'/'C'; this is a plan-time guard, not a load-time " <>
          "validation). If any action carries a \"duration\" (ISO 8601, e.g. \"PT5M\") that's " <>
          "RECTGTN 'T' — the `plan` tool's response already includes a \"temporal\" block (STN " <>
          "consistency + per-step start/end) computed from those durations, with no extra call " <>
          "needed. Then call the `plan` tool with the domain JSON as-is (add a \"todo_list\" " <>
          "entry if the bundled file doesn't already have one).",
        state
      )
    end)
  end

  prompt "replan_after_failure",
         "Sample workflow — recover from a failed plan step via the `replan` tool." do
    title("Replan after failure")
    arg(:domain, required: false, description: "Domain file name")
    arg(:fail_step, required: false, description: "Index of the failed step")

    render(fn args, state ->
      domain = args[:domain] || "<domain>.jsonld"
      fail_step = args[:fail_step] || "<index>"

      message(
        "Read taskweft://domains/#{domain}, then call the `replan` tool with the original plan and fail_step #{fail_step}.",
        state
      )
    end)
  end

  # ---------- HELPERS ----------

  # Parse an Elixir DSL domain string. AST-safe, no runtime code execution.
  defp parse_domain_input(raw) do
    Taskweft.Domain.SafeParser.parse(raw)
  end

  # Same rationale as plan_with_optional_explain/2: surface a schema error
  # instead of letting a malformed domain reach the NIF as a bare
  # "failed_to_load_domain" token.
  defp validate_for_replan(json) do
    case validate_domain(json) do
      {:error, _reason} = error -> error
      _ok -> :ok
    end
  end

  defp validate_domain(json) do
    case Taskweft.JSONLD.Loader.load_string(json) do
      {:ok, result_json} ->
        with {:ok, domain} <- Jason.decode(result_json) do
          {:ok, Taskweft.Domain.ToDSL.domain_to_dsl(domain)}
        else
          _ -> {:ok, result_json}
        end

      {:error, _} = err ->
        err
    end
  end

  # Minimal YAML encoder for the convert tool. Only handles the
  # subset of YAML that RECTGTN domain maps produce.
  defp encode_yaml(value), do: encode_yaml(value, 0)

  defp encode_yaml(value, indent) when is_map(value) do
    prefix = String.duplicate("  ", indent)

    lines =
      Enum.map(value, fn {k, v} ->
        case v do
          m when is_map(m) ->
            "#{prefix}#{k}:\n" <> encode_yaml(m, indent + 1)

          l when is_list(l) ->
            "#{prefix}#{k}:\n" <> encode_yaml_list(l, indent + 1)

          _ ->
            "#{prefix}#{k}: #{encode_yaml_scalar(v)}\n"
        end
      end)

    Enum.join(lines, "")
  end

  defp encode_yaml(list, indent) when is_list(list) do
    encode_yaml_list(list, indent)
  end

  defp encode_yaml_list(list, indent) do
    prefix = String.duplicate("  ", indent)

    lines =
      Enum.map(list, fn item ->
        case item do
          m when is_map(m) ->
            "#{prefix}- " <> first_line(m) <> "\n" <> encode_yaml(m, indent + 1)

          l when is_list(l) ->
            elements = Enum.map(l, &encode_yaml_scalar/1) |> Enum.join(", ")
            "#{prefix}- [#{elements}]\n"

          _ ->
            "#{prefix}- #{encode_yaml_scalar(item)}\n"
        end
      end)

    Enum.join(lines, "")
  end

  defp first_line(map) do
    case Enum.at(Enum.to_list(map), 0) do
      {k, v} when is_binary(v) -> "#{k}: #{v}"
      {k, v} when is_integer(v) -> "#{k}: #{v}"
      {k, v} when is_boolean(v) -> "#{k}: #{v}"
      {k, v} when is_atom(v) -> "#{k}: #{v}"
      _ -> ""
    end
  end

  defp encode_yaml_scalar(val) when is_binary(val), do: val
  defp encode_yaml_scalar(val) when is_integer(val), do: to_string(val)
  defp encode_yaml_scalar(val) when is_float(val), do: to_string(val)
  defp encode_yaml_scalar(true), do: "true"
  defp encode_yaml_scalar(false), do: "false"
  defp encode_yaml_scalar(val) when is_atom(val), do: Atom.to_string(val)

  # `fail_step = -1` means full replan. Any other value must point at a real
  # index in the plan; otherwise the planner silently treats it as
  # past-the-end success.
  defp validate_fail_step(_steps, -1), do: :ok

  defp validate_fail_step(steps, fail_step)
       when is_list(steps) and is_integer(fail_step) and fail_step >= 0 do
    if fail_step < length(steps),
      do: :ok,
      else: {:error, "fail_step #{fail_step} out of range for plan of length #{length(steps)}"}
  end

  defp validate_fail_step(_steps, fail_step),
    do: {:error, "fail_step must be an integer >= -1, got #{inspect(fail_step)}"}

  # Accept either a bare step array or the {"plan":[...]} envelope that `plan`
  # returns, and normalize to a bare step list — the NIF's tw_replan wants a
  # top-level array and silently yields 0 steps from an envelope (#43). Reject
  # anything else with a structured error instead of silently passing it through.
  # `plan_json` arrives as an already-decoded term (a list or a map) — the
  # transport parsed the JSON, so there's no string here to be malformed.
  defp decode_plan(list) when is_list(list), do: {:ok, list}
  defp decode_plan(%{"plan" => list}) when is_list(list), do: {:ok, list}

  defp decode_plan(other),
    do:
      {:error,
       "plan_json must be an array of step arrays or a {\"plan\": [...]} envelope, got #{inspect(other)}"}

  # Neither `Taskweft.plan/1` nor `plan_explain/1` validate before handing the
  # JSON to the NIF loader — a malformed domain (missing "@type", a legacy
  # "goals"/"tasks" key, a variable missing "type", etc.) surfaces only as the
  # opaque NIF-level "failed_to_load_domain" token, which gives a caller no
  # way to fix their document (confirmed via adversarial testing — repeated
  # real callers hit this and had no actionable signal). Run the same schema
  # validation `validate` uses first, so a shape error reports precisely what
  # is wrong instead of a bare failure string.
  defp plan_with_optional_explain(domain_json, explain) do
    case validate_domain(domain_json) do
      {:error, _reason} = error -> error
      _ok -> do_plan(domain_json, explain)
    end
  end

  defp do_plan(domain_json, false), do: Taskweft.plan(domain_json)

  defp do_plan(domain_json, true) do
    case Taskweft.plan_explain(domain_json) do
      {:ok, result_json} ->
        with {:ok, domain} <- Jason.decode(domain_json),
             {:ok, result} <- Jason.decode(result_json) do
          diagnostics = scan_domain_diagnostics(domain)
          explain = merge_explain_payload(result["explain"], diagnostics, result)
          payload = Map.put(result, "explain", explain)
          {:ok, Jason.encode!(payload)}
        else
          _ -> {:ok, result_json}
        end

      other ->
        other
    end
  end

  defp merge_explain_payload(existing, diagnostics, result) when is_map(existing) do
    existing
    |> Map.put("diagnostics", diagnostics)
    |> Map.put_new_lazy("status", fn -> result["status"] || "ok" end)
  end

  defp merge_explain_payload(_existing, diagnostics, result) do
    status = result["status"] || "ok"

    base = %{
      "mode" => "fallback",
      "status" => status,
      "diagnostics" => diagnostics
    }

    if status == "no_plan" do
      Map.put(base, "summary", "planner returned no_plan")
    else
      Map.put(base, "summary", "plan found")
      |> Map.put("solution_tree", build_solution_tree(result))
    end
  end

  defp build_solution_tree(%{"plan" => plan} = result) when is_list(plan) do
    temporal_steps = get_in(result, ["temporal", "steps"])

    children =
      Enum.with_index(plan)
      |> Enum.map(fn {step, index} ->
        action = List.first(step)
        args = Enum.drop(step, 1)
        temporal = if is_list(temporal_steps), do: Enum.at(temporal_steps, index), else: nil

        %{
          "kind" => "action",
          "index" => index,
          "action" => action,
          "args" => args,
          "temporal" => temporal
        }
      end)

    %{
      "kind" => "root",
      "label" => "plan_execution",
      "children" => children
    }
  end

  defp build_solution_tree(_),
    do: %{"kind" => "root", "label" => "plan_execution", "children" => []}

  defp scan_domain_diagnostics(domain) when is_map(domain) do
    eval_ops = valid_eval_ops()
    actions = Map.get(domain, "actions", %{})
    methods = Map.get(domain, "methods", %{})

    # There is no separate "goals" key — a goal method is an ordinary
    # "methods" entry named after the state var it targets, so it's already
    # covered by methods' keys here.
    symbols =
      Map.keys(actions)
      |> Kernel.++(Map.keys(methods))
      |> MapSet.new()

    unknown_subtasks =
      methods
      |> Enum.flat_map(fn {method_name, method} ->
        method
        |> Map.get("alternatives", [])
        |> Enum.with_index()
        |> Enum.flat_map(fn {alt, alt_idx} ->
          alt
          |> Map.get("subtasks", [])
          |> Enum.with_index()
          |> Enum.flat_map(fn {subtask, sub_idx} ->
            case subtask do
              [name | _] when is_binary(name) ->
                if MapSet.member?(symbols, name) do
                  []
                else
                  [
                    %{
                      "severity" => "error",
                      "type" => "unknown_subtask_symbol",
                      "method" => method_name,
                      "alternative" => alt_idx,
                      "subtask" => sub_idx,
                      "symbol" => name
                    }
                  ]
                end

              _ ->
                []
            end
          end)
        end)
      end)

    check_issues =
      methods
      |> Enum.flat_map(fn {method_name, method} ->
        method
        |> Map.get("alternatives", [])
        |> Enum.with_index()
        |> Enum.flat_map(fn {alt, alt_idx} ->
          alt
          |> Map.get("check", [])
          |> Enum.with_index()
          |> Enum.flat_map(fn {check, check_idx} ->
            cond do
              is_map(check) and Map.has_key?(check, "pointer") ->
                [
                  %{
                    "severity" => "error",
                    "type" => "legacy_check_syntax",
                    "method" => method_name,
                    "alternative" => alt_idx,
                    "check" => check_idx
                  }
                ]

              is_map(check) and is_map(check["eval"]) ->
                eval_type = get_in(check, ["eval", "type"]) || ""

                if eval_type in eval_ops do
                  []
                else
                  [
                    %{
                      "severity" => "error",
                      "type" => "unknown_eval_operator",
                      "method" => method_name,
                      "alternative" => alt_idx,
                      "check" => check_idx,
                      "operator" => eval_type
                    }
                  ]
                end

              true ->
                []
            end
          end)
        end)
      end)

    unknown_subtasks ++ check_issues
  end

  defp scan_domain_diagnostics(_), do: []

  defp valid_eval_ops do
    [
      "math/eq",
      "math/neq",
      "math/lt",
      "math/le",
      "math/gt",
      "math/ge",
      "math/and",
      "math/or",
      "math/not",
      # Capability requirements now compile to this op (taskweft/nif's
      # eval_node, tw_loader.hpp) rather than a bespoke guard mechanism, so
      # it's also directly authorable in an ordinary method/goal-method
      # "check" clause: {"eval": {"type": "rebac/check", "rel": <string-or-
      # relation-expr>, "subject": <expr>, "object": <expr>}}.
      "rebac/check"
    ]
  end

  # Run a planner call, converting any {:error, _} into the MCP error shape and
  # any raised exception / exit / thrown value into a clean {:error, _} result —
  # so a malformed domain returns an MCP `isError` instead of crashing the
  # transport (which surfaced as an opaque HTTP 500 / "Error POSTing to endpoint").
  defp guarded(state, fun) do
    tuple_result(fun.(), state)
  rescue
    e -> {:error, "taskweft: #{Exception.message(e)}", state}
  catch
    kind, reason -> {:error, "taskweft: #{inspect({kind, reason})}", state}
  end

  # Unwrap the {:ok, _} | {:error, _} from Taskweft.plan/3 and replan/3 into the
  # MCP run-handler shape (a plain string becomes text content).
  defp tuple_result({:ok, result}, state) when is_binary(result), do: {:ok, result, state}
  defp tuple_result({:error, reason}, state) when is_binary(reason), do: {:error, reason, state}
  defp tuple_result({:error, reason}, state), do: {:error, inspect(reason), state}

  # `Taskweft.MCP.Plans` embeds every bundled file into the .beam at compile
  # time (see its moduledoc) — no runtime `priv/` resolution, no release-
  # packaging fragility to worry about. `rest` is `"domains/<file>"` or
  # `"problems/<file>"`; the latter also covers `.notes.json` siblings
  # (`work_queue.notes.json` etc.), which aren't planning documents but share
  # the same `taskweft://problems/{file}` template.
  defp read_jsonld("taskweft://" <> rest = uri, state) do
    lookup =
      case String.split(rest, "/", parts: 2) do
        ["domains", file] -> Taskweft.MCP.Plans.domain(file)
        ["problems", file] -> problem_or_notes(file)
        _ -> :error
      end

    case lookup do
      {:ok, content} -> {:ok, %{uri: uri, text: content, mimeType: "application/ld+json"}, state}
      :error -> {:error, "unknown resource: #{uri}", state}
    end
  end

  defp read_jsonld(uri, state), do: {:error, "unknown resource: #{uri}", state}

  defp problem_or_notes(file) do
    with :error <- Taskweft.MCP.Plans.problem(file) do
      Taskweft.MCP.Plans.problem_notes(file)
    end
  end

  # A single user text message — the render-handler shape.
  defp message(text, state) do
    {:ok, %{messages: [%{role: "user", content: %{type: "text", text: text}}]}, state}
  end
end
