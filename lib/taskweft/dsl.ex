# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.DSL do
  @moduledoc """
  Elixir DSL for building RECTGTN HTN domains.
  """

  use TypedStruct

  typedstruct do
    field :name, String.t()
    field :variables, [__MODULE__.Variable]
    field :actions, %{String.t() => __MODULE__.Action}
    field :methods, %{String.t() => __MODULE__.Method}
    field :todo_list, [[String.t()]]
    field :capabilities, %{String.t() => [String.t()]}
  end

  def compile(%__MODULE__{} = domain) do
    json = Jason.encode!(build_json_domain(domain))
    {:ok, json}
  end

  defp build_json_domain(%__MODULE__{
         name: name,
         variables: variables,
         actions: actions,
         methods: methods,
         todo_list: todo_list,
         capabilities: capabilities
       }) do
    %{
      "@context" => %{
        "vsekai" => "https://v-sekai.org/",
        "domain" => "vsekai:planning/domain/"
      },
      "@type" => "domain:Definition",
      "name" => name,
      "variables" => Enum.map(variables, &build_variable/1),
      "actions" => build_actions(actions),
      "methods" => build_methods(methods),
      "todo_list" => todo_list,
      "capabilities" => build_capabilities(capabilities)
    }
  end

  defp build_variable(%DSL.Variable{name: name, type: type, init: init}) when is_binary(init) do
    %{name: name, type: type, init: init}
  end

  defp build_variable(%DSL.Variable{name: name, type: type, init: init}) when is_map(init) do
    %{name: name, type: type, init: init}
  end

  defp build_actions(actions) when is_map(actions) do
    Enum.into(actions, %{}, fn {name, action} ->
      {name, %{
        "params" => action.params,
        "body" => Enum.map(action.body, &build_action_body/1)
      }}
    end)
  end

  defp build_methods(methods) when is_map(methods) do
    Enum.into(methods, %{}, fn {name, method} ->
      {name, %{
        "params" => method.params,
        "alternatives" => Enum.map(method.alternatives, &build_alternative/1)
      }}
    end)
  end

  defp build_alternative(%DSL.Alternative{
         name: name,
         check: check,
         subtasks: subtasks
       }) do
    %{
      "name" => name,
      "check" => Enum.map(check, &build_eval/1),
      "subtasks" => subtasks
    }
  end

  defp build_action_body(%DSL.Eval{type: type, a: a, b: b}) do
    %{
      "type" => type,
      "a" => a,
      "b" => b
    }
  end

  defp build_action_body(%DSL.PointerSet{pointer: pointer, value: value}) do
    %{
      "type" => "pointer/set",
      "pointer" => pointer,
      "value" => value
    }
  end

  defp build_eval(%DSL.Eval{type: type, a: a, b: b}), do: %{"type" => type, "a" => a, "b" => b}

  defp build_capabilities(capabilities) when is_map(capabilities) do
    Enum.reduce(capabilities, %{}, fn {entity, caps}, acc ->
      Map.update(acc, entity, [caps], fn current, _key, new ->
        [new | current]
      end)
    end)
  end
end

defmodule DSL.Variable do
  use TypedStruct

  typedstruct do
    field :name, String.t()
    field :type, String.t()
    field :init, term()
  end
end

defmodule DSL.Action do
  use TypedStruct

  typedstruct do
    field :params, [String.t()]
    field :body, [__MODULE__.BodyStep]
  end
end

defmodule DSL.Action.BodyStep do
  use TypedStruct

  typedstruct do
    field :type, String.t()
    field :a, term()
    field :b, term()
  end
end

defmodule DSL.Method do
  use TypedStruct

  typedstruct do
    field :params, [String.t()]
    field :alternatives, [__MODULE__.Alternative]
  end
end

defmodule DSL.Method.Alternative do
  use TypedStruct

  typedstruct do
    field :name, String.t()
    field :check, [__MODULE__.Eval]
    field :subtasks, [[String.t()]]
  end
end

defmodule DSL.Alternative do
  use TypedStruct

  typedstruct do
    field :name, String.t()
    field :check, [__MODULE__.Eval]
    field :subtasks, [[String.t()]]
  end
end

defmodule DSL.Eval do
  use TypedStruct

  typedstruct do
    field :type, String.t()
    field :a, term()
    field :b, term()
  end
end

defmodule DSL.PointerSet do
  use TypedStruct

  typedstruct do
    field :pointer, String.t()
    field :value, term()
  end
end