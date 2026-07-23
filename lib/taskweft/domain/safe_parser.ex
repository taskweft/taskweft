# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.Domain.SafeParser do
  @moduledoc """
  Safe JSON-LD parsing with fallback behavior.
  """

  @doc """
  Parse JSON-LD string into struct or map.

  Tries to parse as a RECTGTN domain struct first. If that fails,
  returns the raw map. Supports both direct JSON-LD and Elixir DSL input.
  """
  def parse(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, decoded} -> parse(decoded)
      {:error, _reason} -> {:error, "invalid json"}
    end
  end

  def parse(map) when is_map(map) do
    case map["@type"] do
      "domain:Definition" -> {:ok, Map.new(map)}
      _ -> {:ok, map}
    end
  rescue
    _ -> {:error, "invalid domain structure"}
  end
end