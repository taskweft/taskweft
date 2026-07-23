# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.DSL do
  @moduledoc """
  Elixir DSL for building RECTGTN HTN domains.

  ## DSL Syntax

  The DSL is an Elixir-like syntax for defining RECTGTN HTN domains:

      name "my_domain"
      variable :pos, type: :ref, init: %{a: "table", b: "hand"}
      variable :clear, type: :bool, init: %{a: true, b: false}
      variable :holding, type: :bool, init: %{hand: false}

      action :pickup,
        params: [:block],
        body: [
          condition(:math/eq, pointer_get("/pos/{block}"), "table"),
          condition(:math/eq, pointer_get("/clear/{block}"), true),
          pointer_set("/pos/{block}", "hand"),
          pointer_set("/clear/{block}", false),
          pointer_set("/holding/hand", "{block}")
        ]

      method :move,
        params: [:block, :dest],
        alternatives: [
          alt(:get_and_put,
            subtasks: [
              [:get, "{block}"],
              [:put, "{block}", "{dest}"]
            ]
          )
        ]

      capabilities %{
        entities: %{drone: [:fly], human: [:walk]},
        graph: [
          %{subject: "alice", rel: "IS_MEMBER_OF", object: "flight_team"},
          %{subject: "flight_team", rel: "HAS_CAPABILITY", object: "fly"}
        ]
      }

      todo_list [
        [:move, :a, :table],
        [:move, :b, :table]
      ]

  ## I/O

  - **Input**: String containing DSL source code
  - **Output**: JSON-LD string (RECTGTN format for the NIF)

  ## Example

      iex> domain = "
      ...>   name \"blocks_world\"
      ...>   variable :pos, type: :ref, init: %{a: \"table\", b: \"table\"}
      ...>   variable :clear, type: :bool, init: %{a: true, b: true}
      ...>   action :a_pickup, params: [:block], body: [...]
      ...>   todo_list [[:a_pickup, :a]]
      ...> "
      iex> Taskweft.DSL.parse(domain)
      {:ok, "{\"@context\":...}"
  """

  alias Taskweft.DSL.SafeParser

  @type parse_result :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Parse a DSL string and return a RECTGTN domain JSON-LD string.

  Returns {:ok, json_string} on success or {:error, reason} on failure.
  """
  @spec parse(String.t()) :: parse_result()
  def parse(dsl_source) when is_binary(dsl_source) do
    SafeParser.parse(dsl_source)
  end
end