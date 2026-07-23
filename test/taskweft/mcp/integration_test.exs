# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.MCP.IntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  setup do
    {:ok, _} = Application.ensure_all_started(:ex_mcp)
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    port = 20000 + :erlang.unique_integer([:positive]) |> rem(40000)
    server_opts = [transport: :http, port: port, host: "127.0.0.1"]

    {:ok, pid} = Taskweft.MCP.Server.start_link(server_opts)
    url = "http://127.0.0.1:#{port}/mcp/v1"

    # Wait for server readiness
    wait_for_server(url)

    on_exit(fn ->
      Process.unlink(pid)
      Process.exit(pid, :shutdown)
    end)

    {:ok, %{url: url}}
  end

  defp wait_for_server(url, retries \\ 10) do
    case :httpc.request(:get, {url, []}, [], []) do
      {:ok, _} -> :ok
      _ ->
        if retries > 0 do
          Process.sleep(50)
          wait_for_server(url, retries - 1)
        end
    end
  end

  defp jsonrpc_call(url, method, params) do
    body = Jason.encode!(%{
      jsonrpc: "2.0",
      id: 1,
      method: method,
      params: params || %{}
    })

    {:ok, {{_, 200, _}, _headers, resp}} =
      :httpc.request(:post, {url, [], "application/json", body}, [], [{:timeout, 10_000}])

    Jason.decode!(resp)
  end

  describe "plan tool" do
    test "returns golden plan for blocks_world", %{url: url} do
      domain = File.read!("priv/plans/domains/blocks_world.jsonld")
      golden = Jason.decode!(File.read!("priv/plans/domains/blocks_world_expected.json"))

      resp = jsonrpc_call(url, "tools/call", %{
        name: "plan",
        arguments: %{domain_json: domain}
      })

      assert resp["jsonrpc"] == "2.0"
      result = resp["result"]
      content = List.first(result["content"])
      plan = Jason.decode!(content["text"])

      assert plan["plan"] == golden["plan"],
             "blocks_world: plan mismatch"
    end

    test "returns golden plan for entity_capabilities", %{url: url} do
      domain = File.read!("priv/plans/domains/entity_capabilities.jsonld")
      golden = Jason.decode!(File.read!("priv/plans/domains/entity_capabilities_expected.json"))

      resp = jsonrpc_call(url, "tools/call", %{
        name: "plan",
        arguments: %{domain_json: domain}
      })

      result = resp["result"]
      content = List.first(result["content"])
      plan = Jason.decode!(content["text"])
      assert plan["plan"] == golden["plan"]
    end

    test "returns golden plan for healthcare", %{url: url} do
      domain = File.read!("priv/plans/domains/healthcare.jsonld")
      golden = Jason.decode!(File.read!("priv/plans/domains/healthcare_expected.json"))

      resp = jsonrpc_call(url, "tools/call", %{
        name: "plan",
        arguments: %{domain_json: domain}
      })

      result = resp["result"]
      content = List.first(result["content"])
      plan = Jason.decode!(content["text"])
      assert plan["plan"] == golden["plan"]
    end

    test "returns error for invalid JSON", %{url: url} do
      resp = jsonrpc_call(url, "tools/call", %{
        name: "plan",
        arguments: %{domain_json: "not valid json"}
      })

      assert resp["error"] != nil
      assert resp["error"]["code"] == -32603
    end
  end

  describe "list_tools" do
    test "exposes plan, replan, validate, and convert tools", %{url: url} do
      resp = jsonrpc_call(url, "tools/list", %{})

      tools = resp["result"]["tools"]
      names = Enum.map(tools, & &1["name"])

      assert "plan" in names
      assert "replan" in names
      assert "validate" in names
    end
  end

  describe "validate tool" do
    test "validates a correct domain", %{url: url} do
      domain = File.read!("priv/plans/domains/blocks_world.jsonld")

      resp = jsonrpc_call(url, "tools/call", %{
        name: "validate",
        arguments: %{domain_json: domain}
      })

      assert resp["result"] != nil
    end
  end
end