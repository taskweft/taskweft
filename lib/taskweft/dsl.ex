# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.DSL do
  @moduledoc """
  Elixir DSL for building RECTGTN HTN domains using real Elixir code.

  ## Usage

      defmodule BlocksWorld do
        use Taskweft.DSL

        @name "blocks_world"

        @variables %{
          pos: %{type: :ref, init: %{a: "table", b: "hand"}},
          clear: %{type: :bool, init: %{a: true, b: false}}
        }

        @actions %{
          pickup: %{
            params: [:block],
            body: [%{pointer_set: "/pos/{block}", value: "hand"}]
          }
        }

        @todo_list [
          [:move, :a, :table],
          [:move, :b, :table]
        ]
      end

  ## I/O

  - **Input**: Real Elixir module code with module attributes
  - **Output**: RECTGTN JSON-LD string

  ## Example

      iex> domain = \"\"\n      ...>       defmodule MyDomain do\n      ...>         use Taskweft.DSL\n      ...>         @name \"my_domain\"\n      ...>         @todo_list [[:test, :a]]\n      ...>       end\n      ...> \"\"\n      iex> Taskweft.DSL.compile(domain)\n      {:ok, \"{\\\"@context\\\":...}\"
  """

  @type compile_result :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Compile an Elixir module that uses `use Taskweft.DSL` and return a RECTGTN domain JSON-LD string.

  Returns {:ok, json_string} or {:error, reason} on failure.
  """
  @spec compile(String.t()) :: compile_result()
  def compile(dsl_source) when is_binary(dsl_source) do
    case Code.string_to_quoted(dsl_source) do
      {:ok, ast} ->
        Taskweft.DSL.SafeParser.parse(ast)

      {:error, {_line, error, _token}} ->
        {:error, "DSL syntax error: #{error}"}
    end
  end
end
