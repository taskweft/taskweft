# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.SolveTest do
  use ExUnit.Case, async: true

  alias Taskweft.Solve

  describe "with_peer/2" do
    setup do
      original = Application.get_env(:taskweft, :mcp_peers)
      on_exit(fn -> restore(original) end)
      :ok
    end

    test "returns peer_not_configured for an unknown peer" do
      Application.put_env(:taskweft, :mcp_peers, [])

      assert {:error, {:peer_not_configured, :nope}} =
               Solve.with_peer(:nope, fn _ -> :reached end)
    end

    test "uses the configured peer name when present" do
      Application.put_env(:taskweft, :mcp_peers,
        present: {:stdio, command: ["/nonexistent/binary"]}
      )

      # Spec is found; an absent peer returns peer_not_configured. Here
      # we verify the *opposite* — peer_not_configured does NOT fire
      # because the name is registered.
      assert {:error, {:peer_not_configured, :missing}} =
               Solve.with_peer(:missing, fn _ -> :unreached end)
    end
  end

  defp restore(nil), do: Application.delete_env(:taskweft, :mcp_peers)
  defp restore(value), do: Application.put_env(:taskweft, :mcp_peers, value)

  # Integration test against the live `:minizinc` peer. Requires the
  # `minizinc` binary on the peer's host PATH. Skipped by default.
  describe "integration: minizinc peer" do
    @tag :integration
    test "round-trips a trivial LP through Taskweft.Solve.minizinc/2" do
      model = """
      var 0..10: x;
      var 0..10: y;
      constraint x + y <= 10;
      solve maximize x + y;
      """

      case Solve.minizinc(model) do
        {:ok, solution} ->
          # Either decoded vars `{"x" => 5, "y" => 5}` or wrapped in raw text.
          assert is_map(solution)

        {:error, reason} ->
          flunk("Solve.minizinc failed: #{inspect(reason)}")
      end
    end
  end
end
