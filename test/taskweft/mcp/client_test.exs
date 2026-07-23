# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.MCP.ClientTest do
  use ExUnit.Case, async: true

  alias Taskweft.MCP.Client
  alias ExMCP.Testing.MockServer

  describe "module surface" do
    test "exports the four public functions" do
      Code.ensure_loaded!(Client)
      exports = Client.__info__(:functions)

      for {name, arity} <- [
            {:connect, 1},
            {:connect, 2},
            {:disconnect, 1},
            {:list_tools, 1},
            {:list_tools, 2},
            {:call_tool, 3},
            {:call_tool, 4},
            {:connect_configured, 0}
          ] do
        assert {name, arity} in exports, "expected #{name}/#{arity} to be exported"
      end
    end
  end

  describe "connect_configured/0" do
    setup do
      original = Application.get_env(:taskweft, :mcp_peers)
      on_exit(fn -> restore(:taskweft, :mcp_peers, original) end)
      :ok
    end

    test "with no peer config, returns an empty map" do
      Application.delete_env(:taskweft, :mcp_peers)
      assert Client.connect_configured() == %{}
    end
  end

  describe "MockServer integration" do
    test "list_tools returns tools from a populated mock server" do
      tool = MockServer.sample_tool()

      MockServer.with_server([tools: [tool]], fn client ->
        {:ok, tools} = Client.list_tools(client)
        assert is_list(tools)
        assert length(tools) >= 1
        tool_names = Enum.map(tools, &(&1[:name] || Map.get(&1, "name")))
        assert "sample_tool" in tool_names
      end)
    end

    test "list_tools on an empty server returns an empty list" do
      MockServer.with_server([], fn client ->
        {:ok, tools} = Client.list_tools(client)
        assert tools == []
      end)
    end

    test "call_tool returns content for a registered tool" do
      MockServer.with_server([tools: [MockServer.sample_tool()]], fn client ->
        result = Client.call_tool(client, "sample_tool", %{"input" => "hello"})
        assert match?({:ok, content} when is_list(content), result)
      end)
    end

    test "call_tool on an unknown tool returns an error" do
      MockServer.with_server([], fn client ->
        assert {:error, _reason} = Client.call_tool(client, "nonexistent", %{})
      end)
    end

    test "disconnect stops the client cleanly" do
      MockServer.with_server([], fn client ->
        assert :ok = Client.disconnect(client)
        refute Process.alive?(client)
      end)
    end
  end

  defp restore(_app, _key, nil), do: :ok
  defp restore(app, key, value), do: Application.put_env(app, key, value)
end
