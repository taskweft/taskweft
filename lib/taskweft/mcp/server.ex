defmodule Taskweft.MCP.Server do
  @moduledoc """
  MCP server for Taskweft.

  Start with `mix taskweft.mcp`; speaks stdio MCP.

  ## Tools

  | Tool | Description |
  |------|-------------|
  | `plan` | Run the HTN planner over a JSON-LD domain |
  | `replan` | Recover from a failed plan step |

  `check_temporal` is not exposed; temporal validity is checked on the
  plan output. ReBAC, bridge, and cache NIF entrypoints are not exposed.

  ## Resources

  Every `.jsonld` under `priv/plans/{domains,problems}` is exposed as
  `taskweft://domains/<file>` and `taskweft://problems/<file>`. The
  `defresource` entries are generated at compile time — new JSON-LD files
  require `mix compile` to register.

  ## Calling from DSPy (training time)

  DSPy's MCP integration lets Python optimization loops (GEPA,
  BootstrapFewShot, etc.) call these tools directly:

  ```python
  import dspy

  mcp = dspy.MCP("http://localhost:4000/mcp")  # or stdio transport

  plan_tool     = mcp.tool("plan")
  replan_tool   = mcp.tool("replan")

  class PlanModule(dspy.Module):
      def forward(self, domain_json):
          return plan_tool(domain_json=domain_json)
  ```
  """

  use ExMCP.Server

  # ---------- TOOLS ----------

  deftool "plan" do
    meta do
      description(
        "Run the IPyHOP-style HTN planner over a JSON-LD domain. Returns the plan as JSON."
      )
    end

    input_schema(%{
      type: "object",
      properties: %{
        domain_json: %{
          type: "string",
          description: "Full JSON-LD domain document, including initial state and goals."
        }
      },
      required: ["domain_json"]
    })
  end

  deftool "replan" do
    meta do
      description(
        "Replan after a step failure. Pass the original domain, the previously-returned plan, and the index of the failed step (-1 for full replan)."
      )
    end

    input_schema(%{
      type: "object",
      properties: %{
        domain_json: %{type: "string"},
        plan_json: %{type: "string"},
        fail_step: %{type: "integer", default: -1}
      },
      required: ["domain_json", "plan_json"]
    })
  end

  # ---------- RESOURCES ----------

  @plans_root Path.join(:code.priv_dir(:taskweft_plans) |> to_string(), "plans") |> Path.expand()

  for kind <- ["domains", "problems"] do
    dir = Path.join(@plans_root, kind)

    files =
      case File.ls(dir) do
        {:ok, fs} -> fs |> Enum.filter(&String.ends_with?(&1, ".jsonld")) |> Enum.sort()
        _ -> []
      end

    for file <- files do
      base = Path.rootname(file)
      kind_singular = String.trim_trailing(kind, "s")
      uri = "taskweft://#{kind}/#{file}"
      display_name = "#{kind_singular}: #{base}"
      desc = "JSON-LD HTN #{kind_singular}: #{base}"

      defresource uri do
        meta do
          name(display_name)
          description(desc)
        end

        mime_type("application/ld+json")
      end
    end
  end

  # ---------- PROMPTS ----------

  defprompt "work_queue" do
    meta do
      name("Work queue status")

      description(
        "Stored skill — read taskweft://problems/work_queue.jsonld and report decoded status (phases, pass conditions, scenarios, stack readiness)."
      )
    end
  end

  defprompt "plan_problem" do
    meta do
      name("Plan a problem")
      description("Sample workflow — solve a problem against a domain via the `plan` tool.")
    end

    arguments do
      arg(:domain, required: false, description: "Domain file name, e.g. blocks_world.jsonld")

      arg(:problem,
        required: false,
        description: "Problem file name, e.g. blocks_world_1a.jsonld"
      )
    end
  end

  defprompt "replan_after_failure" do
    meta do
      name("Replan after failure")
      description("Sample workflow — recover from a failed plan step via the `replan` tool.")
    end

    arguments do
      arg(:domain, required: false, description: "Domain file name")
      arg(:fail_step, required: false, description: "Index of the failed step")
    end
  end

  # ---------- HANDLERS ----------

  @impl true
  def handle_tool_call("plan", %{"domain_json" => d}, state) do
    case validate_domain(d) do
      {:ok, normalized} -> tuple_result(Taskweft.plan(normalized), state)
      {:error, reason} -> {:error, reason, state}
    end
  end

  def handle_tool_call("replan", %{"domain_json" => d, "plan_json" => p} = args, state) do
    fail_step = Map.get(args, "fail_step", -1)

    with {:ok, normalized} <- validate_domain(d),
         :ok <- validate_fail_step(p, fail_step) do
      tuple_result(Taskweft.replan(normalized, p, fail_step), state)
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  def handle_tool_call(name, _args, state),
    do: {:error, "unknown tool: #{name}", state}

  # JSON-LD validation lives in the parent app (`Taskweft.JSONLD.Loader`)
  # so this dep stays circular-free. When the umbrella is loaded the Loader
  # is available and validates @type / name; standalone runs skip validation.
  @loader Module.concat(["Taskweft", "JSONLD", "Loader"])

  defp validate_domain(json) do
    if Code.ensure_loaded?(@loader) and function_exported?(@loader, :load_string, 1) do
      apply(@loader, :load_string, [json])
    else
      {:ok, json}
    end
  end

  # `fail_step = -1` means full replan (no completed prefix). Any other
  # value must point at a real index in the plan; otherwise the planner
  # silently treats it as past-the-end success.
  defp validate_fail_step(_plan_json, -1), do: :ok

  defp validate_fail_step(plan_json, fail_step)
       when is_integer(fail_step) and fail_step >= 0 do
    case decode_plan(plan_json) do
      {:ok, plan} when is_list(plan) ->
        if fail_step < length(plan),
          do: :ok,
          else: {:error, "fail_step #{fail_step} out of range for plan of length #{length(plan)}"}

      _ ->
        # malformed plan_json — let the planner / future #43 fix decide
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

  defp text_result(result, state) when is_binary(result),
    do: {:ok, %{content: [text(result)]}, state}

  # Unwrap the {:ok, _} | {:error, _} returned by Taskweft.plan/3 and
  # Taskweft.replan/3 into the MCP handler reply shape.
  defp tuple_result({:ok, result}, state) when is_binary(result),
    do: text_result(result, state)

  defp tuple_result({:error, reason}, state) when is_binary(reason),
    do: {:error, reason, state}

  defp tuple_result({:error, reason}, state),
    do: {:error, inspect(reason), state}

  @impl true
  def handle_resource_read("taskweft://domains/" <> name = uri, _full_uri, state),
    do: read_jsonld(domains_dir(), name, uri, state)

  def handle_resource_read("taskweft://problems/" <> name = uri, _full_uri, state),
    do: read_jsonld(problems_dir(), name, uri, state)

  def handle_resource_read(uri, _full_uri, state),
    do: {:error, "unknown resource: #{uri}", state}

  # Bridge methods that ExMCP.Server.StdioServer does not handle natively.
  # StdioServer only dispatches `initialize`, `tools/list`, `tools/call`, and
  # `resources/list` to its built-in path; for everything else it calls
  # `handle_request/3` on the handler module. The DSL's default `handle_request/3`
  # returns `{:noreply, state}`, which StdioServer interprets as "no response",
  # causing client timeouts. So we re-dispatch to our DSL handlers here.
  @impl true
  def handle_request("resources/read", %{"uri" => uri}, state) do
    case handle_resource_read(uri, uri, state) do
      {:ok, contents, new_state} -> {:reply, %{"contents" => contents}, new_state}
      {:error, reason, new_state} -> {:error, reason, new_state}
    end
  end

  def handle_request("prompts/list", _params, state) do
    prompts =
      get_prompts()
      |> Map.values()
      |> Enum.map(fn p ->
        %{
          "name" => p.name,
          "description" => p.description,
          "arguments" =>
            Enum.map(p.arguments || [], fn a ->
              %{
                "name" => to_string(a[:name]),
                "description" => a[:description],
                "required" => a[:required] || false
              }
            end)
        }
      end)

    {:reply, %{"prompts" => prompts}, state}
  end

  def handle_request("prompts/get", %{"name" => name} = params, state) do
    args = Map.get(params, "arguments", %{})

    case handle_prompt_get(name, args, state) do
      {:ok, result, new_state} -> {:reply, result, new_state}
      {:error, reason, new_state} -> {:error, reason, new_state}
    end
  end

  def handle_request(_method, _params, state), do: {:noreply, state}

  defp read_jsonld(dir, name, uri, state) do
    cond do
      not String.ends_with?(name, ".jsonld") ->
        {:error, "not a .jsonld file: #{name}", state}

      String.contains?(name, "/") or String.contains?(name, "../") or
          String.starts_with?(name, "..") ->
        {:error, "illegal name: #{name}", state}

      true ->
        path = Path.join(dir, name)

        if File.regular?(path) do
          content = %{uri: uri, mimeType: "application/ld+json", text: File.read!(path)}
          {:ok, [content], state}
        else
          {:error, "not found: #{name}", state}
        end
    end
  end

  @impl true
  def handle_prompt_get("work_queue", _args, state) do
    {:ok, %{messages: [user(prompt_work_queue())]}, state}
  end

  def handle_prompt_get("plan_problem", args, state) do
    domain = Map.get(args, "domain", "<domain>.jsonld")
    problem = Map.get(args, "problem", "<problem>.jsonld")

    text = """
    Solve problem `#{problem}` against domain `#{domain}`.

    1. Read resource `taskweft://domains/#{domain}` for the domain JSON.
    2. Read resource `taskweft://problems/#{problem}` for the problem JSON.
    3. Merge into a single domain document:
       - Override `variables` with the problem's `variables` (initial state).
       - Override `tasks` with the problem's `tasks` (top-level goals).
       - If the problem defines `methods`, merge them into the domain's `methods`
         (the problem's entries win on key collisions). Some problems —
         e.g. `blocks_world_3` — override the recursive `move_blocks` method
         with their own `scan` definition; missing this merge yields `no_plan`.
    4. Call the `plan` tool with the merged `domain_json`.
    5. Report the returned plan, one action per line.
    """

    {:ok, %{messages: [user(text)]}, state}
  end

  def handle_prompt_get("replan_after_failure", args, state) do
    domain = Map.get(args, "domain", "<domain>.jsonld")
    fail_step = Map.get(args, "fail_step", "<index>")

    text = """
    A plan step failed. Replan from that step.

    1. Read resource `taskweft://domains/#{domain}`.
    2. Reuse the previously-returned `plan_json`.
    3. Call `replan` with `fail_step=#{fail_step}`.
    4. Report the new plan and what changed relative to the original.
    """

    {:ok, %{messages: [user(text)]}, state}
  end

  def handle_prompt_get(name, _args, state),
    do: {:error, "unknown prompt: #{name}", state}

  # ---------- INTERNAL ----------

  defp domains_dir, do: Path.join([priv_plans(), "domains"])
  defp problems_dir, do: Path.join([priv_plans(), "problems"])
  defp priv_plans, do: Path.join(:code.priv_dir(:taskweft_plans) |> to_string(), "plans")

  defp prompt_work_queue do
    """
    # Work queue

    The work queue lives at `taskweft://problems/work_queue.jsonld` — a JSON-LD HTN problem document (uses the generic `service_bringup` domain). It is the source of truth for project status; do not infer status from `git log` or open PRs.

    ## What to do

    1. Read the resource `taskweft://problems/work_queue.jsonld`.
    2. Read the four `variables[]` entries: `phase`, `pass_condition`, `scenario`, `stack_ready`. Each has an `init` map of `name → integer`.
    3. Decode integers using the `enums` block at the top of the file:
       - `phase`: `0=unstarted, 1=stub, 2=green, 3=done`
       - `status` (used by `pass_condition`, `scenario`, `stack_ready`): `0=unmet/unverified/not-ready, 1=met/verified/ready`
       - `approach`: `0=direct, 1=prototype_first`
    4. Report by section, in this order, terse:
       - **In flight** — `phase` items where value is `1` (stub) or `2` (green). One line each: `name — stub|green`.
       - **Unstarted** — `phase` items at `0`. One line each: `name`. If the list is long, group by dev track using the `methods` field (each `*_dev_track` lists its subtasks).
       - **Done** — count only, do not list.
       - **Pass conditions** — items where `pass_condition` is `0` (unmet). One line each.
       - **Scenarios** — `concert/chokepoint/convoy/ragdoll`, mark `0` as unverified.
       - **Stack readiness** — components where `stack_ready` is `0`.
    5. End with the `win_condition` field verbatim — one line.

    ## What not to do

    - Do not edit the file. This skill is read-only.
    - Do not infer or invent items not present in the variables. If the user asks about an item that isn't there, say so.
    - Do not summarise the `actions` or `methods` blocks unless asked. They describe how items advance, not their current state.
    - Do not translate phases into prose ("almost done", "blocked"). Report the integer-decoded label only.

    ## When the user asks for one item

    If the user asks `what's the status of <item>`, show:

    ```
    <item>: phase=<label> ( approach=<label> if present )
    gating method: <method-name from methods[] whose name is complete_<item> >
    ```

    Then list the method's `alternatives[].subtasks` so they can see what unblocks it.
    """
  end
end
