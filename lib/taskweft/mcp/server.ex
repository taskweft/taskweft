defmodule Taskweft.MCP.Server do
  @moduledoc """
  MCP server for Taskweft.

  Start with `mix taskweft.mcp` (stdio) or `mix taskweft.mcp --http`.

  ## Tools

  | Tool | Description |
  |------|-------------|
  | `plan` | Run the HTN planner over a JSON-LD domain |
  | `replan` | Recover from a failed plan step |

  `check_temporal` is not exposed; temporal validity is checked on the plan
  output. ReBAC, bridge, and cache NIF entrypoints are not exposed.

  ## Resources

  Every `.jsonld` under `priv/plans/{domains,problems}` is exposed as
  `taskweft://domains/<file>` and `taskweft://problems/<file>`; new files require
  `mix compile` to register.
  """

  use ExMCP.Server.Handler
  use ExMCP.Server.DSL, name: "taskweft", version: "0.1.0"

  @plans_root Path.join(:code.priv_dir(:taskweft_plans) |> to_string(), "plans") |> Path.expand()

  # JSON-LD validation lives in the parent app (`Taskweft.JSONLD.Loader`) so this
  # dep stays circular-free; standalone runs skip validation.
  @loader Module.concat(["Taskweft", "JSONLD", "Loader"])

  # ---------- TOOLS ----------

  tool "plan", "Run the IPyHOP-style HTN planner over a JSON-LD domain. Returns the plan as JSON." do
    param(:domain_json, :string,
      required: true,
      description: """
      A JSON-LD HTN domain (pointer-based IPyHOP). Shape:
        "@context": {"vsekai": "https://v-sekai.org/", "domain": "vsekai:planning/domain/"}
        "@type": "domain:Definition", "name": <string>
        "variables": [{"name": <v>, "init": {<key>: <value>, ...}}]   # state; NOT a flat "state" object
        "actions": {<name>: {"params": [<p>...],
                             "body": [{"pointer/set": "/path/{p}", "value": <v>}]}}   # effects; NOT pre/eff
        "methods": {<name>: {"params": [<p>...],
                             "alternatives": [{"name": <alt>,
                                               "check": [{"pointer": "/path", "eq": <v>}],   # optional guard
                                               "subtasks": [[<call>, <arg>...], ...]}]}}
        "tasks": [[<call>, <arg>...], ...]   # call-arrays, NOT bare strings
      Effects use "pointer/set" (the legacy "set" op is rejected). {curly} names in
      paths/values are substituted from action/method params. Minimal example:
        {"@context":{"vsekai":"https://v-sekai.org/","domain":"vsekai:planning/domain/"},
         "@type":"domain:Definition","name":"demo",
         "variables":[{"name":"done","init":{"a":false,"b":false}}],
         "actions":{"do_a":{"params":[],"body":[{"pointer/set":"/done/a","value":true}]},
                    "do_b":{"params":[],"body":[{"pointer/set":"/done/b","value":true}]}},
         "methods":{"top":{"params":[],"alternatives":[{"name":"seq","subtasks":[["do_a"],["do_b"]]}]}},
         "tasks":[["top"]]}
      """
    )

    run(fn %{domain_json: domain_json}, state ->
      guarded(state, fn ->
        with {:ok, normalized} <- validate_domain(domain_json) do
          Taskweft.plan(normalized)
        end
      end)
    end)
  end

  tool "replan",
       "Replan after a step failure. Pass the original domain, the previously-returned plan, and the index of the failed step (-1 for full replan)." do
    param(:domain_json, :string, required: true)
    param(:plan_json, :string, required: true)

    param(:fail_step, :integer,
      required: false,
      description: "Index of the failed step; -1 for a full replan."
    )

    run(fn %{domain_json: domain_json, plan_json: plan_json} = args, state ->
      fail_step = Map.get(args, :fail_step, -1)

      guarded(state, fn ->
        with {:ok, normalized} <- validate_domain(domain_json),
             :ok <- validate_fail_step(plan_json, fail_step) do
          Taskweft.replan(normalized, plan_json, fail_step)
        end
      end)
    end)
  end

  # ---------- RESOURCES ----------
  # Every bundled `.jsonld` under priv/plans/{domains,problems} is readable. 1.0's
  # `resource` needs a literal URI, so the per-file set is exposed as two templates.

  resource_template "taskweft://domains/{file}", "JSON-LD HTN domain" do
    title("HTN domain")
    mime_type("application/ld+json")
    param(:file, :string)

    read(fn %{file: file}, state -> read_jsonld("taskweft://domains/#{file}", state) end)
  end

  resource_template "taskweft://problems/{file}", "JSON-LD HTN problem" do
    title("HTN problem")
    mime_type("application/ld+json")
    param(:file, :string)

    read(fn %{file: file}, state -> read_jsonld("taskweft://problems/#{file}", state) end)
  end

  # ---------- PROMPTS ----------

  prompt "work_queue",
         "Stored skill — read taskweft://problems/work_queue.jsonld and report decoded status." do
    title("Work queue status")

    render(fn _args, state ->
      message(
        "Read the resource taskweft://problems/work_queue.jsonld and report the decoded status: phases, pass conditions, scenarios, and stack readiness.",
        state
      )
    end)
  end

  prompt "plan_problem", "Sample workflow — solve a problem against a domain via the `plan` tool." do
    title("Plan a problem")
    arg(:domain, required: false, description: "Domain file name, e.g. blocks_world.jsonld")
    arg(:problem, required: false, description: "Problem file name, e.g. blocks_world_1a.jsonld")

    render(fn args, state ->
      domain = args[:domain] || "<domain>.jsonld"
      problem = args[:problem] || "<problem>.jsonld"

      message(
        "Read taskweft://domains/#{domain} and taskweft://problems/#{problem}, then call the `plan` tool with the combined JSON-LD domain.",
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

  defp validate_domain(json) do
    if Code.ensure_loaded?(@loader) and function_exported?(@loader, :load_string, 1) do
      apply(@loader, :load_string, [json])
    else
      {:ok, json}
    end
  end

  # `fail_step = -1` means full replan (no completed prefix). Any other value must
  # point at a real index in the plan; otherwise the planner silently treats it as
  # past-the-end success.
  defp validate_fail_step(_plan_json, -1), do: :ok

  defp validate_fail_step(plan_json, fail_step) when is_integer(fail_step) and fail_step >= 0 do
    case decode_plan(plan_json) do
      {:ok, plan} when is_list(plan) ->
        if fail_step < length(plan),
          do: :ok,
          else: {:error, "fail_step #{fail_step} out of range for plan of length #{length(plan)}"}

      _ ->
        # malformed plan_json — let the planner decide
        :ok
    end
  end

  defp validate_fail_step(_plan_json, fail_step),
    do: {:error, "fail_step must be an integer >= -1, got #{inspect(fail_step)}"}

  defp decode_plan(plan_json) when is_binary(plan_json) do
    case Jason.decode(plan_json) do
      {:ok, list} when is_list(list) -> {:ok, list}
      {:ok, %{"plan" => list}} when is_list(list) -> {:ok, list}
      _ -> :error
    end
  end

  defp decode_plan(_), do: :error

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

  defp read_jsonld("taskweft://" <> rest = uri, state) do
    case File.read(Path.join(@plans_root, rest)) do
      {:ok, content} -> {:ok, %{uri: uri, text: content, mimeType: "application/ld+json"}, state}
      {:error, _} -> {:error, "unknown resource: #{uri}", state}
    end
  end

  defp read_jsonld(uri, state), do: {:error, "unknown resource: #{uri}", state}

  # A single user text message — the render-handler shape.
  defp message(text, state) do
    {:ok, %{messages: [%{role: "user", content: %{type: "text", text: text}}]}, state}
  end
end
