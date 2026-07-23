defmodule Taskweft.Domain.Builder do
  @moduledoc """
  An Elixir DSL for defining RECTGTN HTN domains as compile-time code.

  ## Why a DSL

  Eliminates the JSON-LD / YAML-LD parsing layer entirely. The Elixir
  compiler does syntax checking, auto-complete, and code folding. Domains
  compile directly to the RECTGTN internal format, bypassing string parsing.

  ## Usage

      defmodule MyDomain do
        use Taskweft.Domain.Builder

        name "blocks_world"

        variable :pos, type: :ref, init: %{a: "b", b: "table"}
        variable :clear, type: :bool, init: %{a: true, b: false}

        action :a_pickup,
          params: [:block],
          body: [
            condition(:math/eq, pointer_get("/pos/{block}"), "table"),
            condition(:math/eq, pointer_get("/clear/{block}"), true),
            pointer_set("/pos/{block}", "hand"),
            pointer_set("/clear/{block}", false)
          ]

        method :move_one,
          params: [:block, :dest],
          alternatives: [
            alt(:get_and_put, [
              [:get, "{block}"],
              [:put, "{block}", "{dest}"]
            ])
          ]

        capabilities %{
          entities: %{builder: [:build_feature]},
          graph: [%{subject: "builder", rel: "HAS_CAPABILITY", object: "build_feature"}]
        }

        todo_list [[:move_one, :a, :table]]
      end
  """

  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__)

      @domain_name "unnamed_domain"
      @domain_variables []
      @domain_actions %{}
      @domain_methods %{}
      @domain_capabilities nil
      @domain_todo_list []

      @before_compile unquote(__MODULE__)
    end
  end

  @doc "Set the domain name."
  defmacro name(name) do
    quote do
      @domain_name unquote(name)
    end
  end

  @doc """
  Declare a state variable.

  ## Options

    * `type` — one of `:bool`, `:int`, `:float`, `:ref`, `:float3`, etc.
    * `init` — map of entity → initial value

  """
  defmacro variable(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      var = %{
        name: to_string(name),
        type: to_string(opts[:type] || :ref),
        init: opts[:init] || %{}
      }
      @domain_variables [var | @domain_variables]
    end
  end

  @doc """
  Declare a primitive action.

  ## Options

    * `params` — list of parameter atoms
    * `body` — list of body steps (pointer/set or eval)
    * `duration` — ISO 8601 duration string (optional)

  """
  defmacro action(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      params = (opts[:params] || []) |> Enum.map(&to_string/1)
      body = opts[:body] || []

      action_def = %{
        params: params,
        body: body
      }

      action_def =
        if opts[:duration] do
          Map.put(action_def, :duration, to_string(opts[:duration]))
        else
          action_def
        end

      @domain_actions Map.put(@domain_actions, to_string(name), action_def)
    end
  end

  @doc "Helper: create a `pointer/set` body step."
  def pointer_set(pointer, value) do
    %{"pointer/set" => pointer, "value" => value}
  end

  @doc "Helper: create an `eval` body step."
  def condition(type, a, b \\ nil) do
    eval = %{"type" => to_string(type), "a" => a}
    eval = if b != nil, do: Map.put(eval, "b", b), else: eval
    %{"eval" => eval}
  end

  @doc "Helper: create a `pointer/get` expression (for use inside conditions)."
  def pointer_get(pointer) do
    %{"type" => "pointer/get", "pointer" => pointer}
  end

  @doc "Helper: create a rebac/check eval step."
  def rebac_check(subject, rel, object) do
    %{
      "eval" => %{
        "type" => "rebac/check",
        "rel" => rel,
        "subject" => subject,
        "object" => object
      }
    }
  end

  @doc """
  Declare a method with alternatives.

  ## Options

    * `params` — list of parameter atoms
    * `alternatives` — list of alt definitions

  ## Alternative format

  Each alternative is a map returned by `alt/3`:

      alt(:name, check: [...], subtasks: [[...]])

  """
  defmacro method(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      params = (opts[:params] || []) |> Enum.map(&to_string/1)
      alternatives = opts[:alternatives] || []

      method_def = %{
        params: params,
        alternatives: alternatives
      }

      @domain_methods Map.put(@domain_methods, to_string(name), method_def)
    end
  end

  @doc "Declare an alternative for a method."
  def alt(name, check \\ [], subtasks) do
    alt = %{
      "name" => to_string(name),
      "subtasks" => subtasks
    }

    if check != [] do
      Map.put(alt, "check", check)
    else
      alt
    end
  end

  @doc "Declare check conditions for an alternative (list of eval maps)."
  def check_conditions(conditions) when is_list(conditions), do: conditions

  @doc """
  Declare entity capabilities.

  ## Example

      capabilities %{
        entities: %{builder: [:build_feature]},
        graph: [%{subject: "builder", rel: "HAS_CAPABILITY", object: "build_feature"}]
      }

  """
  defmacro capabilities(caps) do
    quote bind_quoted: [caps: caps] do
      entities =
        caps[:entities]
        |> Enum.map(fn {entity, caps_list} ->
          {to_string(entity), caps_list |> Enum.map(&to_string/1)}
        end)
        |> Enum.into(%{})

      graph_edges =
        (caps[:graph] || [])
        |> Enum.map(fn edge ->
          edge
          |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
          |> Enum.into(%{})
        end)

      @domain_capabilities %{
        "entities" => entities,
        "graph" => %{"edges" => graph_edges, "definitions" => %{}}
      }
    end
  end

  @doc "Set the todo list (initial task list)."
  defmacro todo_list(list) do
    quote bind_quoted: [list: list] do
      @domain_todo_list list
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      def __domain_definition__, do: :__domain_defined__
    end
  end

  @doc """
  Compile Elixir DSL source code and return the domain as a JSON string.

  The input should match the DSL pattern above. Returns `{:ok, json_string}`
  on success or `{:error, reason}` on failure.
  """
  def compile_domain(dsl_source) when is_binary(dsl_source) do
    Taskweft.Domain.SafeParser.parse(dsl_source)
  end
end