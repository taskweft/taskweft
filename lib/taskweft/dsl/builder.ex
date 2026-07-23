# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.DSL.Builder do
  @moduledoc """
  Macro-based Elixir DSL for defining RECTGTN HTN domains.

  Use this in your Elixir modules:

      defmodule MyDomain do
        use Taskweft.DSL.Builder

        name "my_domain"

        variable :pos, type: :ref, init: %{a: "table", b: "hand"}
        variable :clear, type: :bool, init: %{a: true, b: false}

        action :pickup,
          params: [:block],
          body: [
            condition(:math/eq, pointer_get("/pos/{block}"), "table"),
            pointer_set("/pos/{block}", "hand")
          ]

        method :move,
          params: [:block, :dest],
          alternatives: [
            alt(:get_and_put, subtasks: [[:get, "{block}"], [:put, "{block}", "{dest}"]])
          ]

        todo_list [[:move, :a, :table]]

        # Optional capabilities (ReBAC)
        # capabilities %{
        #   entities: %{drone: [:fly], human: [:walk]},
        #   graph: [
        #     %{subject: "alice", rel: "HAS_CAPABILITY", object: "fly"}
        #   ]
        # }
      end

  The module compiles to an Elixir AST, which is then parsed by the
  SafeParser at runtime to produce a RECTGTN JSON-LD domain.
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

  # ========== DSL Macros ==========

  defmacro name(domain_name) do
    quote do
      @domain_name unquote(domain_name)
    end
  end

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

  defmacro alt(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      alt = %{
        name: to_string(name),
        subtasks: opts[:subtasks] || []
      }

      if opts[:check] do
        Map.put(alt, :check, opts[:check])
      else
        alt
      end
    end
  end

  defmacro condition(type, args) do
    quote bind_quoted: [type: type, args: args] do
      condition = %{
        type: to_string(type),
        a: args
      }

      args_len = length(args)
      if args_len > 1 do
        Map.put(condition, :b, Enum.at(args, 1))
      else
        condition
      end
    end
  end

  defmacro pointer_set(path, value) do
    quote bind_quoted: [path: path, value: value] do
      %{"pointer/set" => path, "value" => value}
    end
  end

  defmacro pointer_get(path) do
    quote bind_quoted: [path: path] do
      %{"type" => "pointer/get", "pointer" => path}
    end
  end

  defmacro rebac_check(subject, rel, object) do
    quote bind_quoted: [subject: subject, rel: rel, object: object] do
      %{
        "eval" => %{
          "type" => "rebac/check",
          "rel" => rel,
          "subject" => subject,
          "object" => object
        }
      }
    end
  end

  defmacro todo_list(list) do
    quote bind_quoted: [list: list] do
      @domain_todo_list list
    end
  end

  defmacro capabilities(caps) do
    quote bind_quoted: [caps: caps] do
      entities =
        caps[:entities]
        |> Enum.map(fn {entity, caps_list} ->
          {
            to_string(entity),
            caps_list |> Enum.map(&to_string/1)
          }
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

  # ========== Compilation ==========

  defmacro __before_compile__(_env) do
    quote do
      def __domain_definition__, do: :__domain_defined__

      def domain_name(), do: @domain_name
      def domain_variables(), do: Enum.reverse(@domain_variables)
      def domain_actions(), do: @domain_actions
      def domain_methods(), do: @domain_methods
      def domain_capabilities(), do: @domain_capabilities
      def domain_todo_list(), do: @domain_todo_list
    end
  end

  @doc """
  Compile the DSL and return a RECTGTN domain as a JSON string.

  Returns {:ok, json_string} or {:error, reason}.
  """
  def compile(dsl_source) when is_binary(dsl_source) do
    Taskweft.DSL.SafeParser.parse(dsl_source)
  end
end