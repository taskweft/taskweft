# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.DSL.SafeParser do
  @moduledoc """
  Safe AST parser for the Elixir DSL.

  Walks an Elixir AST without compiling or executing code. Uses strict
  pattern matching to reject any unrecognized constructs (sandbox escape).

  ## Example

      SafeParser.parse('''
        name "blocks_world"
        variable :pos, type: :ref, init: %{a: "table"}
        action :pickup, params: [:block], body: [...]
      ''')
      # => {:ok, json_string}
  """

  @type parse_result :: {:ok, String.t()} | {:error, String.t()}

  @initial_domain %{
    "@context" => %{
      "vsekai" => "https://v-sekai.org/",
      "domain" => "vsekai:planning/domain/"
    },
    "@type" => "domain:Definition",
    "name" => nil,
    "variables" => [],
    "actions" => %{},
    "methods" => %{},
    "todo_list" => []
  }

  @doc """
  Parse an Elixir DSL string into a RECTGTN domain JSON map.

  Returns {:ok, json_string} or {:error, reason}.
  """
  @spec parse(String.t()) :: parse_result()
  def parse(dsl_source) when is_binary(dsl_source) do
    case Code.string_to_quoted(dsl_source,
           columns: true,
           literal_encoder: fn
             {:sigil, _, _}, _meta -> {:ok, {:sigil, :__block__, []}}
             other, _meta -> {:ok, other}
           end
         ) do
      {:ok, {:__block__, _, expressions}} ->
        try do
          domain = Enum.reduce(expressions, initial_domain(), &reduce_ast/2)
          {:ok, Jason.encode!(finalize(domain))}
        catch
          {:invalid, reason} -> {:error, "RECTGTN compliance error: #{reason}"}
        end

      {:ok, single} ->
        try do
          domain = reduce_ast(single, initial_domain())
          {:ok, Jason.encode!(finalize(domain))}
        catch
          {:invalid, reason} -> {:error, "RECTGTN compliance error: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Syntax error: #{inspect(reason)}"}
    end
  end

  # ========== AST Reduction ==========

  defp initial_domain, do: @initial_domain

  defp reduce_ast({:name, _, [name]}, domain) when is_binary(name) do
    Map.put(domain, "name", name)
  end

  defp reduce_ast({:variable, _, [name, opts]}, domain) do
    with {:ok, var} <- parse_variable(name, opts) do
      Map.update!(domain, "variables", fn vars -> [var | vars] end)
    end
  end

  defp reduce_ast({:action, _, [name, opts]}, domain) do
    with {:ok, act} <- parse_action(name, opts) do
      Map.update!(domain, "actions", fn acts -> Map.put(acts, to_string(name), act) end)
    end
  end

  defp reduce_ast({:method, _, [name, opts]}, domain) do
    with {:ok, meth} <- parse_method(name, opts) do
      Map.update!(domain, "methods", fn meths -> Map.put(mechs, to_string(name), meth) end)
    end
  end

  defp reduce_ast({:alt, _, [name, opts]}, domain) do
    with {:ok, alt} <- parse_alternative(name, opts) do
      Map.update!(domain, "methods", fn meths ->
        meths
        |> Enum.map(fn {meth_name, meth} ->
          {meth_name, update_in(meth["alternatives"], fn alts -> [alt | alts] end)}
        end)
      end)
    end
  end

  defp reduce_ast({:condition, _, [type, args]}, domain) do
    cond =
      case args do
        [expr] -> %{"type" => to_string(type), "a" => parse_expr(expr)}
        [expr1, expr2] -> %{"type" => to_string(type), "a" => parse_expr(expr1), "b" => parse_expr(expr2)}
      end

    Map.update!(domain, "actions", fn acts ->
      # Add condition to the last action's body (simple approach)
      acts =
        acts
        |> Enum.map(fn {name, act} ->
          {name, update_in(act["body"], fn body -> [cond | body] end)}
        end)

      acts
    end)
  end

  defp reduce_ast({:pointer_set, _, [path, value]}, domain) do
    step = %{"pointer/set" => to_string(path), "value" => to_string(value)}
    Map.update!(domain, "actions", fn acts ->
      acts
      |> Enum.map(fn {name, act} ->
        {name, update_in(act["body"], fn body -> [step | body] end)}
      end)
    end)
  end

  defp reduce_ast({:pointer_get, _, [path]}, domain) do
    step = %{"type" => "pointer/get", "pointer" => to_string(path)}
    Map.update!(domain, "actions", fn acts ->
      acts
      |> Enum.map(fn {name, act} ->
        {name, update_in(act["body"], fn body -> [step | body] end)}
      end)
    end)
  end

  defp reduce_ast({:rebac_check, _, [subject, rel, object]}, domain) do
    step = %{
      "eval" => %{
        "type" => "rebac/check",
        "rel" => to_string(rel),
        "subject" => to_string(subject),
        "object" => to_string(object)
      }
    }
    Map.update!(domain, "actions", fn acts ->
      acts
      |> Enum.map(fn {name, act} ->
        {name, update_in(act["body"], fn body -> [step | body] end)}
      end)
    end)
  end

  defp reduce_ast({:todo_list, _, [list]}, domain) do
    Map.put(domain, "todo_list", parse_todo_list(list))
  end

  defp reduce_ast({:capabilities, _, [caps]}, domain) do
    entities =
      caps["entities"]
      |> Enum.map(fn {entity, caps_list} ->
        {to_string(entity), Enum.map(caps_list || [], &to_string/1)}
      end)
      |> Enum.into(%{})

    edges =
      (caps["graph"]["edges"] || [])
      |> Enum.map(fn edge ->
        edge
        |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
        |> Enum.into(%{})
      end)

    capabilities = %{
      "entities" => entities,
      "graph" => %{"edges" => edges, "definitions" => %{}}
    }

    Map.put(domain, "capabilities", capabilities)
  end

  defp reduce_ast({:__block__, _, expressions}, domain) do
    Enum.reduce(expressions, domain, &reduce_ast/2)
  end

  defp reduce_ast(_other, domain) do
    throw({:invalid, "unrecognized DSL construct: #{inspect(_other)}"})
  end

  # ========== Parsing Helpers ==========

  defp parse_variable(name, opts) do
    var_name = to_string(name)
    var_type = to_string(opts[:type] || :ref)
    init = parse_init(opts[:init] || %{})

    {:ok, %{"name" => var_name, "type" => var_type, "init" => init}}
  end

  defp parse_init(init) when is_map(init) do
    Enum.into(init, %{}, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp parse_action(name, opts) do
    params = (opts[:params] || []) |> Enum.map(&to_string/1)
    body = (opts[:body] || []) |> Enum.map(&parse_body_step/1)

    action_def = %{
      "params" => params,
      "body" => body
    }

    action_def =
      if opts[:duration] do
        Map.put(action_def, :duration, to_string(opts[:duration]))
      else
        action_def
      end

    {:ok, action_def}
  end

  defp parse_method(name, opts) do
    params = (opts[:params] || []) |> Enum.map(&to_string/1)
    alternatives = (opts[:alternatives] || []) |> Enum.map(&parse_alternative/1)

    method_def = %{
      "params" => params,
      "alternatives" => alternatives
    }

    {:ok, method_def}
  end

  defp parse_alternative(name, opts) do
    %{
      "name" => to_string(name),
      "subtasks" => opts[:subtasks] || [],
      "check" => (opts[:check] || []) |> Enum.map(&parse_guard/1)
    }
  end

  defp parse_guard({:condition, _, [type, args]}) do
    cond =
      case args do
        [expr] -> %{"type" => to_string(type), "a" => parse_expr(expr)}
        [expr1, expr2] -> %{"type" => to_string(type), "a" => parse_expr(expr1), "b" => parse_expr(expr2)}
      end

    cond
  end

  defp parse_guard(other), do: throw({:invalid, "invalid guard: #{inspect(other)}"})

  defp parse_body_step(%{"pointer/set" => path, "value" => value}), do: %{"pointer/set" => path, "value" => value}
  defp parse_body_step(%{"type" => type, "eval" => eval}), do: %{"eval" => parse_eval(eval)}
  defp parse_body_step(other), do: other

  defp parse_eval(%{"type" => "pointer/get", "pointer" => path}), do: %{"type" => "pointer/get", "pointer" => path}
  defp parse_eval(%{"type" => "rebac/check", "rel" => rel, "subject" => subject, "object" => object}), do: %{"type" => "rebac/check", "rel" => rel, "subject" => subject, "object" => object}
  defp parse_eval(eval), do: eval

  defp parse_todo_list(list) when is_list(list) do
    Enum.map(list, fn item ->
      case item do
        [call, args...] when is_binary(call) ->
          [call | Enum.map(args, &to_string/1)]

        %{goal: goals} when is_list(goals) ->
          %{"goal" => Enum.map(goals, &parse_goal/1)}

        %{multigoal: mg} when is_map(mg) ->
          %{"multigoal" => mg}

        other ->
          other
      end
    end)
  end

  defp parse_todo_list(other), do: other

  defp parse_goal(%{"pointer" => pointer, "eq" => value}), do: %{"pointer" => pointer, "eq" => value}
  defp parse_goal(goal), do: goal

  defp parse_expr(atom) when is_atom(atom), do: to_string(atom)
  defp parse_expr(str) when is_binary(str), do: str
  defp parse_expr(num) when is_integer(num), do: to_string(num)
  defp parse_expr(num) when is_float(num), do: to_string(num)
  defp parse_expr(%{"type" => "pointer/get", "pointer" => path}), do: %{"type" => "pointer/get", "pointer" => path}
  defp parse_expr(_other), do: throw({:invalid, "invalid expression: #{inspect(_other)}"})

  # ========== Finalizer ==========

  defp finalize(domain) do
    domain
    |> Map.delete("capabilities")
    |> then(fn d ->
      if Map.has_key?(domain, "capabilities") do
        Map.put(d, "capabilities", domain["capabilities"])
      else
        d
      end
    end)
  end
end